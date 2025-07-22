# Multi-Language Voice Processing Pipeline Infrastructure
# This file creates the complete infrastructure for processing voice content
# through language detection, transcription, translation, and speech synthesis

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  resource_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "multi-language-voice-processing-pipelines"
    },
    var.additional_tags
  )
}

# ============================================================================
# KMS Key for Encryption
# ============================================================================

# KMS key for encrypting sensitive data across all services
resource "aws_kms_key" "voice_processing" {
  count = var.enable_encryption ? 1 : 0
  
  description             = "KMS key for voice processing pipeline encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow voice processing services"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "states.amazonaws.com",
            "s3.amazonaws.com",
            "dynamodb.amazonaws.com",
            "logs.amazonaws.com"
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = local.common_tags
}

# KMS key alias for easier reference
resource "aws_kms_alias" "voice_processing" {
  count = var.enable_encryption ? 1 : 0
  
  name          = "alias/${local.resource_prefix}-voice-processing"
  target_key_id = aws_kms_key.voice_processing[0].key_id
}

# ============================================================================
# S3 Buckets for Audio Processing
# ============================================================================

# S3 bucket for input audio files
resource "aws_s3_bucket" "input" {
  bucket        = "${local.resource_prefix}-input"
  force_destroy = var.s3_bucket_force_destroy
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-input"
    Purpose     = "Audio input files"
    DataType    = "Audio"
  })
}

# S3 bucket for output audio files
resource "aws_s3_bucket" "output" {
  bucket        = "${local.resource_prefix}-output"
  force_destroy = var.s3_bucket_force_destroy
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-output"
    Purpose     = "Processed audio files"
    DataType    = "Audio"
  })
}

# S3 bucket versioning for input bucket
resource "aws_s3_bucket_versioning" "input" {
  bucket = aws_s3_bucket.input.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket versioning for output bucket
resource "aws_s3_bucket_versioning" "output" {
  bucket = aws_s3_bucket.output.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption for input bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  bucket = aws_s3_bucket.input.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_encryption ? aws_kms_key.voice_processing[0].arn : null
    }
    bucket_key_enabled = var.enable_encryption
  }
}

# S3 bucket server-side encryption for output bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  bucket = aws_s3_bucket.output.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_encryption ? aws_kms_key.voice_processing[0].arn : null
    }
    bucket_key_enabled = var.enable_encryption
  }
}

# S3 bucket public access block for input bucket
resource "aws_s3_bucket_public_access_block" "input" {
  bucket = aws_s3_bucket.input.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket public access block for output bucket
resource "aws_s3_bucket_public_access_block" "output" {
  bucket = aws_s3_bucket.output.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for input bucket
resource "aws_s3_bucket_lifecycle_configuration" "input" {
  bucket = aws_s3_bucket.input.id
  
  rule {
    id     = "input_lifecycle"
    status = "Enabled"
    
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    
    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }
  }
}

# S3 bucket lifecycle configuration for output bucket
resource "aws_s3_bucket_lifecycle_configuration" "output" {
  bucket = aws_s3_bucket.output.id
  
  rule {
    id     = "output_lifecycle"
    status = "Enabled"
    
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# ============================================================================
# DynamoDB Table for Job Tracking
# ============================================================================

# DynamoDB table for tracking voice processing jobs
resource "aws_dynamodb_table" "jobs" {
  name           = "${local.resource_prefix}-jobs"
  billing_mode   = var.dynamodb_billing_mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  hash_key       = "JobId"
  
  attribute {
    name = "JobId"
    type = "S"
  }
  
  attribute {
    name = "Status"
    type = "S"
  }
  
  # Global secondary index for querying jobs by status
  global_secondary_index {
    name            = "StatusIndex"
    hash_key        = "Status"
    projection_type = "ALL"
    
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }
  
  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }
  
  # Server-side encryption
  server_side_encryption {
    enabled     = var.enable_encryption
    kms_key_arn = var.enable_encryption ? aws_kms_key.voice_processing[0].arn : null
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-jobs"
    Purpose     = "Job tracking and metadata"
    DataType    = "Metadata"
  })
}

# ============================================================================
# SNS Topic for Notifications
# ============================================================================

# SNS topic for job notifications
resource "aws_sns_topic" "notifications" {
  count = var.enable_sns_notifications ? 1 : 0
  
  name              = "${local.resource_prefix}-notifications"
  kms_master_key_id = var.enable_encryption ? aws_kms_key.voice_processing[0].arn : null
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-notifications"
    Purpose     = "Job notifications"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email" {
  count = var.enable_sns_notifications && var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ============================================================================
# SQS Queue for Processing
# ============================================================================

# SQS queue for processing jobs
resource "aws_sqs_queue" "processing" {
  name                       = "${local.resource_prefix}-processing"
  message_retention_seconds  = 1209600  # 14 days
  receive_wait_time_seconds  = 20       # Long polling
  visibility_timeout_seconds = var.lambda_timeout * 6  # 6x Lambda timeout
  
  # Dead letter queue configuration
  redrive_policy = var.enable_dead_letter_queue ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = 3
  }) : null
  
  # Server-side encryption
  kms_master_key_id                 = var.enable_encryption ? aws_kms_key.voice_processing[0].arn : null
  kms_data_key_reuse_period_seconds = var.enable_encryption ? 300 : null
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-processing"
    Purpose     = "Processing queue"
  })
}

# Dead letter queue for failed processing jobs
resource "aws_sqs_queue" "dlq" {
  count = var.enable_dead_letter_queue ? 1 : 0
  
  name                      = "${local.resource_prefix}-dlq"
  message_retention_seconds = 1209600  # 14 days
  
  # Server-side encryption
  kms_master_key_id                 = var.enable_encryption ? aws_kms_key.voice_processing[0].arn : null
  kms_data_key_reuse_period_seconds = var.enable_encryption ? 300 : null
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-dlq"
    Purpose     = "Dead letter queue"
  })
}

# ============================================================================
# CloudWatch Log Groups
# ============================================================================

# CloudWatch log group for Lambda functions
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = toset([
    "language-detector",
    "transcription-processor",
    "translation-processor",
    "speech-synthesizer",
    "job-status-checker"
  ])
  
  name              = "/aws/lambda/${local.resource_prefix}-${each.key}"
  retention_in_days = var.cloudwatch_retention_days
  kms_key_id        = var.enable_encryption ? aws_kms_key.voice_processing[0].arn : null
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-${each.key}-logs"
    Purpose     = "Lambda function logs"
  })
}

# CloudWatch log group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/stepfunctions/${local.resource_prefix}-voice-processing"
  retention_in_days = var.cloudwatch_retention_days
  kms_key_id        = var.enable_encryption ? aws_kms_key.voice_processing[0].arn : null
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-stepfunctions-logs"
    Purpose     = "Step Functions logs"
  })
}

# ============================================================================
# IAM Roles and Policies
# ============================================================================

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${local.resource_prefix}-lambda-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-lambda-role"
    Purpose     = "Lambda execution role"
  })
}

# IAM policy for Lambda functions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.resource_prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.resource_prefix}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.input.arn,
          "${aws_s3_bucket.input.arn}/*",
          aws_s3_bucket.output.arn,
          "${aws_s3_bucket.output.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.jobs.arn,
          "${aws_dynamodb_table.jobs.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "transcribe:StartTranscriptionJob",
          "transcribe:GetTranscriptionJob",
          "transcribe:ListTranscriptionJobs",
          "transcribe:GetVocabulary",
          "transcribe:ListVocabularies"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "translate:TranslateText",
          "translate:GetTerminology",
          "translate:ListTerminologies"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "polly:SynthesizeSpeech",
          "polly:DescribeVoices"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.enable_sns_notifications ? aws_sns_topic.notifications[0].arn : null
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.processing.arn,
          var.enable_dead_letter_queue ? aws_sqs_queue.dlq[0].arn : null
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = var.enable_encryption ? [aws_kms_key.voice_processing[0].arn] : []
      }
    ]
  })
}

# Attach AWS managed policy for X-Ray tracing
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count = var.enable_x_ray_tracing ? 1 : 0
  
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# IAM role for Step Functions
resource "aws_iam_role" "step_functions_role" {
  name = "${local.resource_prefix}-step-functions-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-step-functions-role"
    Purpose     = "Step Functions execution role"
  })
}

# IAM policy for Step Functions
resource "aws_iam_role_policy" "step_functions_policy" {
  name = "${local.resource_prefix}-step-functions-policy"
  role = aws_iam_role.step_functions_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.language_detector.arn,
          aws_lambda_function.transcription_processor.arn,
          aws_lambda_function.translation_processor.arn,
          aws_lambda_function.speech_synthesizer.arn,
          aws_lambda_function.job_status_checker.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach AWS managed policy for X-Ray tracing to Step Functions
resource "aws_iam_role_policy_attachment" "step_functions_xray" {
  count = var.enable_x_ray_tracing ? 1 : 0
  
  role       = aws_iam_role.step_functions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ============================================================================
# Lambda Function Source Code
# ============================================================================

# Create Lambda function source code archives
data "archive_file" "language_detector" {
  type        = "zip"
  output_path = "${path.module}/language_detector.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/language_detector.py", {
      jobs_table_name = aws_dynamodb_table.jobs.name
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "transcription_processor" {
  type        = "zip"
  output_path = "${path.module}/transcription_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/transcription_processor.py", {
      jobs_table_name = aws_dynamodb_table.jobs.name
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "translation_processor" {
  type        = "zip"
  output_path = "${path.module}/translation_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/translation_processor.py", {
      jobs_table_name = aws_dynamodb_table.jobs.name
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "speech_synthesizer" {
  type        = "zip"
  output_path = "${path.module}/speech_synthesizer.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/speech_synthesizer.py", {
      jobs_table_name = aws_dynamodb_table.jobs.name
      voice_preferences = jsonencode(var.polly_voice_preferences)
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "job_status_checker" {
  type        = "zip"
  output_path = "${path.module}/job_status_checker.zip"
  
  source {
    content = file("${path.module}/lambda_functions/job_status_checker.py")
    filename = "lambda_function.py"
  }
}

# ============================================================================
# Lambda Functions
# ============================================================================

# Language Detection Lambda Function
resource "aws_lambda_function" "language_detector" {
  filename         = data.archive_file.language_detector.output_path
  function_name    = "${local.resource_prefix}-language-detector"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.language_detector.output_base64sha256
  
  environment {
    variables = {
      JOBS_TABLE_NAME = aws_dynamodb_table.jobs.name
      INPUT_BUCKET    = aws_s3_bucket.input.bucket
      OUTPUT_BUCKET   = aws_s3_bucket.output.bucket
    }
  }
  
  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_x_ray_tracing ? "Active" : "PassThrough"
  }
  
  # Dead letter queue configuration
  dead_letter_config {
    target_arn = var.enable_dead_letter_queue ? aws_sqs_queue.dlq[0].arn : null
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-language-detector"
    Purpose     = "Language detection"
  })
  
  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# Transcription Processor Lambda Function
resource "aws_lambda_function" "transcription_processor" {
  filename         = data.archive_file.transcription_processor.output_path
  function_name    = "${local.resource_prefix}-transcription-processor"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.transcription_processor.output_base64sha256
  
  environment {
    variables = {
      JOBS_TABLE_NAME = aws_dynamodb_table.jobs.name
      INPUT_BUCKET    = aws_s3_bucket.input.bucket
      OUTPUT_BUCKET   = aws_s3_bucket.output.bucket
    }
  }
  
  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_x_ray_tracing ? "Active" : "PassThrough"
  }
  
  # Dead letter queue configuration
  dead_letter_config {
    target_arn = var.enable_dead_letter_queue ? aws_sqs_queue.dlq[0].arn : null
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-transcription-processor"
    Purpose     = "Speech transcription"
  })
  
  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# Translation Processor Lambda Function
resource "aws_lambda_function" "translation_processor" {
  filename         = data.archive_file.translation_processor.output_path
  function_name    = "${local.resource_prefix}-translation-processor"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.translation_processor.output_base64sha256
  
  environment {
    variables = {
      JOBS_TABLE_NAME = aws_dynamodb_table.jobs.name
      INPUT_BUCKET    = aws_s3_bucket.input.bucket
      OUTPUT_BUCKET   = aws_s3_bucket.output.bucket
    }
  }
  
  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_x_ray_tracing ? "Active" : "PassThrough"
  }
  
  # Dead letter queue configuration
  dead_letter_config {
    target_arn = var.enable_dead_letter_queue ? aws_sqs_queue.dlq[0].arn : null
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-translation-processor"
    Purpose     = "Text translation"
  })
  
  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# Speech Synthesizer Lambda Function
resource "aws_lambda_function" "speech_synthesizer" {
  filename         = data.archive_file.speech_synthesizer.output_path
  function_name    = "${local.resource_prefix}-speech-synthesizer"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.speech_synthesizer.output_base64sha256
  
  environment {
    variables = {
      JOBS_TABLE_NAME = aws_dynamodb_table.jobs.name
      INPUT_BUCKET    = aws_s3_bucket.input.bucket
      OUTPUT_BUCKET   = aws_s3_bucket.output.bucket
    }
  }
  
  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_x_ray_tracing ? "Active" : "PassThrough"
  }
  
  # Dead letter queue configuration
  dead_letter_config {
    target_arn = var.enable_dead_letter_queue ? aws_sqs_queue.dlq[0].arn : null
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-speech-synthesizer"
    Purpose     = "Speech synthesis"
  })
  
  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# Job Status Checker Lambda Function
resource "aws_lambda_function" "job_status_checker" {
  filename         = data.archive_file.job_status_checker.output_path
  function_name    = "${local.resource_prefix}-job-status-checker"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  memory_size     = 256
  source_code_hash = data.archive_file.job_status_checker.output_base64sha256
  
  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_x_ray_tracing ? "Active" : "PassThrough"
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-job-status-checker"
    Purpose     = "Job status monitoring"
  })
  
  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# ============================================================================
# Step Functions State Machine
# ============================================================================

# Step Functions state machine for voice processing workflow
resource "aws_sfn_state_machine" "voice_processing" {
  name       = "${local.resource_prefix}-voice-processing"
  role_arn   = aws_iam_role.step_functions_role.arn
  definition = templatefile("${path.module}/step_functions/voice_processing_workflow.json", {
    language_detector_arn       = aws_lambda_function.language_detector.arn
    transcription_processor_arn = aws_lambda_function.transcription_processor.arn
    translation_processor_arn   = aws_lambda_function.translation_processor.arn
    speech_synthesizer_arn      = aws_lambda_function.speech_synthesizer.arn
    job_status_checker_arn      = aws_lambda_function.job_status_checker.arn
    jobs_table_name             = aws_dynamodb_table.jobs.name
    target_languages            = jsonencode(var.target_languages)
  })
  
  # Logging configuration
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = var.step_function_logging_level
  }
  
  # X-Ray tracing configuration
  tracing_configuration {
    enabled = var.enable_x_ray_tracing
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-voice-processing"
    Purpose     = "Voice processing workflow"
  })
}

# ============================================================================
# API Gateway (Optional)
# ============================================================================

# API Gateway REST API for voice processing
resource "aws_api_gateway_rest_api" "voice_processing" {
  count = var.enable_api_gateway ? 1 : 0
  
  name        = "${local.resource_prefix}-voice-processing-api"
  description = "API for voice processing pipeline"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-voice-processing-api"
    Purpose     = "Voice processing API"
  })
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "voice_processing" {
  count = var.enable_api_gateway ? 1 : 0
  
  depends_on = [
    aws_api_gateway_rest_api.voice_processing
  ]
  
  rest_api_id = aws_api_gateway_rest_api.voice_processing[0].id
  
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_rest_api.voice_processing[0].body,
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "voice_processing" {
  count = var.enable_api_gateway ? 1 : 0
  
  deployment_id = aws_api_gateway_deployment.voice_processing[0].id
  rest_api_id   = aws_api_gateway_rest_api.voice_processing[0].id
  stage_name    = var.api_gateway_stage_name
  
  # X-Ray tracing configuration
  xray_tracing_enabled = var.enable_x_ray_tracing
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-voice-processing-stage"
    Purpose     = "Voice processing API stage"
  })
}

# ============================================================================
# CloudWatch Alarms and Monitoring
# ============================================================================

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset([
    "language-detector",
    "transcription-processor", 
    "translation-processor",
    "speech-synthesizer",
    "job-status-checker"
  ])
  
  alarm_name          = "${local.resource_prefix}-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Lambda function errors for ${each.key}"
  alarm_actions       = var.enable_sns_notifications ? [aws_sns_topic.notifications[0].arn] : []
  
  dimensions = {
    FunctionName = "${local.resource_prefix}-${each.key}"
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-${each.key}-errors-alarm"
    Purpose     = "Lambda error monitoring"
  })
}

# CloudWatch alarm for Step Functions failed executions
resource "aws_cloudwatch_metric_alarm" "step_functions_failures" {
  alarm_name          = "${local.resource_prefix}-step-functions-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Step Functions execution failures"
  alarm_actions       = var.enable_sns_notifications ? [aws_sns_topic.notifications[0].arn] : []
  
  dimensions = {
    StateMachineArn = aws_sfn_state_machine.voice_processing.arn
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-step-functions-failures-alarm"
    Purpose     = "Step Functions failure monitoring"
  })
}

# CloudWatch alarm for DynamoDB throttling
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttling" {
  alarm_name          = "${local.resource_prefix}-dynamodb-throttling"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReadThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors DynamoDB throttling events"
  alarm_actions       = var.enable_sns_notifications ? [aws_sns_topic.notifications[0].arn] : []
  
  dimensions = {
    TableName = aws_dynamodb_table.jobs.name
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-dynamodb-throttling-alarm"
    Purpose     = "DynamoDB throttling monitoring"
  })
}

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "voice_processing" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  dashboard_name = "${local.resource_prefix}-voice-processing-dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${local.resource_prefix}-language-detector"],
            [".", "Duration", ".", "."],
            [".", "Errors", ".", "."],
            [".", "Throttles", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Language Detector Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", aws_sfn_state_machine.voice_processing.arn],
            [".", "ExecutionsFailed", ".", "."],
            [".", "ExecutionsTimedOut", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Step Functions Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.jobs.name],
            [".", "ConsumedWriteCapacityUnits", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "DynamoDB Metrics"
          period  = 300
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-voice-processing-dashboard"
    Purpose     = "Voice processing monitoring dashboard"
  })
}