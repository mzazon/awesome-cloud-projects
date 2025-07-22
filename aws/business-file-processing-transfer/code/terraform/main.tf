# Main Terraform configuration for AWS Transfer Family and Step Functions file processing
# This file creates a complete automated file processing pipeline with SFTP ingestion

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  
  # S3 bucket names (must be globally unique)
  landing_bucket   = "${local.name_prefix}-landing"
  processed_bucket = "${local.name_prefix}-processed"
  archive_bucket   = "${local.name_prefix}-archive"
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    CreatedBy   = "Terraform"
  }
}

# =============================================================================
# KMS KEY FOR ENCRYPTION
# =============================================================================

resource "aws_kms_key" "file_processing" {
  count = var.enable_encryption ? 1 : 0
  
  description             = "KMS key for file processing infrastructure encryption"
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
          "kms:GenerateDataKey",
          "kms:ReEncrypt*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kms-key"
  })
}

resource "aws_kms_alias" "file_processing" {
  count = var.enable_encryption ? 1 : 0
  
  name          = "alias/${local.name_prefix}-file-processing"
  target_key_id = aws_kms_key.file_processing[0].key_id
}

# =============================================================================
# S3 BUCKETS FOR FILE STORAGE
# =============================================================================

# Landing bucket for incoming files via SFTP
resource "aws_s3_bucket" "landing" {
  bucket        = local.landing_bucket
  force_destroy = var.s3_bucket_force_destroy

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-landing"
    Purpose     = "SFTP file ingestion"
    DataClass   = "Incoming"
  })
}

# Processed bucket for transformed files
resource "aws_s3_bucket" "processed" {
  bucket        = local.processed_bucket
  force_destroy = var.s3_bucket_force_destroy

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-processed"
    Purpose     = "Processed file storage"
    DataClass   = "Processed"
  })
}

# Archive bucket for long-term storage
resource "aws_s3_bucket" "archive" {
  bucket        = local.archive_bucket
  force_destroy = var.s3_bucket_force_destroy

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-archive"
    Purpose     = "Long-term file archive"
    DataClass   = "Archive"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "landing" {
  bucket = aws_s3_bucket.landing.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_versioning" "processed" {
  bucket = aws_s3_bucket.processed.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_versioning" "archive" {
  bucket = aws_s3_bucket.archive.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "landing" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.landing.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.file_processing[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.processed.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.file_processing[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.archive.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.file_processing[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "landing" {
  bucket = aws_s3_bucket.landing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "processed" {
  bucket = aws_s3_bucket.processed.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "archive" {
  bucket = aws_s3_bucket.archive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for archive bucket
resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id

  rule {
    id     = "archive_lifecycle"
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

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# Lambda execution role
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

# Lambda execution policy
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
          "s3:PutObject",
          "s3:CopyObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.landing.arn}/*",
          "${aws_s3_bucket.processed.arn}/*",
          "${aws_s3_bucket.archive.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.landing.arn,
          aws_s3_bucket.processed.arn,
          aws_s3_bucket.archive.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*",
          "kms:DescribeKey"
        ]
        Resource = var.enable_encryption ? [aws_kms_key.file_processing[0].arn] : []
      }
    ]
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# X-Ray tracing policy for Lambda
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Transfer Family service role
resource "aws_iam_role" "transfer_role" {
  name = "${local.name_prefix}-transfer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "transfer.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-transfer-role"
  })
}

# Transfer Family S3 access policy
resource "aws_iam_role_policy" "transfer_policy" {
  name = "${local.name_prefix}-transfer-policy"
  role = aws_iam_role.transfer_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ]
        Resource = "${aws_s3_bucket.landing.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.landing.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*",
          "kms:DescribeKey"
        ]
        Resource = var.enable_encryption ? [aws_kms_key.file_processing[0].arn] : []
      }
    ]
  })
}

# Step Functions execution role
resource "aws_iam_role" "stepfunctions_role" {
  name = "${local.name_prefix}-stepfunctions-role"

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
    Name = "${local.name_prefix}-stepfunctions-role"
  })
}

# Step Functions Lambda invocation policy
resource "aws_iam_role_policy" "stepfunctions_policy" {
  name = "${local.name_prefix}-stepfunctions-policy"
  role = aws_iam_role.stepfunctions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.validator.arn,
          aws_lambda_function.processor.arn,
          aws_lambda_function.router.arn
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

# EventBridge role for Step Functions
resource "aws_iam_role" "eventbridge_role" {
  name = "${local.name_prefix}-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eventbridge-role"
  })
}

# EventBridge Step Functions invocation policy
resource "aws_iam_role_policy" "eventbridge_policy" {
  name = "${local.name_prefix}-eventbridge-policy"
  role = aws_iam_role.eventbridge_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.file_processing.arn
      }
    ]
  })
}

# =============================================================================
# LAMBDA FUNCTIONS
# =============================================================================

# Lambda function ZIP packages
data "archive_file" "validator_zip" {
  type        = "zip"
  output_path = "${path.module}/validator_function.zip"
  
  source {
    content = <<EOF
import json
import boto3
import csv
from io import StringIO
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    
    try:
        # Extract S3 information from EventBridge or direct input
        if 'detail' in event:
            bucket = event['detail']['bucket']['name']
            key = event['detail']['object']['key']
        else:
            bucket = event['bucket']
            key = event['key']
        
        logger.info(f"Validating file: s3://{bucket}/{key}")
        
        # Download and validate file format
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Validate CSV format
        csv_reader = csv.reader(StringIO(content))
        rows = list(csv_reader)
        
        if len(rows) < 2:  # Header + at least one data row
            raise ValueError("File must contain header and data rows")
        
        logger.info(f"File validation successful: {len(rows) - 1} data rows found")
        
        return {
            'statusCode': 200,
            'isValid': True,
            'rowCount': len(rows) - 1,
            'bucket': bucket,
            'key': key
        }
    except Exception as e:
        logger.error(f"Validation failed: {str(e)}")
        return {
            'statusCode': 400,
            'isValid': False,
            'error': str(e),
            'bucket': bucket,
            'key': key
        }
EOF
    filename = "validator_function.py"
  }
}

data "archive_file" "processor_zip" {
  type        = "zip"
  output_path = "${path.module}/processor_function.zip"
  
  source {
    content = <<EOF
import json
import boto3
import csv
import io
from datetime import datetime
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    bucket = event['bucket']
    key = event['key']
    
    try:
        logger.info(f"Processing file: s3://{bucket}/{key}")
        
        # Download original file
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Process CSV data
        csv_reader = csv.DictReader(io.StringIO(content))
        processed_rows = []
        
        for row in csv_reader:
            # Add processing timestamp
            row['processed_timestamp'] = datetime.utcnow().isoformat()
            # Add business logic transformations here
            processed_rows.append(row)
        
        # Convert back to CSV
        output = io.StringIO()
        if processed_rows:
            writer = csv.DictWriter(output, fieldnames=processed_rows[0].keys())
            writer.writeheader()
            writer.writerows(processed_rows)
        
        # Upload processed file
        processed_bucket = bucket.replace('landing', 'processed')
        processed_key = f"processed/{key}"
        s3.put_object(
            Bucket=processed_bucket,
            Key=processed_key,
            Body=output.getvalue(),
            ContentType='text/csv'
        )
        
        logger.info(f"File processed successfully: {len(processed_rows)} records")
        
        return {
            'statusCode': 200,
            'processedKey': processed_key,
            'recordCount': len(processed_rows),
            'bucket': bucket,
            'originalKey': key
        }
        
    except Exception as e:
        logger.error(f"Processing failed: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'bucket': bucket,
            'key': key
        }
EOF
    filename = "processor_function.py"
  }
}

data "archive_file" "router_zip" {
  type        = "zip"
  output_path = "${path.module}/router_function.zip"
  
  source {
    content = <<EOF
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    bucket = event['bucket']
    key = event['processedKey']
    record_count = event['recordCount']
    
    try:
        logger.info(f"Routing file: {key} with {record_count} records")
        
        # Determine routing destination based on file content
        if 'financial' in key.lower():
            destination = 'financial-data/'
        elif 'inventory' in key.lower():
            destination = 'inventory-data/'
        else:
            destination = 'general-data/'
        
        # Copy to archive with organized structure
        processed_bucket = bucket.replace('landing', 'processed')
        archive_bucket = bucket.replace('landing', 'archive')
        archive_key = f"{destination}{key}"
        
        s3.copy_object(
            CopySource={'Bucket': processed_bucket, 'Key': key},
            Bucket=archive_bucket,
            Key=archive_key
        )
        
        logger.info(f"File routed to: s3://{archive_bucket}/{archive_key}")
        
        return {
            'statusCode': 200,
            'destination': destination,
            'archiveKey': archive_key,
            'recordCount': record_count
        }
        
    except Exception as e:
        logger.error(f"Routing failed: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }
EOF
    filename = "router_function.py"
  }
}

# File validator Lambda function
resource "aws_lambda_function" "validator" {
  filename         = data.archive_file.validator_zip.output_path
  function_name    = "${local.name_prefix}-validator"
  role            = aws_iam_role.lambda_role.arn
  handler         = "validator_function.lambda_handler"
  source_code_hash = data.archive_file.validator_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  environment {
    variables = {
      LANDING_BUCKET   = aws_s3_bucket.landing.bucket
      PROCESSED_BUCKET = aws_s3_bucket.processed.bucket
      ARCHIVE_BUCKET   = aws_s3_bucket.archive.bucket
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-validator"
  })
}

# Data processor Lambda function
resource "aws_lambda_function" "processor" {
  filename         = data.archive_file.processor_zip.output_path
  function_name    = "${local.name_prefix}-processor"
  role            = aws_iam_role.lambda_role.arn
  handler         = "processor_function.lambda_handler"
  source_code_hash = data.archive_file.processor_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  environment {
    variables = {
      LANDING_BUCKET   = aws_s3_bucket.landing.bucket
      PROCESSED_BUCKET = aws_s3_bucket.processed.bucket
      ARCHIVE_BUCKET   = aws_s3_bucket.archive.bucket
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-processor"
  })
}

# File router Lambda function
resource "aws_lambda_function" "router" {
  filename         = data.archive_file.router_zip.output_path
  function_name    = "${local.name_prefix}-router"
  role            = aws_iam_role.lambda_role.arn
  handler         = "router_function.lambda_handler"
  source_code_hash = data.archive_file.router_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  environment {
    variables = {
      LANDING_BUCKET   = aws_s3_bucket.landing.bucket
      PROCESSED_BUCKET = aws_s3_bucket.processed.bucket
      ARCHIVE_BUCKET   = aws_s3_bucket.archive.bucket
      SNS_TOPIC_ARN    = aws_sns_topic.alerts.arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-router"
  })
}

# =============================================================================
# STEP FUNCTIONS STATE MACHINE
# =============================================================================

# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "stepfunctions" {
  name              = "/aws/stepfunctions/${local.name_prefix}-workflow"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-stepfunctions-logs"
  })
}

# Step Functions state machine
resource "aws_sfn_state_machine" "file_processing" {
  name     = "${local.name_prefix}-workflow"
  role_arn = aws_iam_role.stepfunctions_role.arn

  definition = jsonencode({
    Comment = "Automated file processing workflow"
    StartAt = "ValidateFile"
    States = {
      ValidateFile = {
        Type     = "Task"
        Resource = aws_lambda_function.validator.arn
        Next     = "CheckValidation"
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException"]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "ValidationFailed"
          }
        ]
      }
      CheckValidation = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.isValid"
            BooleanEquals = true
            Next          = "ProcessFile"
          }
        ]
        Default = "ValidationFailed"
      }
      ProcessFile = {
        Type     = "Task"
        Resource = aws_lambda_function.processor.arn
        Next     = "RouteFile"
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException"]
            IntervalSeconds = 2
            MaxAttempts     = 3
          }
        ]
      }
      RouteFile = {
        Type     = "Task"
        Resource = aws_lambda_function.router.arn
        Next     = "ProcessingComplete"
      }
      ProcessingComplete = {
        Type = "Succeed"
      }
      ValidationFailed = {
        Type  = "Fail"
        Cause = "File validation failed"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.stepfunctions.arn}:*"
    include_execution_data = true
    level                  = var.step_functions_log_level
  }

  dynamic "tracing_configuration" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      enabled = true
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-workflow"
  })
}

# =============================================================================
# AWS TRANSFER FAMILY
# =============================================================================

# Transfer Family SFTP server
resource "aws_transfer_server" "sftp" {
  identity_provider_type = "SERVICE_MANAGED"
  protocols              = ["SFTP"]
  endpoint_type          = var.transfer_family_endpoint_type
  
  # Security policy for enhanced security
  security_policy_name = "TransferSecurityPolicy-TLS-1-2-2017-01"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sftp-server"
  })
}

# Transfer Family user
resource "aws_transfer_user" "business_partner" {
  server_id      = aws_transfer_server.sftp.id
  user_name      = var.sftp_username
  role           = aws_iam_role.transfer_role.arn
  home_directory = "/${aws_s3_bucket.landing.bucket}"

  home_directory_type = "PATH"

  tags = merge(local.common_tags, {
    Name     = "${local.name_prefix}-${var.sftp_username}"
    UserType = "BusinessPartner"
  })
}

# =============================================================================
# S3 EVENT NOTIFICATION AND EVENTBRIDGE INTEGRATION
# =============================================================================

# S3 bucket notification to EventBridge
resource "aws_s3_bucket_notification" "landing_notification" {
  bucket      = aws_s3_bucket.landing.id
  eventbridge = true
}

# EventBridge rule for S3 events
resource "aws_cloudwatch_event_rule" "s3_file_upload" {
  name        = "${local.name_prefix}-file-processing"
  description = "Trigger file processing workflow on S3 object creation"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.landing.bucket]
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-event-rule"
  })
}

# EventBridge target for Step Functions
resource "aws_cloudwatch_event_target" "stepfunctions" {
  rule      = aws_cloudwatch_event_rule.s3_file_upload.name
  target_id = "StepFunctionsTarget"
  arn       = aws_sfn_state_machine.file_processing.arn
  role_arn  = aws_iam_role.eventbridge_role.arn

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
    }
    input_template = <<EOF
{
  "bucket": "<bucket>",
  "key": "<key>"
}
EOF
  }
}

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

# SNS topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alerts"
  })
}

# SNS topic subscription (if email provided)
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch alarm for failed Step Functions executions
resource "aws_cloudwatch_metric_alarm" "failed_executions" {
  alarm_name          = "${local.name_prefix}-failed-executions"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors Step Functions execution failures"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.file_processing.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-failed-executions-alarm"
  })
}

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = 3
  alarm_name          = "${local.name_prefix}-lambda-errors-${element(["validator", "processor", "router"], count.index)}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = element([
      aws_lambda_function.validator.function_name,
      aws_lambda_function.processor.function_name,
      aws_lambda_function.router.function_name
    ], count.index)
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-errors-${element(["validator", "processor", "router"], count.index)}"
  })
}