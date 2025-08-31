# Email List Management System with SES and DynamoDB
# This Terraform configuration deploys a complete serverless email list management system
# including DynamoDB for subscriber storage, SES for email delivery, and Lambda functions
# for subscription management and newsletter sending.

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique resource names with random suffix
  table_name         = "email-subscribers-${random_id.suffix.hex}"
  lambda_role_name   = "EmailListLambdaRole-${random_id.suffix.hex}"
  function_name_base = "email-list-${random_id.suffix.hex}"
  
  # Common tags for all resources
  common_tags = {
    Project     = "EmailListManagement"
    Environment = var.environment
    Purpose     = "ServerlessEmailMarketing"
    ManagedBy   = "Terraform"
  }
}

# Data source for current AWS region and account ID
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

#------------------------------------------------------------------------------
# DynamoDB Table for Subscriber Management
#------------------------------------------------------------------------------

resource "aws_dynamodb_table" "email_subscribers" {
  name           = local.table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "email"
  
  # Define primary key attribute
  attribute {
    name = "email"
    type = "S"
  }
  
  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }
  
  # Server-side encryption with AWS managed keys
  server_side_encryption {
    enabled = true
  }
  
  # TTL configuration for automatic cleanup of inactive subscribers
  ttl {
    attribute_name = "ttl"
    enabled        = false # Set to true if you want automatic cleanup
  }
  
  tags = merge(local.common_tags, {
    Name        = local.table_name
    Description = "Stores email subscribers and their metadata"
  })
}

#------------------------------------------------------------------------------
# SES Email Identity Verification
#------------------------------------------------------------------------------

resource "aws_ses_email_identity" "sender" {
  email = var.sender_email
  
  tags = merge(local.common_tags, {
    Name        = "sender-identity"
    Description = "Verified email identity for sending newsletters"
  })
}

#------------------------------------------------------------------------------
# IAM Role and Policies for Lambda Functions
#------------------------------------------------------------------------------

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = local.lambda_role_name
  
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
    Name        = local.lambda_role_name
    Description = "Execution role for email list management Lambda functions"
  })
}

# Custom policy for DynamoDB and SES access
resource "aws_iam_policy" "lambda_email_policy" {
  name        = "email-list-lambda-policy-${random_id.suffix.hex}"
  description = "Policy for Lambda functions to access DynamoDB and SES"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # DynamoDB permissions for subscriber management
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.email_subscribers.arn
      },
      # SES permissions for email sending
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail",
          "ses:GetSendQuota",
          "ses:GetSendStatistics"
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
  
  tags = local.common_tags
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_custom_policy" {
  policy_arn = aws_iam_policy.lambda_email_policy.arn
  role       = aws_iam_role.lambda_execution_role.name
}

# Attach AWS managed basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

#------------------------------------------------------------------------------
# CloudWatch Log Groups for Lambda Functions
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "subscribe_logs" {
  name              = "/aws/lambda/${local.function_name_base}-subscribe"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "${local.function_name_base}-subscribe-logs"
    Description = "Log group for subscribe Lambda function"
  })
}

resource "aws_cloudwatch_log_group" "newsletter_logs" {
  name              = "/aws/lambda/${local.function_name_base}-newsletter"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "${local.function_name_base}-newsletter-logs"
    Description = "Log group for newsletter Lambda function"
  })
}

resource "aws_cloudwatch_log_group" "list_logs" {
  name              = "/aws/lambda/${local.function_name_base}-list"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "${local.function_name_base}-list-logs"
    Description = "Log group for list subscribers Lambda function"
  })
}

resource "aws_cloudwatch_log_group" "unsubscribe_logs" {
  name              = "/aws/lambda/${local.function_name_base}-unsubscribe"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "${local.function_name_base}-unsubscribe-logs"
    Description = "Log group for unsubscribe Lambda function"
  })
}

#------------------------------------------------------------------------------
# Lambda Function Source Code Archives
#------------------------------------------------------------------------------

# Subscribe function source code
data "archive_file" "subscribe_function_zip" {
  type        = "zip"
  output_path = "${path.module}/subscribe_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/subscribe_function.py", {
      table_name = local.table_name
    })
    filename = "subscribe_function.py"
  }
}

# Newsletter function source code
data "archive_file" "newsletter_function_zip" {
  type        = "zip"
  output_path = "${path.module}/newsletter_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/newsletter_function.py", {
      table_name   = local.table_name
      sender_email = var.sender_email
    })
    filename = "newsletter_function.py"
  }
}

# List subscribers function source code
data "archive_file" "list_function_zip" {
  type        = "zip"
  output_path = "${path.module}/list_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/list_function.py", {
      table_name = local.table_name
    })
    filename = "list_function.py"
  }
}

# Unsubscribe function source code
data "archive_file" "unsubscribe_function_zip" {
  type        = "zip"
  output_path = "${path.module}/unsubscribe_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/unsubscribe_function.py", {
      table_name = local.table_name
    })
    filename = "unsubscribe_function.py"
  }
}

#------------------------------------------------------------------------------
# Lambda Functions
#------------------------------------------------------------------------------

# Lambda function for subscriber registration
resource "aws_lambda_function" "subscribe_function" {
  filename         = data.archive_file.subscribe_function_zip.output_path
  function_name    = "${local.function_name_base}-subscribe"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "subscribe_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 30
  memory_size     = 256
  
  source_code_hash = data.archive_file.subscribe_function_zip.output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.email_subscribers.name
    }
  }
  
  # Advanced logging configuration
  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.subscribe_logs.name
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_custom_policy,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.subscribe_logs
  ]
  
  tags = merge(local.common_tags, {
    Name        = "${local.function_name_base}-subscribe"
    Description = "Handles new subscriber registrations"
  })
}

# Lambda function for sending newsletters
resource "aws_lambda_function" "newsletter_function" {
  filename         = data.archive_file.newsletter_function_zip.output_path
  function_name    = "${local.function_name_base}-newsletter"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "newsletter_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 300  # 5 minutes for bulk email sending
  memory_size     = 512  # Higher memory for processing multiple subscribers
  
  source_code_hash = data.archive_file.newsletter_function_zip.output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME   = aws_dynamodb_table.email_subscribers.name
      SENDER_EMAIL = var.sender_email
    }
  }
  
  # Advanced logging configuration
  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.newsletter_logs.name
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_custom_policy,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.newsletter_logs,
    aws_ses_email_identity.sender
  ]
  
  tags = merge(local.common_tags, {
    Name        = "${local.function_name_base}-newsletter"
    Description = "Sends newsletters to all active subscribers"
  })
}

# Lambda function for listing subscribers
resource "aws_lambda_function" "list_function" {
  filename         = data.archive_file.list_function_zip.output_path
  function_name    = "${local.function_name_base}-list"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "list_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 30
  memory_size     = 256
  
  source_code_hash = data.archive_file.list_function_zip.output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.email_subscribers.name
    }
  }
  
  # Advanced logging configuration  
  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.list_logs.name
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_custom_policy,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.list_logs
  ]
  
  tags = merge(local.common_tags, {
    Name        = "${local.function_name_base}-list"
    Description = "Lists all subscribers for administrative purposes"
  })
}

# Lambda function for unsubscribing users
resource "aws_lambda_function" "unsubscribe_function" {
  filename         = data.archive_file.unsubscribe_function_zip.output_path
  function_name    = "${local.function_name_base}-unsubscribe"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "unsubscribe_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 30
  memory_size     = 256
  
  source_code_hash = data.archive_file.unsubscribe_function_zip.output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.email_subscribers.name
    }
  }
  
  # Advanced logging configuration
  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.unsubscribe_logs.name
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_custom_policy,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.unsubscribe_logs
  ]
  
  tags = merge(local.common_tags, {
    Name        = "${local.function_name_base}-unsubscribe"
    Description = "Handles subscriber unsubscription requests"
  })
}

#------------------------------------------------------------------------------
# Lambda Function URLs (Optional - for direct HTTP access)
#------------------------------------------------------------------------------

# Function URL for subscribe function (if enabled)
resource "aws_lambda_function_url" "subscribe_url" {
  count              = var.enable_function_urls ? 1 : 0
  function_name      = aws_lambda_function.subscribe_function.function_name
  authorization_type = "NONE"  # Change to "AWS_IAM" for secured access
  
  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["POST"]
    allow_headers     = ["content-type", "x-amz-date", "authorization"]
    max_age          = 86400
  }
}

# Function URL for newsletter function (if enabled)
resource "aws_lambda_function_url" "newsletter_url" {
  count              = var.enable_function_urls ? 1 : 0
  function_name      = aws_lambda_function.newsletter_function.function_name
  authorization_type = "AWS_IAM"  # Secured access for newsletter sending
  
  cors {
    allow_credentials = true
    allow_origins     = var.allowed_origins
    allow_methods     = ["POST"]
    allow_headers     = ["content-type", "x-amz-date", "authorization"]
    max_age          = 86400
  }
}

# Function URL for list function (if enabled)
resource "aws_lambda_function_url" "list_url" {
  count              = var.enable_function_urls ? 1 : 0
  function_name      = aws_lambda_function.list_function.function_name
  authorization_type = "AWS_IAM"  # Secured access for administrative functions
  
  cors {
    allow_credentials = true
    allow_origins     = var.allowed_origins
    allow_methods     = ["GET"]
    allow_headers     = ["content-type", "x-amz-date", "authorization"]
    max_age          = 86400
  }
}

# Function URL for unsubscribe function (if enabled)
resource "aws_lambda_function_url" "unsubscribe_url" {
  count              = var.enable_function_urls ? 1 : 0
  function_name      = aws_lambda_function.unsubscribe_function.function_name
  authorization_type = "NONE"  # Public access for easy unsubscribe
  
  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["POST", "GET"]
    allow_headers     = ["content-type"]
    max_age          = 86400
  }
}