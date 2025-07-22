# Main Terraform Configuration for Audio Processing Pipeline
# This file contains all the AWS resources needed for the audio processing pipeline

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Get MediaConvert endpoint for the current region
data "aws_mediaconvert_endpoint" "current" {}

# Local values for consistent naming
locals {
  suffix = random_string.suffix.result
  
  # Resource names with fallback to auto-generated names
  input_bucket_name       = var.input_bucket_name != "" ? var.input_bucket_name : "${var.project_name}-input-${local.suffix}"
  output_bucket_name      = var.output_bucket_name != "" ? var.output_bucket_name : "${var.project_name}-output-${local.suffix}"
  lambda_function_name    = var.lambda_function_name != "" ? var.lambda_function_name : "${var.project_name}-trigger-${local.suffix}"
  sns_topic_name          = var.sns_topic_name != "" ? var.sns_topic_name : "${var.project_name}-notifications-${local.suffix}"
  dashboard_name          = var.cloudwatch_dashboard_name != "" ? var.cloudwatch_dashboard_name : "${var.project_name}-pipeline-${local.suffix}"
  job_template_name       = var.mediaconvert_job_template_name != "" ? var.mediaconvert_job_template_name : "AudioProcessingTemplate-${local.suffix}"
  preset_name             = var.mediaconvert_preset_name != "" ? var.mediaconvert_preset_name : "EnhancedAudioPreset-${local.suffix}"
  
  # IAM role names
  mediaconvert_role_name = "MediaConvertRole-${local.suffix}"
  lambda_role_name       = "${local.lambda_function_name}-role"
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "audio-processing-pipelines-aws-elemental-mediaconvert"
  }
}

# =============================================================================
# KMS Key for S3 Bucket Encryption
# =============================================================================

resource "aws_kms_key" "s3_encryption" {
  count = var.s3_encryption_enabled ? 1 : 0
  
  description             = "KMS key for S3 bucket encryption in audio processing pipeline"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow S3 Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "S3-Encryption-Key-${local.suffix}"
  })
}

resource "aws_kms_alias" "s3_encryption" {
  count = var.s3_encryption_enabled ? 1 : 0
  
  name          = "alias/${var.project_name}-s3-encryption-${local.suffix}"
  target_key_id = aws_kms_key.s3_encryption[0].key_id
}

# =============================================================================
# S3 Buckets for Input and Output
# =============================================================================

# S3 bucket for input audio files
resource "aws_s3_bucket" "input" {
  bucket = local.input_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "Input-Bucket"
    Type = "Input"
  })
}

# S3 bucket for processed audio files
resource "aws_s3_bucket" "output" {
  bucket = local.output_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "Output-Bucket"
    Type = "Output"
  })
}

# Versioning configuration for input bucket
resource "aws_s3_bucket_versioning" "input" {
  bucket = aws_s3_bucket.input.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# Versioning configuration for output bucket
resource "aws_s3_bucket_versioning" "output" {
  bucket = aws_s3_bucket.output.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# Server-side encryption for input bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  count  = var.s3_encryption_enabled ? 1 : 0
  bucket = aws_s3_bucket.input.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_encryption[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# Server-side encryption for output bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  count  = var.s3_encryption_enabled ? 1 : 0
  bucket = aws_s3_bucket.output.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_encryption[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# Public access block for input bucket
resource "aws_s3_bucket_public_access_block" "input" {
  count  = var.enable_s3_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.input.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Public access block for output bucket
resource "aws_s3_bucket_public_access_block" "output" {
  count  = var.enable_s3_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket for access logs (if enabled)
resource "aws_s3_bucket" "access_logs" {
  count  = var.enable_s3_access_logging ? 1 : 0
  bucket = "${local.input_bucket_name}-access-logs"
  
  tags = merge(local.common_tags, {
    Name = "Access-Logs-Bucket"
    Type = "Logging"
  })
}

# Access logging for input bucket
resource "aws_s3_bucket_logging" "input" {
  count  = var.enable_s3_access_logging ? 1 : 0
  bucket = aws_s3_bucket.input.id

  target_bucket = aws_s3_bucket.access_logs[0].id
  target_prefix = "input-access-logs/"
}

# Access logging for output bucket
resource "aws_s3_bucket_logging" "output" {
  count  = var.enable_s3_access_logging ? 1 : 0
  bucket = aws_s3_bucket.output.id

  target_bucket = aws_s3_bucket.access_logs[0].id
  target_prefix = "output-access-logs/"
}

# =============================================================================
# SNS Topic for Notifications
# =============================================================================

resource "aws_sns_topic" "notifications" {
  name = local.sns_topic_name
  
  tags = merge(local.common_tags, {
    Name = "Processing-Notifications"
  })
}

# Email subscription for notifications (if email provided)
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# =============================================================================
# IAM Role for MediaConvert
# =============================================================================

# Trust policy for MediaConvert service
data "aws_iam_policy_document" "mediaconvert_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["mediaconvert.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# MediaConvert service role
resource "aws_iam_role" "mediaconvert" {
  name               = local.mediaconvert_role_name
  assume_role_policy = data.aws_iam_policy_document.mediaconvert_trust.json
  
  tags = merge(local.common_tags, {
    Name = "MediaConvert-Service-Role"
  })
}

# Policy for MediaConvert to access S3 and SNS
data "aws_iam_policy_document" "mediaconvert_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.input.arn,
      "${aws_s3_bucket.input.arn}/*",
      aws_s3_bucket.output.arn,
      "${aws_s3_bucket.output.arn}/*"
    ]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [aws_sns_topic.notifications.arn]
  }
  
  # KMS permissions for S3 encryption
  dynamic "statement" {
    for_each = var.s3_encryption_enabled ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ]
      resources = [aws_kms_key.s3_encryption[0].arn]
    }
  }
}

# Attach policy to MediaConvert role
resource "aws_iam_role_policy" "mediaconvert" {
  name   = "MediaConvertS3SNSPolicy"
  role   = aws_iam_role.mediaconvert.id
  policy = data.aws_iam_policy_document.mediaconvert_policy.json
}

# =============================================================================
# MediaConvert Job Template
# =============================================================================

resource "aws_media_convert_job_template" "audio_processing" {
  description = "Template for processing audio files with multiple output formats"
  name        = local.job_template_name
  
  settings_json = jsonencode({
    OutputGroups = [
      {
        Name = "MP3_Output"
        OutputGroupSettings = {
          Type = "FILE_GROUP_SETTINGS"
          FileGroupSettings = {
            Destination = "s3://${aws_s3_bucket.output.bucket}/mp3/"
          }
        }
        Outputs = [
          {
            NameModifier = "_mp3"
            ContainerSettings = {
              Container = "MP3"
            }
            AudioDescriptions = [
              {
                AudioTypeControl = "FOLLOW_INPUT"
                CodecSettings = {
                  Codec = "MP3"
                  Mp3Settings = {
                    Bitrate         = var.audio_bitrate_mp3
                    Channels        = var.audio_channels
                    RateControlMode = "CBR"
                    SampleRate      = var.audio_sample_rate
                  }
                }
              }
            ]
          }
        ]
      },
      {
        Name = "AAC_Output"
        OutputGroupSettings = {
          Type = "FILE_GROUP_SETTINGS"
          FileGroupSettings = {
            Destination = "s3://${aws_s3_bucket.output.bucket}/aac/"
          }
        }
        Outputs = [
          {
            NameModifier = "_aac"
            ContainerSettings = {
              Container = "MP4"
            }
            AudioDescriptions = [
              {
                AudioTypeControl = "FOLLOW_INPUT"
                CodecSettings = {
                  Codec = "AAC"
                  AacSettings = {
                    Bitrate     = var.audio_bitrate_aac
                    CodingMode  = "CODING_MODE_2_0"
                    SampleRate  = var.audio_sample_rate
                  }
                }
              }
            ]
          }
        ]
      },
      {
        Name = "FLAC_Output"
        OutputGroupSettings = {
          Type = "FILE_GROUP_SETTINGS"
          FileGroupSettings = {
            Destination = "s3://${aws_s3_bucket.output.bucket}/flac/"
          }
        }
        Outputs = [
          {
            NameModifier = "_flac"
            ContainerSettings = {
              Container = "FLAC"
            }
            AudioDescriptions = [
              {
                AudioTypeControl = "FOLLOW_INPUT"
                CodecSettings = {
                  Codec = "FLAC"
                  FlacSettings = {
                    Channels   = var.audio_channels
                    SampleRate = var.audio_sample_rate
                  }
                }
              }
            ]
          }
        ]
      }
    ]
    Inputs = [
      {
        FileInput = "s3://${aws_s3_bucket.input.bucket}/"
        AudioSelectors = {
          "Audio Selector 1" = {
            Tracks          = [1]
            DefaultSelection = "DEFAULT"
          }
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "Audio-Processing-Template"
  })
}

# =============================================================================
# MediaConvert Preset for Enhanced Audio
# =============================================================================

resource "aws_media_convert_preset" "enhanced_audio" {
  category    = "Custom"
  description = "Preset for enhanced audio processing with noise reduction"
  name        = local.preset_name
  
  settings_json = jsonencode({
    ContainerSettings = {
      Container = "MP4"
    }
    AudioDescriptions = [
      {
        AudioTypeControl = "FOLLOW_INPUT"
        CodecSettings = {
          Codec = "AAC"
          AacSettings = {
            Bitrate       = 192000
            CodingMode    = "CODING_MODE_2_0"
            SampleRate    = 48000
            Specification = "MPEG4"
          }
        }
        AudioNormalizationSettings = {
          Algorithm         = "ITU_BS_1770_2"
          AlgorithmControl  = "CORRECT_AUDIO"
          LoudnessLogging   = "LOG"
          PeakCalculation   = "TRUE_PEAK"
          TargetLkfs        = var.loudness_target_lkfs
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "Enhanced-Audio-Preset"
  })
}

# =============================================================================
# Lambda Function for Processing Trigger
# =============================================================================

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "Lambda-Log-Group"
  })
}

# IAM role for Lambda function
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = local.lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  
  tags = merge(local.common_tags, {
    Name = "Lambda-Execution-Role"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy for Lambda to access MediaConvert
data "aws_iam_policy_document" "lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "mediaconvert:CreateJob",
      "mediaconvert:GetJob",
      "mediaconvert:ListJobs"
    ]
    resources = ["*"]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [aws_iam_role.mediaconvert.arn]
  }
  
  # KMS permissions for S3 decryption
  dynamic "statement" {
    for_each = var.s3_encryption_enabled ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ]
      resources = [aws_kms_key.s3_encryption[0].arn]
    }
  }
}

# Attach MediaConvert policy to Lambda role
resource "aws_iam_role_policy" "lambda" {
  name   = "MediaConvertAccess"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

# Lambda function code
data "archive_file" "lambda" {
  type        = "zip"
  output_path = "/tmp/lambda_function.zip"
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      mediaconvert_endpoint = data.aws_mediaconvert_endpoint.current.endpoint_url
      template_arn          = aws_media_convert_job_template.audio_processing.arn
      mediaconvert_role_arn = aws_iam_role.mediaconvert.arn
    })
    filename = "lambda_function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "audio_processor" {
  filename         = data.archive_file.lambda.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda.output_base64sha256
  
  environment {
    variables = {
      MEDIACONVERT_ENDPOINT = data.aws_mediaconvert_endpoint.current.endpoint_url
      TEMPLATE_ARN          = aws_media_convert_job_template.audio_processing.arn
      MEDIACONVERT_ROLE_ARN = aws_iam_role.mediaconvert.arn
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.lambda,
  ]
  
  tags = merge(local.common_tags, {
    Name = "Audio-Processing-Trigger"
  })
}

# =============================================================================
# S3 Event Notifications
# =============================================================================

# Lambda permission for S3 to invoke function
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.audio_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input.arn
}

# S3 bucket notification configuration
resource "aws_s3_bucket_notification" "input_bucket" {
  bucket = aws_s3_bucket.input.id

  dynamic "lambda_function" {
    for_each = var.supported_audio_extensions
    content {
      lambda_function_arn = aws_lambda_function.audio_processor.arn
      events              = ["s3:ObjectCreated:*"]
      filter_suffix       = ".${lambda_function.value}"
    }
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

resource "aws_cloudwatch_dashboard" "audio_pipeline" {
  dashboard_name = local.dashboard_name

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/MediaConvert", "JobsCompleted"],
            [".", "JobsErrored"],
            [".", "JobsSubmitted"]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "MediaConvert Jobs"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", local.lambda_function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Lambda Function Metrics"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.input.bucket, "StorageType", "StandardStorage"],
            [".", ".", ".", aws_s3_bucket.output.bucket, ".", "."],
            [".", "NumberOfObjects", ".", aws_s3_bucket.input.bucket, ".", "AllStorageTypes"],
            [".", ".", ".", aws_s3_bucket.output.bucket, ".", "."]
          ]
          period = 86400
          stat   = "Average"
          region = var.aws_region
          title  = "S3 Storage Metrics"
        }
      }
    ]
  })
}

# =============================================================================
# Lambda Function Source Code Template
# =============================================================================

# Create the Lambda function source code file
resource "local_file" "lambda_function" {
  filename = "${path.module}/lambda_function.py"
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    mediaconvert_endpoint = data.aws_mediaconvert_endpoint.current.endpoint_url
    template_arn          = aws_media_convert_job_template.audio_processing.arn
    mediaconvert_role_arn = aws_iam_role.mediaconvert.arn
  })
}