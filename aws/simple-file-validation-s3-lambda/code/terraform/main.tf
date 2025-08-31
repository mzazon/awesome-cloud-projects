# =============================================================================
# Simple File Validation with S3 and Lambda - Main Configuration
# =============================================================================
# This Terraform configuration creates a serverless file validation system
# that automatically validates uploaded files based on type and size,
# moving valid files to an approved bucket and quarantining invalid ones.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
  required_version = ">= 1.0"
}

# Configure the AWS Provider with default tags
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# =============================================================================
# Random ID for Unique Resource Names
# =============================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  # Generate unique bucket names using random suffix
  upload_bucket_name     = "${var.project_name}-upload-${random_id.bucket_suffix.hex}"
  valid_bucket_name      = "${var.project_name}-valid-${random_id.bucket_suffix.hex}"
  quarantine_bucket_name = "${var.project_name}-quarantine-${random_id.bucket_suffix.hex}"
  lambda_function_name   = "${var.project_name}-validator-${random_id.bucket_suffix.hex}"

  # Common tags for all resources
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Purpose     = "file-validation"
    ManagedBy   = "terraform"
    Recipe      = "simple-file-validation-s3-lambda"
  }
}

# =============================================================================
# S3 Buckets for File Management
# =============================================================================

# Upload bucket - receives initial file uploads
resource "aws_s3_bucket" "upload" {
  bucket        = local.upload_bucket_name
  force_destroy = var.force_destroy_buckets

  tags = merge(local.common_tags, {
    Name        = "File Upload Bucket"
    Description = "Initial upload destination for file validation"
  })
}

# Valid files bucket - stores validated files
resource "aws_s3_bucket" "valid" {
  bucket        = local.valid_bucket_name
  force_destroy = var.force_destroy_buckets

  tags = merge(local.common_tags, {
    Name        = "Valid Files Bucket"
    Description = "Storage for files that passed validation"
  })
}

# Quarantine bucket - stores invalid or suspicious files
resource "aws_s3_bucket" "quarantine" {
  bucket        = local.quarantine_bucket_name
  force_destroy = var.force_destroy_buckets

  tags = merge(local.common_tags, {
    Name        = "Quarantine Bucket"
    Description = "Storage for files that failed validation"
  })
}

# =============================================================================
# S3 Bucket Configurations (Modular Approach)
# =============================================================================

# Enable versioning for upload bucket (data protection)
resource "aws_s3_bucket_versioning" "upload" {
  bucket = aws_s3_bucket.upload.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable versioning for valid files bucket
resource "aws_s3_bucket_versioning" "valid" {
  bucket = aws_s3_bucket.valid.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable versioning for quarantine bucket
resource "aws_s3_bucket_versioning" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption for upload bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "upload" {
  bucket = aws_s3_bucket.upload.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Server-side encryption for valid files bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "valid" {
  bucket = aws_s3_bucket.valid.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Server-side encryption for quarantine bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access for all buckets (security best practice)
resource "aws_s3_bucket_public_access_block" "upload" {
  bucket = aws_s3_bucket.upload.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "valid" {
  bucket = aws_s3_bucket.valid.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# IAM Role and Policies for Lambda Function
# =============================================================================

# Lambda execution role with least privilege principle
resource "aws_iam_role" "lambda_execution" {
  name = "${local.lambda_function_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "Lambda Execution Role"
    Description = "IAM role for file validation Lambda function"
  })
}

# Custom IAM policy for S3 and CloudWatch access
resource "aws_iam_policy" "lambda_s3_policy" {
  name        = "${local.lambda_function_name}-s3-policy"
  description = "IAM policy for file validation Lambda function S3 access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.upload.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "${aws_s3_bucket.valid.arn}/*",
          "${aws_s3_bucket.quarantine.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${local.lambda_function_name}*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach custom S3 policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_s3_policy" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

# =============================================================================
# CloudWatch Log Group for Lambda Function
# =============================================================================

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "Lambda Logs"
    Description = "CloudWatch logs for file validation Lambda function"
  })
}

# =============================================================================
# Lambda Function Package
# =============================================================================

# Create Lambda function code inline (for simplicity)
resource "local_file" "lambda_code" {
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    max_file_size_mb    = var.max_file_size_mb
    allowed_extensions  = jsonencode(var.allowed_file_extensions)
  })
  filename = "${path.module}/lambda_function.py"
}

# Create ZIP package for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content  = local_file.lambda_code.content
    filename = "lambda_function.py"
  }

  depends_on = [local_file.lambda_code]
}

# =============================================================================
# Lambda Function
# =============================================================================

resource "aws_lambda_function" "file_validator" {
  function_name = local.lambda_function_name
  role          = aws_iam_role.lambda_execution.arn

  # Package configuration
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"

  # Performance settings optimized for file processing
  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  # Environment variables for configuration
  environment {
    variables = {
      VALID_BUCKET_NAME      = aws_s3_bucket.valid.bucket
      QUARANTINE_BUCKET_NAME = aws_s3_bucket.quarantine.bucket
      MAX_FILE_SIZE_MB       = var.max_file_size_mb
      ALLOWED_EXTENSIONS     = jsonencode(var.allowed_file_extensions)
      LOG_LEVEL              = var.lambda_log_level
    }
  }

  # CloudWatch logging configuration
  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda_logs.name
  }

  tags = merge(local.common_tags, {
    Name        = "File Validation Function"
    Description = "Lambda function for automated file validation"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_s3_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# =============================================================================
# Lambda Permission for S3 to Invoke Function
# =============================================================================

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_validator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.upload.arn
}

# =============================================================================
# S3 Event Notification Configuration
# =============================================================================

resource "aws_s3_bucket_notification" "file_upload_notification" {
  bucket = aws_s3_bucket.upload.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.file_validator.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.s3_filter_prefix
    filter_suffix       = var.s3_filter_suffix
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}