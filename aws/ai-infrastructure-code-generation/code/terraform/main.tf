# AI-Powered Infrastructure Code Generation with Amazon Q Developer and AWS Infrastructure Composer
# This Terraform configuration creates the complete infrastructure for automated template processing

# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming prefix
  name_prefix = "${var.application_name}-${var.environment}"
  
  # Resource-specific names with random suffix
  bucket_name         = "${local.name_prefix}-templates-${random_id.suffix.hex}"
  lambda_function_name = "${local.name_prefix}-processor-${random_id.suffix.hex}"
  iam_role_name       = "${local.name_prefix}-role-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = "AI-Powered Infrastructure Generation"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "amazon-q-developer-infrastructure-composer"
    },
    var.additional_tags
  )
}

# S3 Bucket for Template Storage
resource "aws_s3_bucket" "template_bucket" {
  bucket = local.bucket_name
  
  tags = merge(local.common_tags, {
    Purpose = "Template Storage"
    Name    = local.bucket_name
  })
}

# S3 Bucket Versioning Configuration
resource "aws_s3_bucket_versioning" "template_bucket_versioning" {
  bucket = aws_s3_bucket.template_bucket.id
  
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "template_bucket_pab" {
  bucket = aws_s3_bucket.template_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "template_bucket_encryption" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.template_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.s3_encryption_algorithm
      kms_master_key_id = var.s3_encryption_algorithm == "aws:kms" ? var.kms_key_id : null
    }
    bucket_key_enabled = var.s3_encryption_algorithm == "aws:kms"
  }
}

# S3 Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "template_bucket_lifecycle" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.template_bucket.id

  rule {
    id     = "template_lifecycle"
    status = "Enabled"

    # Transition to Infrequent Access after specified days
    transition {
      days          = var.s3_lifecycle_days
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete old versions after 365 days
    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# IAM Role for Lambda Function
resource "aws_iam_role" "lambda_execution_role" {
  name = local.iam_role_name

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
    Purpose = "Lambda Execution Role"
    Name    = local.iam_role_name
  })
}

# IAM Policy for Lambda Function
resource "aws_iam_role_policy" "lambda_execution_policy" {
  name = "${local.iam_role_name}-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 permissions for template processing
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.template_bucket.arn,
          "${aws_s3_bucket.template_bucket.arn}/*"
        ]
      },
      # CloudFormation permissions for template validation and deployment
      {
        Effect = "Allow"
        Action = [
          "cloudformation:ValidateTemplate",
          "cloudformation:CreateStack",
          "cloudformation:DescribeStacks",
          "cloudformation:DescribeStackEvents",
          "cloudformation:UpdateStack",
          "cloudformation:DeleteStack",
          "cloudformation:ListStacks"
        ]
        Resource = "*"
      },
      # IAM permissions for CloudFormation operations
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole",
          "iam:CreateRole",
          "iam:AttachRolePolicy",
          "iam:GetRole",
          "iam:ListRoles"
        ]
        Resource = "*"
      },
      # CloudWatch Logs permissions
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# VPC configuration for Lambda (conditional)
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  count      = var.enable_vpc_config ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# CloudWatch Log Group for Lambda Function
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Purpose = "Lambda Function Logs"
    Name    = "/aws/lambda/${local.lambda_function_name}"
  })
}

# Create Lambda function code as a zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      auto_deploy_prefix = var.auto_deploy_prefix
      enable_auto_deployment = var.enable_auto_deployment
    })
    filename = "index.py"
  }
}

# Lambda Function for Template Processing
resource "aws_lambda_function" "template_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Environment variables for Lambda function
  environment {
    variables = {
      BUCKET_NAME           = aws_s3_bucket.template_bucket.bucket
      AUTO_DEPLOY_PREFIX    = var.auto_deploy_prefix
      ENABLE_AUTO_DEPLOYMENT = var.enable_auto_deployment
      ENVIRONMENT           = var.environment
      APPLICATION_NAME      = var.application_name
    }
  }

  # VPC configuration (conditional)
  dynamic "vpc_config" {
    for_each = var.enable_vpc_config ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_log_group,
  ]

  tags = merge(local.common_tags, {
    Purpose = "Template Processing"
    Name    = local.lambda_function_name
  })
}

# Lambda Permission for S3 to invoke the function
resource "aws_lambda_permission" "s3_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.template_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.template_bucket.arn
}

# S3 Bucket Notification Configuration
resource "aws_s3_bucket_notification" "template_bucket_notification" {
  bucket = aws_s3_bucket.template_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.template_processor.arn
    events             = ["s3:ObjectCreated:*"]
    filter_prefix      = "templates/"
    filter_suffix      = ".json"
  }

  depends_on = [aws_lambda_permission.s3_invoke_lambda]
}

# SNS Topic for Notifications (optional)
resource "aws_sns_topic" "template_notifications" {
  count = var.enable_sns_notifications ? 1 : 0
  name  = "${local.name_prefix}-notifications"

  tags = merge(local.common_tags, {
    Purpose = "Template Processing Notifications"
    Name    = "${local.name_prefix}-notifications"
  })
}

# SNS Topic Subscription (optional)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.enable_sns_notifications ? 1 : 0
  topic_arn = aws_sns_topic.template_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# IAM policy for SNS publishing (if notifications enabled)
resource "aws_iam_role_policy" "lambda_sns_policy" {
  count = var.enable_sns_notifications ? 1 : 0
  name  = "${local.iam_role_name}-sns-policy"
  role  = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.template_notifications[0].arn
      }
    ]
  })
}

# Create sample infrastructure requirements file in S3
resource "aws_s3_object" "infrastructure_requirements" {
  bucket = aws_s3_bucket.template_bucket.bucket
  key    = "documentation/infrastructure-requirements.md"
  
  content = templatefile("${path.module}/infrastructure-requirements.md", {
    application_name = var.application_name
    environment     = var.environment
  })
  
  content_type = "text/markdown"
  
  tags = merge(local.common_tags, {
    Purpose = "Documentation"
    Type    = "Requirements"
  })
}

# Create Q Developer prompt templates in S3
resource "aws_s3_object" "q_prompts" {
  bucket = aws_s3_bucket.template_bucket.bucket
  key    = "documentation/q-prompts.md"
  
  content = file("${path.module}/q-prompts.md")
  content_type = "text/markdown"
  
  tags = merge(local.common_tags, {
    Purpose = "Documentation"
    Type    = "Prompts"
  })
}