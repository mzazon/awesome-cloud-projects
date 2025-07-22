# Terraform configuration for AWS Intelligent Document Processing with Amazon Textract
# This configuration creates a complete document processing pipeline using:
# - S3 bucket for document storage and results
# - Lambda function for document processing with Textract
# - IAM roles and policies for secure access
# - CloudWatch monitoring and logging
# - Event-driven architecture with S3 notifications

# Data source to get current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common tags applied to all resources for resource management and cost tracking
  common_tags = merge(var.tags, {
    Project     = "TextractDocumentProcessing"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "intelligent-document-processing-amazon-textract"
  })
  
  # Resource naming with consistent prefix and unique suffix
  name_prefix = "${var.project_name}-${var.environment}"
  random_suffix = lower(random_id.suffix.hex)
}

# S3 bucket for storing documents and processing results
resource "aws_s3_bucket" "textract_documents" {
  bucket = "${local.name_prefix}-textract-documents-${local.random_suffix}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-textract-documents-${local.random_suffix}"
    Type = "DocumentStorage"
  })
}

# Enable versioning on the S3 bucket for document history and audit compliance
resource "aws_s3_bucket_versioning" "textract_documents" {
  bucket = aws_s3_bucket.textract_documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption configuration for data protection
resource "aws_s3_bucket_server_side_encryption_configuration" "textract_documents" {
  bucket = aws_s3_bucket.textract_documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block all public access to ensure document security
resource "aws_s3_bucket_public_access_block" "textract_documents" {
  bucket = aws_s3_bucket.textract_documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create folder structure in S3 bucket for organization
resource "aws_s3_object" "documents_folder" {
  bucket = aws_s3_bucket.textract_documents.id
  key    = "${var.documents_prefix}/"
  content = ""
  content_type = "application/x-directory"
  
  tags = local.common_tags
}

resource "aws_s3_object" "results_folder" {
  bucket = aws_s3_bucket.textract_documents.id
  key    = "${var.results_prefix}/"
  content = ""
  content_type = "application/x-directory"
  
  tags = local.common_tags
}

# IAM role for Lambda function execution
resource "aws_iam_role" "textract_processor_role" {
  name = "${local.name_prefix}-textract-processor-role-${local.random_suffix}"
  
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
    Name = "${local.name_prefix}-textract-processor-role-${local.random_suffix}"
    Type = "LambdaExecutionRole"
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.textract_processor_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom IAM policy for S3 and Textract access with least privilege principle
resource "aws_iam_policy" "textract_processor_policy" {
  name        = "${local.name_prefix}-textract-processor-policy-${local.random_suffix}"
  description = "Policy for Textract document processor Lambda function"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.textract_documents.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "textract:DetectDocumentText",
          "textract:AnalyzeDocument"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach custom policy to Lambda execution role
resource "aws_iam_role_policy_attachment" "textract_processor_policy" {
  role       = aws_iam_role.textract_processor_role.name
  policy_arn = aws_iam_policy.textract_processor_policy.arn
}

# CloudWatch Log Group for Lambda function with configurable retention
resource "aws_cloudwatch_log_group" "textract_processor_logs" {
  name              = "/aws/lambda/${local.name_prefix}-textract-processor-${local.random_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-textract-processor-logs"
    Type = "LogGroup"
  })
}

# Lambda function for document processing with Textract
resource "aws_lambda_function" "textract_processor" {
  function_name = "${local.name_prefix}-textract-processor-${local.random_suffix}"
  role         = aws_iam_role.textract_processor_role.arn
  handler      = "lambda_function.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  memory_size  = var.lambda_memory_size
  
  # Lambda function code with template interpolation for configuration
  filename         = "lambda_function.zip"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  # Environment variables for configuration
  environment {
    variables = {
      BUCKET_NAME        = aws_s3_bucket.textract_documents.id
      DOCUMENTS_PREFIX   = var.documents_prefix
      RESULTS_PREFIX     = var.results_prefix
      TEXTRACT_API_VERSION = var.textract_api_version
      SUPPORTED_FORMATS  = join(",", var.supported_formats)
      LOG_LEVEL         = var.log_level
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.textract_processor_policy,
    aws_cloudwatch_log_group.textract_processor_logs,
  ]
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-textract-processor-${local.random_suffix}"
    Type = "DocumentProcessorFunction"
  })
}

# Create Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      bucket_name       = aws_s3_bucket.textract_documents.id
      documents_prefix  = var.documents_prefix
      results_prefix    = var.results_prefix
      supported_formats = var.supported_formats
    })
    filename = "lambda_function.py"
  }
}

# Lambda permission to allow S3 to invoke the function
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.textract_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.textract_documents.arn
}

# S3 bucket notification to trigger Lambda function on document upload
resource "aws_s3_bucket_notification" "textract_processor_trigger" {
  bucket = aws_s3_bucket.textract_documents.id
  
  lambda_function {
    lambda_function_arn = aws_lambda_function.textract_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "${var.documents_prefix}/"
    filter_suffix       = ""
  }
  
  depends_on = [aws_lambda_permission.allow_s3]
}

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-textract-processor-errors-${local.random_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.error_threshold
  alarm_description   = "This metric monitors lambda errors for Textract processor"
  alarm_actions       = var.alarm_actions
  
  dimensions = {
    FunctionName = aws_lambda_function.textract_processor.function_name
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-textract-processor-errors"
    Type = "ErrorAlarm"
  })
}

# CloudWatch alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration_alarm" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-textract-processor-duration-${local.random_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = var.duration_threshold
  alarm_description   = "This metric monitors lambda duration for Textract processor"
  alarm_actions       = var.alarm_actions
  
  dimensions = {
    FunctionName = aws_lambda_function.textract_processor.function_name
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-textract-processor-duration"
    Type = "DurationAlarm"
  })
}