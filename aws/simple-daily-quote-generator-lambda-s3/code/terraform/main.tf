# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming
locals {
  name_suffix = var.resource_name_suffix != "" ? var.resource_name_suffix : random_id.suffix.hex
  bucket_name = "${var.s3_bucket_prefix}-${local.name_suffix}"
  
  common_tags = {
    Project     = "simple-daily-quote-generator"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Data source to get current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# S3 bucket for storing quote data
resource "aws_s3_bucket" "quotes_bucket" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Description = "S3 bucket for storing daily quotes JSON data"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "quotes_bucket_versioning" {
  bucket = aws_s3_bucket.quotes_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "quotes_bucket_encryption" {
  bucket = aws_s3_bucket.quotes_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "quotes_bucket_pab" {
  bucket = aws_s3_bucket.quotes_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "quotes_bucket_lifecycle" {
  count  = var.enable_cost_optimization ? 1 : 0
  bucket = aws_s3_bucket.quotes_bucket.id

  rule {
    id     = "intelligent_tiering"
    status = "Enabled"

    transition {
      days          = 1
      storage_class = "INTELLIGENT_TIERING"
    }
  }
}

# Upload quotes data to S3 bucket
resource "aws_s3_object" "quotes_data" {
  bucket  = aws_s3_bucket.quotes_bucket.id
  key     = "quotes.json"
  content = jsonencode(var.quotes_data)
  
  content_type = "application/json"
  etag         = md5(jsonencode(var.quotes_data))

  tags = merge(local.common_tags, {
    Name        = "quotes.json"
    Description = "JSON file containing inspirational quotes"
  })
}

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-s3-role-${local.name_suffix}"

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
    Name        = "lambda-s3-role-${local.name_suffix}"
    Description = "IAM role for Lambda function to access S3 and CloudWatch Logs"
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom IAM policy for S3 read access
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "S3ReadPolicy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.quotes_bucket.arn}/*"
      }
    ]
  })
}

# Create Lambda function code as a zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      bucket_name = aws_s3_bucket.quotes_bucket.id
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for quote generation
resource "aws_lambda_function" "quote_generator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.quotes_bucket.id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_s3_policy,
    aws_s3_object.quotes_data,
  ]

  tags = merge(local.common_tags, {
    Name        = var.lambda_function_name
    Description = "Lambda function to serve random inspirational quotes from S3"
  })
}

# Lambda function URL for direct HTTP access
resource "aws_lambda_function_url" "quote_generator_url" {
  function_name      = aws_lambda_function.quote_generator.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = var.cors_allow_origins
    allow_methods     = var.cors_allow_methods
    allow_headers     = ["*"]
    expose_headers    = ["date", "keep-alive"]
    max_age          = var.cors_max_age
  }

  depends_on = [aws_lambda_function.quote_generator]
}

# CloudWatch Log Group for Lambda function (explicit creation for better control)
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name        = "/aws/lambda/${var.lambda_function_name}"
    Description = "CloudWatch log group for Lambda function logs"
  })
}