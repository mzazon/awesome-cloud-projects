# Centralized SaaS Security Monitoring with AWS AppFabric and EventBridge
# This Terraform configuration creates a comprehensive security monitoring solution
# for SaaS applications using AWS AppFabric, EventBridge, Lambda, and SNS.

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Component   = "security-monitoring"
  })
}

# ==============================================================================
# S3 Bucket for Security Logs
# ==============================================================================

# S3 bucket to store AppFabric security logs in OCSF format
resource "aws_s3_bucket" "security_logs" {
  bucket        = "${local.name_prefix}-security-logs-${data.aws_caller_identity.current.account_id}-${local.name_suffix}"
  force_destroy = var.s3_bucket_force_destroy
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-security-logs-${local.name_suffix}"
    Purpose     = "appfabric-security-logs"
    DataType    = "security-events"
  })
}

# S3 bucket versioning for data protection
resource "aws_s3_bucket_versioning" "security_logs_versioning" {
  bucket = aws_s3_bucket.security_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption for data at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "security_logs_encryption" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.security_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for security
resource "aws_s3_bucket_public_access_block" "security_logs_pab" {
  bucket = aws_s3_bucket.security_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket notification configuration for EventBridge
resource "aws_s3_bucket_notification" "security_logs_notification" {
  bucket      = aws_s3_bucket.security_logs.id
  eventbridge = true
  
  depends_on = [aws_cloudwatch_event_bus.security_monitoring]
}

# ==============================================================================
# KMS Key for SNS Encryption (Optional)
# ==============================================================================

# KMS key for SNS topic encryption
resource "aws_kms_key" "sns_encryption" {
  count                   = var.enable_sns_encryption ? 1 : 0
  description             = "KMS key for SNS topic encryption in security monitoring"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-sns-key-${local.name_suffix}"
    Service = "sns"
  })
}

# KMS key alias for easier identification
resource "aws_kms_alias" "sns_encryption" {
  count         = var.enable_sns_encryption ? 1 : 0
  name          = "alias/${local.name_prefix}-sns-encryption-${local.name_suffix}"
  target_key_id = aws_kms_key.sns_encryption[0].key_id
}

# KMS key policy to allow SNS service access
resource "aws_kms_key_policy" "sns_encryption" {
  count  = var.enable_sns_encryption ? 1 : 0
  key_id = aws_kms_key.sns_encryption[0].id
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
        Sid    = "Allow SNS Service"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      }
    ]
  })
}

# ==============================================================================
# SNS Topic for Security Alerts
# ==============================================================================

# SNS topic for sending security alerts
resource "aws_sns_topic" "security_alerts" {
  name              = "${local.name_prefix}-security-alerts-${local.name_suffix}"
  kms_master_key_id = var.enable_sns_encryption ? aws_kms_key.sns_encryption[0].id : null
  
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-security-alerts-${local.name_suffix}"
    Purpose = "security-notifications"
  })
}

# SNS topic policy to allow Lambda to publish messages
resource "aws_sns_topic_policy" "security_alerts_policy" {
  arn = aws_sns_topic.security_alerts.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_execution.arn
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.security_alerts.arn
      }
    ]
  })
}

# Email subscription to SNS topic (only if email is provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ==============================================================================
# EventBridge Custom Bus and Rules
# ==============================================================================

# Custom EventBridge bus for security events
resource "aws_cloudwatch_event_bus" "security_monitoring" {
  name = "${local.name_prefix}-security-bus-${local.name_suffix}"
  
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-security-bus-${local.name_suffix}"
    Purpose = "security-event-routing"
  })
}

# EventBridge rule for S3 security log events
resource "aws_cloudwatch_event_rule" "s3_security_logs" {
  name           = "${local.name_prefix}-s3-security-logs-${local.name_suffix}"
  description    = "Route S3 security log events to Lambda processor"
  event_bus_name = aws_cloudwatch_event_bus.security_monitoring.name
  state          = var.eventbridge_rule_state
  
  event_pattern = jsonencode({
    source        = ["aws.s3"]
    detail-type   = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.security_logs.bucket]
      }
      object = {
        key = [{
          prefix = var.security_log_prefix
        }]
      }
    }
  })
  
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-s3-security-logs-${local.name_suffix}"
    Purpose = "security-log-processing"
  })
}

# EventBridge target to invoke Lambda function
resource "aws_cloudwatch_event_target" "lambda_processor" {
  rule           = aws_cloudwatch_event_rule.s3_security_logs.name
  event_bus_name = aws_cloudwatch_event_bus.security_monitoring.name
  target_id      = "SecurityProcessorLambdaTarget"
  arn            = aws_lambda_function.security_processor.arn
  
  depends_on = [aws_lambda_permission.eventbridge_invoke]
}

# ==============================================================================
# Lambda Function for Security Processing
# ==============================================================================

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-security-processor-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-lambda-logs-${local.name_suffix}"
    Service = "lambda"
  })
}

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
  name = "${local.name_prefix}-lambda-execution-role-${local.name_suffix}"
  
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
    Name = "${local.name_prefix}-lambda-execution-role-${local.name_suffix}"
  })
}

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution.name
}

# IAM policy for Lambda to access required services
resource "aws_iam_role_policy" "lambda_security_processor" {
  name = "${local.name_prefix}-lambda-security-policy-${local.name_suffix}"
  role = aws_iam_role.lambda_execution.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.security_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.security_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.security_logs.arn
      },
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

# Create Lambda function source code archive
data "archive_file" "lambda_source" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      sns_topic_arn = aws_sns_topic.security_alerts.arn
    })
    filename = "index.py"
  }
}

# Lambda function for security event processing
resource "aws_lambda_function" "security_processor" {
  filename      = data.archive_file.lambda_source.output_path
  function_name = "${local.name_prefix}-security-processor-${local.name_suffix}"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_source.output_base64sha256
  
  environment {
    variables = {
      SNS_TOPIC_ARN         = aws_sns_topic.security_alerts.arn
      S3_BUCKET_NAME        = aws_s3_bucket.security_logs.bucket
      LOG_LEVEL             = "INFO"
      SECURITY_LOG_PREFIX   = var.security_log_prefix
    }
  }
  
  depends_on = [aws_cloudwatch_log_group.lambda_logs]
  
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-security-processor-${local.name_suffix}"
    Purpose = "security-event-processing"
  })
}

# Lambda permission for EventBridge to invoke function
resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowExecutionFromEventBridge-${local.name_suffix}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_security_logs.arn
}

# ==============================================================================
# AWS AppFabric Resources
# ==============================================================================

# IAM role for AppFabric service
resource "aws_iam_role" "appfabric_service" {
  name = "${local.name_prefix}-appfabric-service-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "appfabric.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-appfabric-service-role-${local.name_suffix}"
  })
}

# IAM policy for AppFabric to write to S3 bucket
resource "aws_iam_role_policy" "appfabric_s3_access" {
  name = "${local.name_prefix}-appfabric-s3-policy-${local.name_suffix}"
  role = aws_iam_role.appfabric_service.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.security_logs.arn,
          "${aws_s3_bucket.security_logs.arn}/*"
        ]
      }
    ]
  })
}

# AppFabric App Bundle for SaaS application connectivity
resource "aws_appfabric_app_bundle" "security_monitoring" {
  customer_managed_key_arn = var.enable_s3_encryption && length(aws_kms_key.sns_encryption) > 0 ? aws_kms_key.sns_encryption[0].arn : null
  
  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-app-bundle-${local.name_suffix}"
    Purpose = "saas-security-monitoring"
  })
}

# Note: AppFabric ingestions and destinations require manual SaaS app authorization
# These resources are defined as examples but may need manual intervention

# Example AppFabric ingestion destination for S3
resource "aws_appfabric_ingestion_destination" "s3_destination" {
  # This resource is commented out as it requires an ingestion to be created first
  # and ingestions require manual SaaS application authorization
  
  # app_bundle_arn = aws_appfabric_app_bundle.security_monitoring.arn
  # ingestion_arn  = aws_appfabric_ingestion.example.arn
  
  count = 0 # Disabled until ingestions are manually configured
  
  # processing_configuration {
  #   audit_log {
  #     format = var.appfabric_processing_format
  #     schema = var.appfabric_processing_schema
  #   }
  # }
  
  # destination_configuration {
  #   audit_log {
  #     destination {
  #       s3_bucket {
  #         bucket_name = aws_s3_bucket.security_logs.bucket
  #         prefix      = var.security_log_prefix
  #       }
  #     }
  #   }
  # }
  
  # tags = merge(local.common_tags, {
  #   Name    = "${local.name_prefix}-s3-destination-${local.name_suffix}"
  #   Purpose = "security-log-storage"
  # })
}