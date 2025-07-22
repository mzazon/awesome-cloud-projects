# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  # Resource naming
  name_prefix       = "${var.project_name}-${var.environment}"
  random_suffix     = random_string.suffix.result
  input_bucket      = var.input_bucket_name != "" ? var.input_bucket_name : "${local.name_prefix}-input-${local.random_suffix}"
  output_bucket     = var.output_bucket_name != "" ? var.output_bucket_name : "${local.name_prefix}-output-${local.random_suffix}"
  lambda_name       = var.lambda_function_name != "" ? var.lambda_function_name : "${local.name_prefix}-processor-${local.random_suffix}"
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "DocumentSummarization"
  }
  
  # Lambda environment variables
  lambda_environment = {
    OUTPUT_BUCKET          = local.output_bucket
    BEDROCK_MODEL_ID       = var.bedrock_model_id
    BEDROCK_MAX_TOKENS     = tostring(var.bedrock_max_tokens)
    MAX_DOCUMENT_SIZE_MB   = tostring(var.max_document_size_mb)
    DOCUMENT_PREFIX        = var.document_prefix
    SNS_TOPIC_ARN         = var.enable_sns_notifications ? aws_sns_topic.notifications[0].arn : ""
  }
}

# KMS key for encryption (if enabled)
resource "aws_kms_key" "bucket_encryption" {
  count = var.enable_bucket_encryption ? 1 : 0
  
  description             = "KMS key for document summarization S3 bucket encryption"
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
    Name = "${local.name_prefix}-kms-key"
  })
}

resource "aws_kms_alias" "bucket_encryption" {
  count = var.enable_bucket_encryption ? 1 : 0
  
  name          = "alias/${local.name_prefix}-bucket-encryption"
  target_key_id = aws_kms_key.bucket_encryption[0].key_id
}

# S3 bucket for input documents
resource "aws_s3_bucket" "input_documents" {
  bucket        = local.input_bucket
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-input-bucket"
    Type = "DocumentInput"
  })
}

# S3 bucket versioning for input documents
resource "aws_s3_bucket_versioning" "input_documents" {
  bucket = aws_s3_bucket.input_documents.id
  
  versioning_configuration {
    status = var.enable_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption for input documents
resource "aws_s3_bucket_server_side_encryption_configuration" "input_documents" {
  count  = var.enable_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.input_documents.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.bucket_encryption[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for input documents
resource "aws_s3_bucket_public_access_block" "input_documents" {
  bucket = aws_s3_bucket.input_documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for input documents
resource "aws_s3_bucket_lifecycle_configuration" "input_documents" {
  count  = var.bucket_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.input_documents.id

  rule {
    id     = "document_lifecycle"
    status = "Enabled"

    transition {
      days          = var.bucket_lifecycle_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.bucket_lifecycle_days * 3
      storage_class = "GLACIER"
    }

    expiration {
      days = var.bucket_lifecycle_days * 12  # Keep for 1 year
    }
  }
}

# S3 bucket for output summaries
resource "aws_s3_bucket" "output_summaries" {
  bucket        = local.output_bucket
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-output-bucket"
    Type = "SummaryOutput"
  })
}

# S3 bucket versioning for output summaries
resource "aws_s3_bucket_versioning" "output_summaries" {
  bucket = aws_s3_bucket.output_summaries.id
  
  versioning_configuration {
    status = var.enable_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption for output summaries
resource "aws_s3_bucket_server_side_encryption_configuration" "output_summaries" {
  count  = var.enable_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.output_summaries.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.bucket_encryption[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for output summaries
resource "aws_s3_bucket_public_access_block" "output_summaries" {
  bucket = aws_s3_bucket.output_summaries.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for output summaries
resource "aws_s3_bucket_lifecycle_configuration" "output_summaries" {
  count  = var.bucket_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.output_summaries.id

  rule {
    id     = "summary_lifecycle"
    status = "Enabled"

    transition {
      days          = var.bucket_lifecycle_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.bucket_lifecycle_days * 2
      storage_class = "GLACIER"
    }
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role"

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
    Name = "${local.name_prefix}-lambda-role"
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_prefix}-lambda-policy"
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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.input_documents.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.output_summaries.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "textract:DetectDocumentText",
          "textract:AnalyzeDocument"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.bedrock_model_id}"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.enable_bucket_encryption ? aws_kms_key.bucket_encryption[0].arn : "*"
        Condition = var.enable_bucket_encryption ? {
          StringEquals = {
            "kms:ViaService" = "s3.${data.aws_region.current.name}.amazonaws.com"
          }
        } : null
      }
    ]
  })
}

# Attach additional policies for SNS if notifications are enabled
resource "aws_iam_role_policy" "lambda_sns_policy" {
  count = var.enable_sns_notifications ? 1 : 0
  name  = "${local.name_prefix}-lambda-sns-policy"
  role  = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.notifications[0].arn
      }
    ]
  })
}

# Lambda function source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      bedrock_model_id    = var.bedrock_model_id
      max_tokens          = var.bedrock_max_tokens
      max_doc_size_mb     = var.max_document_size_mb
      enable_sns          = var.enable_sns_notifications
    })
    filename = "lambda_function.py"
  }
  
  source {
    content  = "boto3>=1.26.0\nbotocore>=1.29.0"
    filename = "requirements.txt"
  }
}

# Lambda function
resource "aws_lambda_function" "document_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = local.lambda_environment
  }

  # Reserved concurrency if enabled
  reserved_concurrent_executions = var.enable_lambda_reserved_concurrency ? var.lambda_reserved_concurrency : null

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name = local.lambda_name
  })
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-logs"
  })
}

# Lambda permission for S3 to invoke the function
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.document_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input_documents.arn
}

# S3 bucket notification configuration
resource "aws_s3_bucket_notification" "input_notification" {
  bucket = aws_s3_bucket.input_documents.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.document_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.document_prefix
    filter_suffix       = ""
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}

# SNS topic for notifications (optional)
resource "aws_sns_topic" "notifications" {
  count = var.enable_sns_notifications ? 1 : 0
  name  = "${local.name_prefix}-notifications"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-notifications"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notifications" {
  count     = var.enable_sns_notifications ? 1 : 0
  topic_arn = aws_sns_topic.notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch dashboard for monitoring (optional)
resource "aws_cloudwatch_dashboard" "monitoring" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "${local.name_prefix}-monitoring"

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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.document_processor.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."],
            [".", "Throttles", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Lambda Function Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.input_documents.bucket, "StorageType", "AllStorageTypes"],
            [".", "BucketSizeBytes", ".", ".", ".", "."],
            [".", "NumberOfObjects", "BucketName", aws_s3_bucket.output_summaries.bucket, "StorageType", "AllStorageTypes"],
            [".", "BucketSizeBytes", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "S3 Storage Metrics"
          period  = 300
        }
      }
    ]
  })
}

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = var.enable_sns_notifications ? [aws_sns_topic.notifications[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.document_processor.function_name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-errors-alarm"
  })
}

# CloudWatch alarm for Lambda duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${local.name_prefix}-lambda-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = tostring(var.lambda_timeout * 1000 * 0.8)  # 80% of timeout
  alarm_description   = "This metric monitors lambda duration"
  alarm_actions       = var.enable_sns_notifications ? [aws_sns_topic.notifications[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.document_processor.function_name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-duration-alarm"
  })
}