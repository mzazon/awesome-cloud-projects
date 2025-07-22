# Main Terraform Configuration for AWS Application Discovery Service
# This file creates the core infrastructure for application discovery and assessment

# Data Sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # Generate unique bucket name if not provided
  bucket_name = var.discovery_bucket_name != "" ? var.discovery_bucket_name : "${var.resource_prefix}-discovery-data-${local.account_id}-${random_string.suffix.result}"
  
  # Common tags to apply to all resources
  common_tags = merge(var.additional_tags, {
    Project     = "ApplicationDiscoveryService"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "application-discovery-assessment-aws-application-discovery-service"
  })
}

# KMS Key for S3 Bucket Encryption
resource "aws_kms_key" "discovery_key" {
  count = var.enable_encryption ? 1 : 0
  
  description             = "KMS key for Application Discovery Service S3 bucket encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Application Discovery Service"
        Effect = "Allow"
        Principal = {
          Service = "discovery.amazonaws.com"
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
    Name = "${var.resource_prefix}-discovery-key"
  })
}

# KMS Key Alias
resource "aws_kms_alias" "discovery_key_alias" {
  count = var.enable_encryption ? 1 : 0
  
  name          = "alias/${var.resource_prefix}-discovery-key"
  target_key_id = aws_kms_key.discovery_key[0].key_id
}

# S3 Bucket for Discovery Data Storage
resource "aws_s3_bucket" "discovery_data" {
  bucket        = local.bucket_name
  force_destroy = true
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-discovery-data"
  })
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "discovery_data_versioning" {
  bucket = aws_s3_bucket.discovery_data.id
  
  versioning_configuration {
    status = var.enable_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 Bucket Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "discovery_data_encryption" {
  count = var.enable_encryption ? 1 : 0
  
  bucket = aws_s3_bucket.discovery_data.id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.discovery_key[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "discovery_data_pab" {
  bucket = aws_s3_bucket.discovery_data.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "discovery_data_lifecycle" {
  bucket = aws_s3_bucket.discovery_data.id
  
  rule {
    id     = "discovery_data_lifecycle"
    status = "Enabled"
    
    expiration {
      days = var.bucket_lifecycle_days
    }
    
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# IAM Role for Application Discovery Service
resource "aws_iam_role" "discovery_service_role" {
  name = "${var.resource_prefix}-ApplicationDiscoveryServiceRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "discovery.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-discovery-service-role"
  })
}

# IAM Policy Attachment for Discovery Service
resource "aws_iam_role_policy_attachment" "discovery_service_policy" {
  role       = aws_iam_role.discovery_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ApplicationDiscoveryServiceContinuousExportServiceRolePolicy"
}

# Custom IAM Policy for S3 Access
resource "aws_iam_role_policy" "discovery_s3_policy" {
  name = "${var.resource_prefix}-discovery-s3-policy"
  role = aws_iam_role.discovery_service_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.discovery_data.arn,
          "${aws_s3_bucket.discovery_data.arn}/*"
        ]
      }
    ]
  })
}

# SNS Topic for Notifications (if enabled)
resource "aws_sns_topic" "discovery_notifications" {
  count = var.enable_sns_notifications ? 1 : 0
  
  name = "${var.resource_prefix}-discovery-notifications"
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-discovery-notifications"
  })
}

# SNS Topic Subscription (if enabled)
resource "aws_sns_topic_subscription" "discovery_email_notifications" {
  count = var.enable_sns_notifications && var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.discovery_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Lambda Execution Role
resource "aws_iam_role" "lambda_execution_role" {
  count = var.enable_automated_reports ? 1 : 0
  
  name = "${var.resource_prefix}-discovery-lambda-role"
  
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
    Name = "${var.resource_prefix}-lambda-execution-role"
  })
}

# Lambda Execution Policy
resource "aws_iam_role_policy" "lambda_execution_policy" {
  count = var.enable_automated_reports ? 1 : 0
  
  name = "${var.resource_prefix}-lambda-execution-policy"
  role = aws_iam_role.lambda_execution_role[0].id
  
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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "discovery:StartExportTask",
          "discovery:DescribeExportTasks"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          aws_s3_bucket.discovery_data.arn,
          "${aws_s3_bucket.discovery_data.arn}/*"
        ]
      }
    ]
  })
}

# Lambda Function for Automated Discovery Reports
resource "aws_lambda_function" "discovery_automation" {
  count = var.enable_automated_reports ? 1 : 0
  
  filename         = "discovery_automation.zip"
  function_name    = "${var.resource_prefix}-discovery-automation"
  role            = aws_iam_role.lambda_execution_role[0].arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory
  
  environment {
    variables = {
      DISCOVERY_BUCKET = aws_s3_bucket.discovery_data.bucket
      AWS_REGION       = local.region
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-discovery-automation"
  })
}

# Lambda Function Code
data "archive_file" "lambda_zip" {
  count = var.enable_automated_reports ? 1 : 0
  
  type        = "zip"
  output_path = "discovery_automation.zip"
  
  source {
    content = <<EOF
import boto3
import json
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    discovery = boto3.client('discovery')
    
    try:
        # Start weekly export
        response = discovery.start_export_task(
            exportDataFormat='CSV',
            s3Bucket=os.environ['DISCOVERY_BUCKET']
        )
        
        logger.info(f"Discovery export started with ID: {response['exportId']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Discovery export started successfully',
                'exportId': response['exportId']
            })
        }
        
    except Exception as e:
        logger.error(f"Error starting discovery export: {str(e)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
EOF
    filename = "index.py"
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count = var.enable_automated_reports ? 1 : 0
  
  name              = "/aws/lambda/${var.resource_prefix}-discovery-automation"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-lambda-logs"
  })
}

# CloudWatch Events Rule for Automated Reports
resource "aws_cloudwatch_event_rule" "discovery_schedule" {
  count = var.enable_automated_reports ? 1 : 0
  
  name                = "${var.resource_prefix}-discovery-schedule"
  description         = "Schedule for automated discovery reports"
  schedule_expression = var.report_schedule
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-discovery-schedule"
  })
}

# CloudWatch Events Target
resource "aws_cloudwatch_event_target" "lambda_target" {
  count = var.enable_automated_reports ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.discovery_schedule[0].name
  target_id = "DiscoveryLambdaTarget"
  arn       = aws_lambda_function.discovery_automation[0].arn
}

# Lambda Permission for CloudWatch Events
resource "aws_lambda_permission" "allow_cloudwatch" {
  count = var.enable_automated_reports ? 1 : 0
  
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discovery_automation[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.discovery_schedule[0].arn
}

# Athena Database for Discovery Analysis
resource "aws_athena_database" "discovery_database" {
  count = var.enable_athena_analysis ? 1 : 0
  
  name   = var.athena_database_name
  bucket = aws_s3_bucket.discovery_data.bucket
  
  encryption_configuration {
    encryption_option = var.enable_encryption ? "SSE_KMS" : "SSE_S3"
    kms_key       = var.enable_encryption ? aws_kms_key.discovery_key[0].arn : null
  }
}

# Athena Workgroup for Discovery Queries
resource "aws_athena_workgroup" "discovery_workgroup" {
  count = var.enable_athena_analysis ? 1 : 0
  
  name = "${var.resource_prefix}-discovery-workgroup"
  
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    
    result_configuration {
      output_location = "s3://${aws_s3_bucket.discovery_data.bucket}/athena-results/"
      
      encryption_configuration {
        encryption_option = var.enable_encryption ? "SSE_KMS" : "SSE_S3"
        kms_key       = var.enable_encryption ? aws_kms_key.discovery_key[0].arn : null
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-discovery-workgroup"
  })
}

# Migration Hub Home Region Configuration
# Note: This resource requires manual setup via AWS CLI as there's no native Terraform resource
resource "null_resource" "migration_hub_setup" {
  provisioner "local-exec" {
    command = <<-EOT
      aws migrationhub create-progress-update-stream \
        --progress-update-stream-name "DiscoveryAssessment" \
        --region ${var.migration_hub_home_region} || true
    EOT
  }
  
  triggers = {
    home_region = var.migration_hub_home_region
  }
}

# Discovery Applications (simulated via local-exec as no native Terraform resource exists)
resource "null_resource" "discovery_applications" {
  count = length(var.application_groups)
  
  provisioner "local-exec" {
    command = <<-EOT
      aws discovery create-application \
        --name "${var.application_groups[count.index].name}-${random_string.suffix.result}" \
        --description "${var.application_groups[count.index].description}" \
        --region ${var.aws_region} || true
    EOT
  }
  
  depends_on = [null_resource.migration_hub_setup]
  
  triggers = {
    application_name = var.application_groups[count.index].name
    application_desc = var.application_groups[count.index].description
  }
}