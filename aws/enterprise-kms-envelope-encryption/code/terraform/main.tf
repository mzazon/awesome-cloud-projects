# ======================================
# Enterprise KMS Envelope Encryption Infrastructure
# ======================================

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with random suffix
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = "Enterprise KMS Envelope Encryption"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "Key rotation and envelope encryption"
  })
}

# ======================================
# KMS Customer Master Key (CMK)
# ======================================

# KMS key policy document
data "aws_iam_policy_document" "kms_key_policy" {
  # Root account access
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    
    actions   = ["kms:*"]
    resources = ["*"]
  }
  
  # Lambda function access for key management
  statement {
    sid    = "Allow Lambda Key Management"
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.lambda_role.arn]
    }
    
    actions = [
      "kms:DescribeKey",
      "kms:GetKeyRotationStatus",
      "kms:EnableKeyRotation",
      "kms:ListKeys",
      "kms:ListAliases"
    ]
    
    resources = ["*"]
  }
  
  # S3 service access for bucket encryption
  statement {
    sid    = "Allow S3 Service"
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
      "kms:CreateGrant"
    ]
    
    resources = ["*"]
    
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
  
  # Additional principals if specified
  dynamic "statement" {
    for_each = length(var.kms_key_policy_additional_principals) > 0 ? [1] : []
    
    content {
      sid    = "Additional Principals Access"
      effect = "Allow"
      
      principals {
        type        = "AWS"
        identifiers = var.kms_key_policy_additional_principals
      }
      
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      
      resources = ["*"]
    }
  }
}

# KMS Customer Master Key
resource "aws_kms_key" "enterprise_cmk" {
  description              = var.kms_key_description
  key_usage               = "ENCRYPT_DECRYPT"
  key_spec                = "SYMMETRIC_DEFAULT"
  enable_key_rotation     = var.enable_key_rotation
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_key_policy.json
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cmk-${local.name_suffix}"
    Type = "Customer Master Key"
  })
}

# KMS key alias for easier reference
resource "aws_kms_alias" "enterprise_cmk_alias" {
  name          = "alias/${local.name_prefix}-${local.name_suffix}"
  target_key_id = aws_kms_key.enterprise_cmk.key_id
}

# ======================================
# S3 Bucket with KMS Encryption
# ======================================

# S3 bucket for encrypted data storage
resource "aws_s3_bucket" "encrypted_data" {
  bucket        = "${local.name_prefix}-encrypted-data-${local.name_suffix}"
  force_destroy = var.s3_bucket_force_destroy
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-encrypted-data-${local.name_suffix}"
    Type = "Encrypted Data Storage"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "encrypted_data_versioning" {
  bucket = aws_s3_bucket.encrypted_data.id
  
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Suspended"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "encrypted_data_encryption" {
  bucket = aws_s3_bucket.encrypted_data.id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.enterprise_cmk.arn
      sse_algorithm     = "aws:kms"
    }
    
    bucket_key_enabled = var.enable_s3_bucket_key
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "encrypted_data_pab" {
  bucket = aws_s3_bucket.encrypted_data.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ======================================
# Lambda Function for Key Rotation Monitoring
# ======================================

# Lambda function source code
locals {
  lambda_source_code = <<-EOT
import json
import boto3
import logging
from datetime import datetime
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Monitor KMS key rotation status and ensure compliance with enterprise policies.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Response dictionary with monitoring results
    """
    kms_client = boto3.client('kms')
    
    try:
        # List all customer-managed keys
        paginator = kms_client.get_paginator('list_keys')
        
        rotation_status = []
        keys_checked = 0
        keys_with_rotation_enabled = 0
        keys_rotation_enabled = 0
        
        for page in paginator.paginate():
            for key in page['Keys']:
                key_id = key['KeyId']
                
                try:
                    # Get key details
                    key_details = kms_client.describe_key(KeyId=key_id)
                    
                    # Skip AWS-managed keys
                    if key_details['KeyMetadata']['KeyManager'] == 'AWS':
                        continue
                    
                    keys_checked += 1
                    
                    # Check rotation status
                    rotation_response = kms_client.get_key_rotation_status(KeyId=key_id)
                    rotation_enabled = rotation_response['KeyRotationEnabled']
                    
                    if rotation_enabled:
                        keys_with_rotation_enabled += 1
                    
                    key_info = {
                        'KeyId': key_id,
                        'KeyArn': key_details['KeyMetadata']['Arn'],
                        'RotationEnabled': rotation_enabled,
                        'KeyState': key_details['KeyMetadata']['KeyState'],
                        'CreationDate': key_details['KeyMetadata']['CreationDate'].isoformat(),
                        'KeyUsage': key_details['KeyMetadata']['KeyUsage']
                    }
                    
                    # Add alias information if available
                    try:
                        aliases_response = kms_client.list_aliases(KeyId=key_id)
                        if aliases_response['Aliases']:
                            key_info['Aliases'] = [alias['AliasName'] for alias in aliases_response['Aliases']]
                    except Exception as alias_error:
                        logger.warning(f"Could not retrieve aliases for key {key_id}: {str(alias_error)}")
                    
                    rotation_status.append(key_info)
                    
                    # Log key rotation status
                    logger.info(f"Key {key_id}: Rotation {'enabled' if rotation_enabled else 'disabled'}")
                    
                    # Optionally enable rotation if disabled (controlled by environment variable)
                    auto_enable_rotation = os.environ.get('AUTO_ENABLE_ROTATION', 'false').lower() == 'true'
                    
                    if (not rotation_enabled and 
                        key_details['KeyMetadata']['KeyState'] == 'Enabled' and
                        auto_enable_rotation):
                        
                        logger.warning(f"Enabling rotation for key {key_id}")
                        kms_client.enable_key_rotation(KeyId=key_id)
                        keys_rotation_enabled += 1
                        
                except Exception as key_error:
                    logger.error(f"Error processing key {key_id}: {str(key_error)}")
                    continue
        
        # Prepare summary
        summary = {
            'keysChecked': keys_checked,
            'keysWithRotationEnabled': keys_with_rotation_enabled,
            'keysRotationJustEnabled': keys_rotation_enabled,
            'rotationCompliancePercentage': round((keys_with_rotation_enabled / keys_checked * 100), 2) if keys_checked > 0 else 0
        }
        
        logger.info(f"Key rotation monitoring completed: {summary}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Key rotation monitoring completed successfully',
                'summary': summary,
                'timestamp': datetime.now().isoformat(),
                'keysDetails': rotation_status
            }, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error during key rotation monitoring: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Key rotation monitoring failed',
                'timestamp': datetime.now().isoformat()
            })
        }
EOT
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/key_rotation_monitor.zip"
  
  source {
    content  = local.lambda_source_code
    filename = "lambda_function.py"
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role-${local.name_suffix}"
  
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
    Name = "${local.name_prefix}-lambda-role-${local.name_suffix}"
    Type = "Lambda Execution Role"
  })
}

# IAM policy for Lambda KMS operations
resource "aws_iam_policy" "lambda_kms_policy" {
  name        = "${local.name_prefix}-lambda-kms-policy-${local.name_suffix}"
  description = "KMS permissions for key rotation monitoring Lambda function"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:DescribeKey",
          "kms:GetKeyRotationStatus",
          "kms:EnableKeyRotation",
          "kms:ListKeys",
          "kms:ListAliases"
        ]
        Resource = "*"
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
  
  tags = local.common_tags
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach custom KMS policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_kms_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_kms_policy.arn
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-key-rotator-${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-logs-${local.name_suffix}"
    Type = "Lambda Log Group"
  })
}

# Lambda function
resource "aws_lambda_function" "key_rotation_monitor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-key-rotator-${local.name_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      AUTO_ENABLE_ROTATION = "false"  # Set to "true" to automatically enable rotation
      LOG_LEVEL           = "INFO"
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_kms_policy_attachment,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-key-rotator-${local.name_suffix}"
    Type = "Key Rotation Monitor"
  })
}

# ======================================
# CloudWatch Events for Scheduled Execution
# ======================================

# CloudWatch Events rule for scheduled Lambda execution
resource "aws_cloudwatch_event_rule" "key_rotation_schedule" {
  name                = "${local.name_prefix}-key-rotation-schedule-${local.name_suffix}"
  description         = "Schedule for KMS key rotation monitoring"
  schedule_expression = var.monitoring_schedule
  state              = "ENABLED"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-key-rotation-schedule-${local.name_suffix}"
    Type = "CloudWatch Events Rule"
  })
}

# CloudWatch Events target
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.key_rotation_schedule.name
  target_id = "KeyRotationLambdaTarget"
  arn       = aws_lambda_function.key_rotation_monitor.arn
}

# Lambda permission for CloudWatch Events
resource "aws_lambda_permission" "allow_cloudwatch_events" {
  statement_id  = "AllowExecutionFromCloudWatchEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.key_rotation_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.key_rotation_schedule.arn
}

# ======================================
# Sample Data for Testing (Optional)
# ======================================

# Sample S3 object to demonstrate encryption
resource "aws_s3_object" "sample_encrypted_data" {
  bucket       = aws_s3_bucket.encrypted_data.id
  key          = "sample-data/enterprise-data.txt"
  content      = "This is sample enterprise data that demonstrates KMS envelope encryption.\nThe data is automatically encrypted using the enterprise customer master key.\nThis showcases the transparent encryption capabilities of AWS S3 with KMS integration."
  content_type = "text/plain"
  
  # Encryption is handled automatically by bucket-level configuration
  
  tags = merge(local.common_tags, {
    Name = "Sample Encrypted Data"
    Type = "Test Data"
  })
}