# Main Terraform configuration for Custom CloudFormation Resources with Lambda-backed Custom Resources

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix  = "${var.project_name}-${var.environment}"
  random_suffix = random_id.suffix.hex
  
  # Common tags merged with user-provided tags
  common_tags = merge(var.tags, {
    Project     = "CustomResourceDemo"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "custom-cloudformation-resources-lambda-backed-custom-resources"
  })
}

# S3 bucket for demonstration data storage
resource "aws_s3_bucket" "demo_bucket" {
  bucket = "${local.name_prefix}-data-${local.random_suffix}"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-data-bucket"
    Description = "S3 bucket for custom resource demonstration data"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "demo_bucket_versioning" {
  bucket = aws_s3_bucket.demo_bucket.id
  
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "demo_bucket_encryption" {
  bucket = aws_s3_bucket.demo_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "demo_bucket_pab" {
  bucket = aws_s3_bucket.demo_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "demo_bucket_lifecycle" {
  depends_on = [aws_s3_bucket_versioning.demo_bucket_versioning]
  bucket     = aws_s3_bucket.demo_bucket.id

  rule {
    id     = "delete_old_versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.s3_lifecycle_expiration_days
    }
  }
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role-${local.random_suffix}"

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
    Name        = "${local.name_prefix}-lambda-execution-role"
    Description = "IAM role for custom resource Lambda functions"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom IAM policy for S3 access
resource "aws_iam_policy" "lambda_s3_policy" {
  name        = "${local.name_prefix}-lambda-s3-policy-${local.random_suffix}"
  description = "IAM policy for Lambda to access S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.demo_bucket.arn,
          "${aws_s3_bucket.demo_bucket.arn}/*"
        ]
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-lambda-s3-policy"
    Description = "S3 access policy for custom resource Lambda function"
  })
}

# Attach S3 policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_s3_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

# CloudWatch Log Group for basic Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-handler-${local.random_suffix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-lambda-logs"
    Description = "CloudWatch logs for custom resource Lambda function"
  })
}

# Create Lambda deployment package for basic function
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda-function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      log_level = var.environment == "production" ? "INFO" : "DEBUG"
    })
    filename = "lambda_function.py"
  }
}

# Basic Lambda function for custom resources
resource "aws_lambda_function" "custom_resource_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  function_name = "${local.name_prefix}-handler-${local.random_suffix}"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  description = "Custom resource handler for CloudFormation demonstration"

  environment {
    variables = {
      ENVIRONMENT = var.environment
      LOG_LEVEL   = var.environment == "production" ? "INFO" : "DEBUG"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_s3_policy_attachment,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-custom-resource-handler"
    Description = "Lambda function for handling custom CloudFormation resources"
  })
}

# CloudWatch Log Group for advanced Lambda function
resource "aws_cloudwatch_log_group" "advanced_lambda_logs" {
  count             = var.enable_advanced_error_handling ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-advanced-handler-${local.random_suffix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-advanced-lambda-logs"
    Description = "CloudWatch logs for advanced custom resource Lambda function"
  })
}

# Create Lambda deployment package for advanced function
data "archive_file" "advanced_lambda_zip" {
  count       = var.enable_advanced_error_handling ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/advanced-lambda-function.zip"
  
  source {
    content = templatefile("${path.module}/advanced_lambda_function.py.tpl", {
      log_level = var.environment == "production" ? "INFO" : "DEBUG"
    })
    filename = "advanced_lambda_function.py"
  }
}

# Advanced Lambda function with enhanced error handling
resource "aws_lambda_function" "advanced_custom_resource_handler" {
  count            = var.enable_advanced_error_handling ? 1 : 0
  filename         = data.archive_file.advanced_lambda_zip[0].output_path
  source_code_hash = data.archive_file.advanced_lambda_zip[0].output_base64sha256
  
  function_name = "${local.name_prefix}-advanced-handler-${local.random_suffix}"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "advanced_lambda_function.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  description = "Advanced custom resource handler with comprehensive error handling"

  environment {
    variables = {
      ENVIRONMENT = var.environment
      LOG_LEVEL   = var.environment == "production" ? "INFO" : "DEBUG"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_s3_policy_attachment,
    aws_cloudwatch_log_group.advanced_lambda_logs[0]
  ]

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-advanced-custom-resource-handler"
    Description = "Advanced Lambda function with enhanced error handling for custom resources"
  })
}

# Standard S3 bucket for comparison (as shown in recipe)
resource "aws_s3_bucket" "standard_bucket" {
  bucket = "${local.name_prefix}-standard-${local.random_suffix}"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-standard-bucket"
    Description = "Standard S3 bucket for comparison with custom resource"
  })
}

# Standard bucket public access block
resource "aws_s3_bucket_public_access_block" "standard_bucket_pab" {
  bucket = aws_s3_bucket.standard_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFormation template for custom resource demonstration
resource "aws_cloudformation_stack" "custom_resource_demo" {
  name = "${local.name_prefix}-stack-${local.random_suffix}"

  template_body = templatefile("${path.module}/custom-resource-template.yaml.tpl", {
    lambda_function_arn = aws_lambda_function.custom_resource_handler.arn
    s3_bucket_name      = aws_s3_bucket.demo_bucket.id
    data_file_name      = var.data_file_name
    custom_data_content = var.custom_data_content
    project_name        = var.project_name
    environment         = var.environment
    random_suffix       = local.random_suffix
  })

  parameters = {
    LambdaFunctionArn  = aws_lambda_function.custom_resource_handler.arn
    S3BucketName       = aws_s3_bucket.demo_bucket.id
    DataFileName       = var.data_file_name
    CustomDataContent  = var.custom_data_content
  }

  capabilities = ["CAPABILITY_IAM"]

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-custom-resource-stack"
    Description = "CloudFormation stack demonstrating custom resources"
  })
}

# Production-ready CloudFormation stack (optional)
resource "aws_cloudformation_stack" "production_custom_resource" {
  count = var.enable_production_template ? 1 : 0
  name  = "${local.name_prefix}-production-stack-${local.random_suffix}"

  template_body = templatefile("${path.module}/production-template.yaml.tpl", {
    project_name  = var.project_name
    environment   = var.environment
    random_suffix = local.random_suffix
    aws_region    = var.aws_region
  })

  parameters = {
    Environment     = var.environment
    ResourceVersion = "1.0"
  }

  capabilities = ["CAPABILITY_IAM"]

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-production-stack"
    Description = "Production-ready CloudFormation stack with custom resources"
  })
}