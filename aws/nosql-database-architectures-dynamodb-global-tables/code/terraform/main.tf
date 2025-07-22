# DynamoDB Global Tables Infrastructure
# This file creates a globally distributed NoSQL database architecture using DynamoDB Global Tables
# with comprehensive security, monitoring, and backup capabilities across multiple AWS regions

# Get current AWS caller identity for account ID
data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Merge default and additional tags
locals {
  all_tags = merge(
    var.default_tags,
    var.additional_tags,
    {
      Name = "${var.project_name}-${var.environment}"
    }
  )
  
  table_name_with_suffix = "${var.table_name}-${random_string.suffix.result}"
}

# -----------------------------------------------------------------------------
# KMS Keys for Encryption (Region-specific)
# -----------------------------------------------------------------------------

# KMS key for primary region
resource "aws_kms_key" "primary_key" {
  provider = aws.primary
  
  description              = "DynamoDB Global Table encryption key for ${var.primary_region}"
  key_usage               = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  deletion_window_in_days = var.kms_key_deletion_window
  
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
        Sid    = "Allow DynamoDB Service"
        Effect = "Allow"
        Principal = {
          Service = "dynamodb.amazonaws.com"
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
  
  tags = local.all_tags
}

# KMS key alias for primary region
resource "aws_kms_alias" "primary_key_alias" {
  provider = aws.primary
  
  name          = "alias/dynamodb-global-${var.primary_region}-${random_string.suffix.result}"
  target_key_id = aws_kms_key.primary_key.key_id
}

# KMS key for secondary region
resource "aws_kms_key" "secondary_key" {
  provider = aws.secondary
  
  description              = "DynamoDB Global Table encryption key for ${var.secondary_region}"
  key_usage               = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  deletion_window_in_days = var.kms_key_deletion_window
  
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
        Sid    = "Allow DynamoDB Service"
        Effect = "Allow"
        Principal = {
          Service = "dynamodb.dynamodb.amazonaws.com"
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
  
  tags = local.all_tags
}

# KMS key alias for secondary region
resource "aws_kms_alias" "secondary_key_alias" {
  provider = aws.secondary
  
  name          = "alias/dynamodb-global-${var.secondary_region}-${random_string.suffix.result}"
  target_key_id = aws_kms_key.secondary_key.key_id
}

# KMS key for tertiary region
resource "aws_kms_key" "tertiary_key" {
  provider = aws.tertiary
  
  description              = "DynamoDB Global Table encryption key for ${var.tertiary_region}"
  key_usage               = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  deletion_window_in_days = var.kms_key_deletion_window
  
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
        Sid    = "Allow DynamoDB Service"
        Effect = "Allow"
        Principal = {
          Service = "dynamodb.amazonaws.com"
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
  
  tags = local.all_tags
}

# KMS key alias for tertiary region
resource "aws_kms_alias" "tertiary_key_alias" {
  provider = aws.tertiary
  
  name          = "alias/dynamodb-global-${var.tertiary_region}-${random_string.suffix.result}"
  target_key_id = aws_kms_key.tertiary_key.key_id
}

# -----------------------------------------------------------------------------
# IAM Role for DynamoDB Global Tables Access
# -----------------------------------------------------------------------------

# IAM role for applications to access DynamoDB Global Tables
resource "aws_iam_role" "dynamodb_global_role" {
  name = "DynamoDBGlobalTableRole-${random_string.suffix.result}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "ec2.amazonaws.com"
          ]
        }
      }
    ]
  })
  
  tags = local.all_tags
}

# IAM policy for DynamoDB Global Tables operations
resource "aws_iam_role_policy" "dynamodb_global_policy" {
  name = "DynamoDBGlobalTablePolicy-${random_string.suffix.result}"
  role = aws_iam_role.dynamodb_global_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:ConditionCheckItem"
        ]
        Resource = [
          "arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/${local.table_name_with_suffix}",
          "arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/${local.table_name_with_suffix}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams"
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
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# DynamoDB Table (Primary Region)
# -----------------------------------------------------------------------------

# Primary DynamoDB table with Global Tables configuration
resource "aws_dynamodb_table" "primary_table" {
  provider = aws.primary
  
  name           = local.table_name_with_suffix
  billing_mode   = "PROVISIONED"
  read_capacity  = var.read_capacity
  write_capacity = var.write_capacity
  
  # Enable deletion protection
  deletion_protection_enabled = var.enable_deletion_protection
  
  # Composite primary key (PK/SK pattern)
  hash_key  = "PK"
  range_key = "SK"
  
  attribute {
    name = "PK"
    type = "S"
  }
  
  attribute {
    name = "SK"
    type = "S"
  }
  
  attribute {
    name = "GSI1PK"
    type = "S"
  }
  
  attribute {
    name = "GSI1SK"
    type = "S"
  }
  
  # Global Secondary Index for flexible querying
  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
    read_capacity   = var.gsi_read_capacity
    write_capacity  = var.gsi_write_capacity
  }
  
  # Enable DynamoDB Streams for Global Tables replication
  stream_enabled   = true
  stream_view_type = var.stream_view_type
  
  # Server-side encryption configuration
  dynamic "server_side_encryption" {
    for_each = var.enable_server_side_encryption ? [1] : []
    content {
      enabled     = true
      kms_key_arn = aws_kms_key.primary_key.arn
    }
  }
  
  # Point-in-time recovery configuration
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }
  
  # Enable Global Tables
  replica {
    region_name = var.secondary_region
    kms_key_arn = var.enable_server_side_encryption ? aws_kms_key.secondary_key.arn : null
    
    point_in_time_recovery = var.enable_point_in_time_recovery
  }
  
  replica {
    region_name = var.tertiary_region
    kms_key_arn = var.enable_server_side_encryption ? aws_kms_key.tertiary_key.arn : null
    
    point_in_time_recovery = var.enable_point_in_time_recovery
  }
  
  tags = local.all_tags
}

# -----------------------------------------------------------------------------
# Auto Scaling Configuration (Optional)
# -----------------------------------------------------------------------------

# Auto scaling target for table read capacity
resource "aws_appautoscaling_target" "table_read_target" {
  count = var.enable_auto_scaling ? 1 : 0
  
  max_capacity       = var.auto_scaling_max_capacity
  min_capacity       = var.auto_scaling_min_capacity
  resource_id        = "table/${aws_dynamodb_table.primary_table.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

# Auto scaling policy for table read capacity
resource "aws_appautoscaling_policy" "table_read_policy" {
  count = var.enable_auto_scaling ? 1 : 0
  
  name               = "DynamoDBReadCapacityUtilization:${aws_appautoscaling_target.table_read_target[0].resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.table_read_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.table_read_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.table_read_target[0].service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = var.auto_scaling_target_utilization
  }
}

# Auto scaling target for table write capacity
resource "aws_appautoscaling_target" "table_write_target" {
  count = var.enable_auto_scaling ? 1 : 0
  
  max_capacity       = var.auto_scaling_max_capacity
  min_capacity       = var.auto_scaling_min_capacity
  resource_id        = "table/${aws_dynamodb_table.primary_table.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

# Auto scaling policy for table write capacity
resource "aws_appautoscaling_policy" "table_write_policy" {
  count = var.enable_auto_scaling ? 1 : 0
  
  name               = "DynamoDBWriteCapacityUtilization:${aws_appautoscaling_target.table_write_target[0].resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.table_write_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.table_write_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.table_write_target[0].service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = var.auto_scaling_target_utilization
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms for Monitoring
# -----------------------------------------------------------------------------

# CloudWatch alarm for read throttling in primary region
resource "aws_cloudwatch_metric_alarm" "read_throttles_primary" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  provider = aws.primary
  
  alarm_name          = "${local.table_name_with_suffix}-ReadThrottles-${var.primary_region}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ReadThrottledEvents"
  namespace           = "AWS/DynamoDB"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.read_throttle_threshold
  alarm_description   = "High read throttling on ${local.table_name_with_suffix} in ${var.primary_region}"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  
  dimensions = {
    TableName = local.table_name_with_suffix
  }
  
  tags = local.all_tags
}

# CloudWatch alarm for write throttling in primary region
resource "aws_cloudwatch_metric_alarm" "write_throttles_primary" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  provider = aws.primary
  
  alarm_name          = "${local.table_name_with_suffix}-WriteThrottles-${var.primary_region}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "WriteThrottledEvents"
  namespace           = "AWS/DynamoDB"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.write_throttle_threshold
  alarm_description   = "High write throttling on ${local.table_name_with_suffix} in ${var.primary_region}"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  
  dimensions = {
    TableName = local.table_name_with_suffix
  }
  
  tags = local.all_tags
}

# CloudWatch alarm for replication delay in secondary region
resource "aws_cloudwatch_metric_alarm" "replication_delay_secondary" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  provider = aws.secondary
  
  alarm_name          = "${local.table_name_with_suffix}-ReplicationLag-${var.secondary_region}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ReplicationDelay"
  namespace           = "AWS/DynamoDB"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.replication_delay_threshold
  alarm_description   = "High replication lag on ${local.table_name_with_suffix} in ${var.secondary_region}"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  
  dimensions = {
    TableName       = local.table_name_with_suffix
    ReceivingRegion = var.secondary_region
  }
  
  tags = local.all_tags
}

# CloudWatch alarm for replication delay in tertiary region
resource "aws_cloudwatch_metric_alarm" "replication_delay_tertiary" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  provider = aws.tertiary
  
  alarm_name          = "${local.table_name_with_suffix}-ReplicationLag-${var.tertiary_region}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ReplicationDelay"
  namespace           = "AWS/DynamoDB"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.replication_delay_threshold
  alarm_description   = "High replication lag on ${local.table_name_with_suffix} in ${var.tertiary_region}"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  
  dimensions = {
    TableName       = local.table_name_with_suffix
    ReceivingRegion = var.tertiary_region
  }
  
  tags = local.all_tags
}

# -----------------------------------------------------------------------------
# AWS Backup Configuration
# -----------------------------------------------------------------------------

# Backup vault for DynamoDB table
resource "aws_backup_vault" "dynamodb_backup_vault" {
  count = var.enable_backup ? 1 : 0
  
  provider = aws.primary
  
  name        = "DynamoDB-Global-Backup-${random_string.suffix.result}"
  kms_key_arn = aws_kms_key.primary_key.arn
  
  tags = local.all_tags
}

# Backup plan for automated backups
resource "aws_backup_plan" "dynamodb_backup_plan" {
  count = var.enable_backup ? 1 : 0
  
  provider = aws.primary
  
  name = "DynamoDB-Global-Backup-Plan-${random_string.suffix.result}"
  
  rule {
    rule_name         = "DailyBackups"
    target_vault_name = aws_backup_vault.dynamodb_backup_vault[0].name
    schedule          = var.backup_schedule
    start_window      = var.backup_start_window
    completion_window = var.backup_completion_window
    
    lifecycle {
      delete_after = var.backup_retention_days
    }
    
    recovery_point_tags = merge(
      local.all_tags,
      {
        BackupType = "Automated"
      }
    )
  }
  
  tags = local.all_tags
}

# IAM role for AWS Backup
resource "aws_iam_role" "backup_role" {
  count = var.enable_backup ? 1 : 0
  
  name = "AWSBackupServiceRole-${random_string.suffix.result}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.all_tags
}

# Attach AWS managed policy for backup service role
resource "aws_iam_role_policy_attachment" "backup_service_policy" {
  count = var.enable_backup ? 1 : 0
  
  role       = aws_iam_role.backup_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# Backup selection to specify which resources to backup
resource "aws_backup_selection" "dynamodb_backup_selection" {
  count = var.enable_backup ? 1 : 0
  
  provider = aws.primary
  
  iam_role_arn = aws_iam_role.backup_role[0].arn
  name         = "DynamoDB-Global-Selection"
  plan_id      = aws_backup_plan.dynamodb_backup_plan[0].id
  
  resources = [
    aws_dynamodb_table.primary_table.arn
  ]
  
  condition {
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.environment
    }
  }
}

# -----------------------------------------------------------------------------
# Lambda Function for Testing Global Tables
# -----------------------------------------------------------------------------

# Lambda function for testing cross-region operations
resource "aws_lambda_function" "global_table_test" {
  count = var.enable_lambda_demo ? 1 : 0
  
  provider = aws.primary
  
  filename         = "global-table-test.zip"
  function_name    = "global-table-test-${random_string.suffix.result}"
  role            = aws_iam_role.dynamodb_global_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  environment {
    variables = {
      TABLE_NAME = local.table_name_with_suffix
      REGIONS    = "${var.primary_region},${var.secondary_region},${var.tertiary_region}"
    }
  }
  
  tags = local.all_tags
}

# Lambda function code (inline for simplicity)
data "archive_file" "lambda_zip" {
  count = var.enable_lambda_demo ? 1 : 0
  
  type        = "zip"
  output_path = "global-table-test.zip"
  
  source {
    content = <<EOF
import json
import boto3
import os
from datetime import datetime, timezone
import uuid

def lambda_handler(event, context):
    table_name = os.environ['TABLE_NAME']
    regions = os.environ['REGIONS'].split(',')
    
    results = {}
    
    for region in regions:
        try:
            dynamodb = boto3.resource('dynamodb', region_name=region)
            table = dynamodb.Table(table_name)
            
            # Test write operation in each region
            test_item = {
                'PK': f'TEST#{uuid.uuid4()}',
                'SK': 'LAMBDA_TEST',
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'region': region,
                'test_data': f'Test from Lambda in {region}'
            }
            
            table.put_item(Item=test_item)
            
            # Test read operation to verify data accessibility
            response = table.scan(
                FilterExpression='attribute_exists(#r)',
                ExpressionAttributeNames={'#r': 'region'},
                Limit=5
            )
            
            results[region] = {
                'write_success': True,
                'items_count': response['Count'],
                'sample_items': response['Items'][:2]  # First 2 items
            }
            
        except Exception as e:
            results[region] = {
                'error': str(e),
                'write_success': False
            }
    
    return {
        'statusCode': 200,
        'body': json.dumps(results, default=str)
    }
EOF
    filename = "lambda_function.py"
  }
}

# Update Lambda function code
resource "aws_lambda_function" "global_table_test_with_code" {
  count = var.enable_lambda_demo ? 1 : 0
  
  provider = aws.primary
  
  filename         = data.archive_file.lambda_zip[0].output_path
  function_name    = "global-table-test-${random_string.suffix.result}"
  role            = aws_iam_role.dynamodb_global_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = local.table_name_with_suffix
      REGIONS    = "${var.primary_region},${var.secondary_region},${var.tertiary_region}"
    }
  }
  
  tags = local.all_tags
}