# main.tf - Main configuration for DynamoDB Global Tables multi-region infrastructure
# This file defines the core infrastructure components for a production-ready
# DynamoDB Global Tables implementation across multiple AWS regions

# Generate random suffix for unique resource naming
resource "random_password" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for consistent resource naming and configuration
locals {
  # Common naming convention
  table_name             = "${var.table_name_prefix}-${random_password.suffix.result}"
  lambda_function_name   = "${var.lambda_function_name_prefix}-${random_password.suffix.result}"
  iam_role_name         = "GlobalTableRole-${random_password.suffix.result}"
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Recipe      = "dynamodb-global-tables-multi-region"
    },
    var.additional_tags
  )
  
  # Define regions for iteration
  regions = [
    var.primary_region,
    var.secondary_region,
    var.tertiary_region
  ]
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# ===================================================================
# KMS Key for DynamoDB Encryption
# ===================================================================

# KMS key for DynamoDB table encryption
resource "aws_kms_key" "dynamodb_key" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description             = "KMS key for DynamoDB Global Tables encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "dynamodb.amazonaws.com"
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
    Name = "DynamoDB-GlobalTable-KMS-Key"
  })
}

# KMS key alias
resource "aws_kms_alias" "dynamodb_key_alias" {
  count = var.enable_kms_encryption ? 1 : 0
  
  name          = "alias/dynamodb-global-tables-${random_password.suffix.result}"
  target_key_id = aws_kms_key.dynamodb_key[0].key_id
}

# ===================================================================
# DynamoDB Global Table
# ===================================================================

# Primary DynamoDB table with Global Tables configuration
resource "aws_dynamodb_table" "global_table" {
  name           = local.table_name
  billing_mode   = var.billing_mode
  hash_key       = "UserId"
  range_key      = "ProfileType"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  # Point-in-time recovery configuration
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }
  
  # Server-side encryption configuration
  dynamic "server_side_encryption" {
    for_each = var.enable_kms_encryption ? [1] : []
    content {
      enabled     = true
      kms_key_arn = aws_kms_key.dynamodb_key[0].arn
    }
  }
  
  # Table attributes
  attribute {
    name = "UserId"
    type = "S"
  }
  
  attribute {
    name = "ProfileType"
    type = "S"
  }
  
  # Email GSI attribute (only if GSI is enabled)
  dynamic "attribute" {
    for_each = var.enable_email_gsi ? [1] : []
    content {
      name = "Email"
      type = "S"
    }
  }
  
  # Provisioned throughput (only for provisioned billing mode)
  dynamic "read_capacity" {
    for_each = var.billing_mode == "PROVISIONED" ? [1] : []
    content {
      read_capacity = var.read_capacity
    }
  }
  
  dynamic "write_capacity" {
    for_each = var.billing_mode == "PROVISIONED" ? [1] : []
    content {
      write_capacity = var.write_capacity
    }
  }
  
  # Global Secondary Index for email-based queries
  dynamic "global_secondary_index" {
    for_each = var.enable_email_gsi ? [1] : []
    content {
      name            = var.email_gsi_name
      hash_key        = "Email"
      projection_type = "ALL"
      
      # Provisioned throughput for GSI (only for provisioned billing mode)
      read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
      write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
    }
  }
  
  # Global table replicas
  replica {
    region_name = var.secondary_region
    
    # Point-in-time recovery for replica
    point_in_time_recovery = var.enable_point_in_time_recovery
    
    # KMS encryption for replica
    dynamic "server_side_encryption" {
      for_each = var.enable_kms_encryption ? [1] : []
      content {
        enabled     = true
        kms_key_arn = aws_kms_key.dynamodb_key[0].arn
      }
    }
    
    # Provisioned throughput for replica (only for provisioned billing mode)
    dynamic "read_capacity" {
      for_each = var.billing_mode == "PROVISIONED" ? [1] : []
      content {
        read_capacity = var.read_capacity
      }
    }
    
    dynamic "write_capacity" {
      for_each = var.billing_mode == "PROVISIONED" ? [1] : []
      content {
        write_capacity = var.write_capacity
      }
    }
    
    # Global Secondary Index for replica
    dynamic "global_secondary_index" {
      for_each = var.enable_email_gsi ? [1] : []
      content {
        name = var.email_gsi_name
        
        # Provisioned throughput for GSI replica (only for provisioned billing mode)
        read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
        write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
      }
    }
  }
  
  replica {
    region_name = var.tertiary_region
    
    # Point-in-time recovery for replica
    point_in_time_recovery = var.enable_point_in_time_recovery
    
    # KMS encryption for replica
    dynamic "server_side_encryption" {
      for_each = var.enable_kms_encryption ? [1] : []
      content {
        enabled     = true
        kms_key_arn = aws_kms_key.dynamodb_key[0].arn
      }
    }
    
    # Provisioned throughput for replica (only for provisioned billing mode)
    dynamic "read_capacity" {
      for_each = var.billing_mode == "PROVISIONED" ? [1] : []
      content {
        read_capacity = var.read_capacity
      }
    }
    
    dynamic "write_capacity" {
      for_each = var.billing_mode == "PROVISIONED" ? [1] : []
      content {
        write_capacity = var.write_capacity
      }
    }
    
    # Global Secondary Index for replica
    dynamic "global_secondary_index" {
      for_each = var.enable_email_gsi ? [1] : []
      content {
        name = var.email_gsi_name
        
        # Provisioned throughput for GSI replica (only for provisioned billing mode)
        read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
        write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
      }
    }
  }
  
  # Deletion protection
  deletion_protection_enabled = var.enable_deletion_protection
  
  tags = merge(local.common_tags, {
    Name = local.table_name
  })
  
  # Ensure table is created before proceeding with other resources
  lifecycle {
    create_before_destroy = true
  }
}

# ===================================================================
# IAM Role and Policies for Lambda Functions
# ===================================================================

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
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
    Name = local.iam_role_name
  })
}

# IAM policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM policy for DynamoDB access
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "DynamoDBGlobalTableAccess"
  role = aws_iam_role.lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:DescribeTable",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams"
        ]
        Resource = [
          aws_dynamodb_table.global_table.arn,
          "${aws_dynamodb_table.global_table.arn}/*",
          "${aws_dynamodb_table.global_table.arn}/index/*"
        ]
      }
    ]
  })
}

# ===================================================================
# Lambda Function Code
# ===================================================================

# Lambda function source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      table_name = local.table_name
    })
    filename = "lambda_function.py"
  }
}

# Write Lambda function template
resource "local_file" "lambda_function_template" {
  filename = "${path.module}/lambda_function.py.tpl"
  content  = <<-EOF
import json
import boto3
import os
import time
from datetime import datetime
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    """
    Lambda function for testing DynamoDB Global Tables operations
    Supports put, get, scan, update, and delete operations
    """
    
    # Get region from environment or context
    region = os.environ.get('AWS_REGION', context.invoked_function_arn.split(':')[3])
    
    # Initialize DynamoDB resource
    dynamodb = boto3.resource('dynamodb', region_name=region)
    table = dynamodb.Table('${table_name}')
    
    try:
        # Process the operation
        operation = event.get('operation', 'put')
        
        if operation == 'put':
            return handle_put_operation(table, event, region)
        elif operation == 'get':
            return handle_get_operation(table, event, region)
        elif operation == 'scan':
            return handle_scan_operation(table, event, region)
        elif operation == 'update':
            return handle_update_operation(table, event, region)
        elif operation == 'delete':
            return handle_delete_operation(table, event, region)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': f'Unsupported operation: {operation}',
                    'supported_operations': ['put', 'get', 'scan', 'update', 'delete']
                })
            }
    
    except ClientError as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'DynamoDB operation failed',
                'details': str(e),
                'region': region
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Lambda function error',
                'details': str(e),
                'region': region
            })
        }

def handle_put_operation(table, event, region):
    """Handle put item operation"""
    user_id = event.get('userId', f'user-{int(time.time())}')
    profile_type = event.get('profileType', 'standard')
    
    item = {
        'UserId': user_id,
        'ProfileType': profile_type,
        'Name': event.get('name', 'Test User'),
        'Email': event.get('email', 'test@example.com'),
        'Region': region,
        'CreatedAt': datetime.utcnow().isoformat(),
        'LastModified': datetime.utcnow().isoformat()
    }
    
    # Add any additional attributes from the event
    for key, value in event.items():
        if key not in ['operation', 'userId', 'profileType', 'name', 'email']:
            item[key] = value
    
    response = table.put_item(Item=item)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Item created in {region}',
            'userId': user_id,
            'profileType': profile_type,
            'item': item
        })
    }

def handle_get_operation(table, event, region):
    """Handle get item operation"""
    user_id = event.get('userId')
    profile_type = event.get('profileType', 'standard')
    
    if not user_id:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'userId is required for get operation'
            })
        }
    
    response = table.get_item(
        Key={
            'UserId': user_id,
            'ProfileType': profile_type
        }
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Item retrieved from {region}',
            'userId': user_id,
            'profileType': profile_type,
            'item': response.get('Item', 'Not found')
        })
    }

def handle_scan_operation(table, event, region):
    """Handle scan operation"""
    limit = event.get('limit', 10)
    
    response = table.scan(
        ProjectionExpression='UserId, ProfileType, #r, #n, Email',
        ExpressionAttributeNames={
            '#r': 'Region',
            '#n': 'Name'
        },
        Limit=limit
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Items scanned from {region}',
            'count': response['Count'],
            'items': response.get('Items', [])
        })
    }

def handle_update_operation(table, event, region):
    """Handle update item operation"""
    user_id = event.get('userId')
    profile_type = event.get('profileType', 'standard')
    
    if not user_id:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'userId is required for update operation'
            })
        }
    
    # Build update expression
    update_expression = "SET LastModified = :lm, #r = :r"
    expression_attribute_values = {
        ':lm': datetime.utcnow().isoformat(),
        ':r': region
    }
    expression_attribute_names = {
        '#r': 'Region'
    }
    
    # Add additional fields to update
    for key, value in event.items():
        if key not in ['operation', 'userId', 'profileType']:
            attr_name = f'#{key}'
            attr_value = f':{key}'
            update_expression += f', {attr_name} = {attr_value}'
            expression_attribute_names[attr_name] = key
            expression_attribute_values[attr_value] = value
    
    response = table.update_item(
        Key={
            'UserId': user_id,
            'ProfileType': profile_type
        },
        UpdateExpression=update_expression,
        ExpressionAttributeNames=expression_attribute_names,
        ExpressionAttributeValues=expression_attribute_values,
        ReturnValues='ALL_NEW'
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Item updated in {region}',
            'userId': user_id,
            'profileType': profile_type,
            'updated_item': response.get('Attributes', {})
        })
    }

def handle_delete_operation(table, event, region):
    """Handle delete item operation"""
    user_id = event.get('userId')
    profile_type = event.get('profileType', 'standard')
    
    if not user_id:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'userId is required for delete operation'
            })
        }
    
    response = table.delete_item(
        Key={
            'UserId': user_id,
            'ProfileType': profile_type
        },
        ReturnValues='ALL_OLD'
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Item deleted from {region}',
            'userId': user_id,
            'profileType': profile_type,
            'deleted_item': response.get('Attributes', {})
        })
    }
EOF
}

# ===================================================================
# Lambda Functions (Multi-Region)
# ===================================================================

# Lambda function in primary region
resource "aws_lambda_function" "global_table_processor_primary" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = local.table_name
    }
  }
  
  tags = merge(local.common_tags, {
    Name   = "${local.lambda_function_name}-primary"
    Region = var.primary_region
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_dynamodb_policy,
    aws_dynamodb_table.global_table
  ]
}

# Lambda function in secondary region
resource "aws_lambda_function" "global_table_processor_secondary" {
  provider = aws.secondary
  
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = local.table_name
    }
  }
  
  tags = merge(local.common_tags, {
    Name   = "${local.lambda_function_name}-secondary"
    Region = var.secondary_region
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_dynamodb_policy,
    aws_dynamodb_table.global_table
  ]
}

# Lambda function in tertiary region
resource "aws_lambda_function" "global_table_processor_tertiary" {
  provider = aws.tertiary
  
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = local.table_name
    }
  }
  
  tags = merge(local.common_tags, {
    Name   = "${local.lambda_function_name}-tertiary"
    Region = var.tertiary_region
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_dynamodb_policy,
    aws_dynamodb_table.global_table
  ]
}

# ===================================================================
# SNS Topic and Subscription (Optional)
# ===================================================================

# SNS topic for CloudWatch alarm notifications
resource "aws_sns_topic" "cloudwatch_notifications" {
  count = var.enable_sns_notifications ? 1 : 0
  
  name = "GlobalTable-Notifications-${random_password.suffix.result}"
  
  tags = merge(local.common_tags, {
    Name = "GlobalTable-Notifications"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notifications" {
  count = var.enable_sns_notifications ? 1 : 0
  
  topic_arn = aws_sns_topic.cloudwatch_notifications[0].arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

# ===================================================================
# CloudWatch Monitoring and Alarms
# ===================================================================

# CloudWatch alarm for replication latency
resource "aws_cloudwatch_metric_alarm" "replication_latency" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "GlobalTable-ReplicationLatency-${local.table_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReplicationLatency"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Average"
  threshold           = var.replication_latency_threshold
  alarm_description   = "This metric monitors replication latency for DynamoDB Global Tables"
  alarm_actions       = var.enable_sns_notifications ? [aws_sns_topic.cloudwatch_notifications[0].arn] : []
  
  dimensions = {
    TableName       = local.table_name
    ReceivingRegion = var.secondary_region
  }
  
  tags = merge(local.common_tags, {
    Name = "GlobalTable-ReplicationLatency"
  })
}

# CloudWatch alarm for user errors
resource "aws_cloudwatch_metric_alarm" "user_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "GlobalTable-UserErrors-${local.table_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.user_errors_threshold
  alarm_description   = "This metric monitors user errors for DynamoDB Global Tables"
  alarm_actions       = var.enable_sns_notifications ? [aws_sns_topic.cloudwatch_notifications[0].arn] : []
  
  dimensions = {
    TableName = local.table_name
  }
  
  tags = merge(local.common_tags, {
    Name = "GlobalTable-UserErrors"
  })
}

# CloudWatch dashboard for Global Tables monitoring
resource "aws_cloudwatch_dashboard" "global_table_dashboard" {
  count = var.enable_cloudwatch_dashboard ? 1 : 0
  
  dashboard_name = "GlobalTable-${local.table_name}"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", local.table_name],
            [".", "ConsumedWriteCapacityUnits", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.primary_region
          title  = "Read/Write Capacity Consumption"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ReplicationLatency", "TableName", local.table_name, "ReceivingRegion", var.secondary_region],
            [".", ".", ".", ".", ".", var.tertiary_region]
          ]
          period = 300
          stat   = "Average"
          region = var.primary_region
          title  = "Replication Latency"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/DynamoDB", "UserErrors", "TableName", local.table_name],
            [".", "SystemErrors", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.primary_region
          title  = "Error Metrics"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/DynamoDB", "SuccessfulRequestLatency", "TableName", local.table_name, "Operation", "GetItem"],
            [".", ".", ".", ".", ".", "PutItem"],
            [".", ".", ".", ".", ".", "Query"],
            [".", ".", ".", ".", ".", "Scan"]
          ]
          period = 300
          stat   = "Average"
          region = var.primary_region
          title  = "Request Latency by Operation"
        }
      }
    ]
  })
}

# ===================================================================
# Time-based wait for Global Table setup
# ===================================================================

# Wait for Global Table replication to be fully established
resource "time_sleep" "wait_for_global_table" {
  depends_on = [aws_dynamodb_table.global_table]
  
  create_duration = "120s"
}

# ===================================================================
# Test Data (Optional)
# ===================================================================

# Optional: Create test data after Global Table is ready
resource "aws_lambda_invocation" "test_data_creation" {
  count = var.environment == "dev" ? 1 : 0
  
  function_name = aws_lambda_function.global_table_processor_primary.function_name
  
  input = jsonencode({
    operation    = "put"
    userId       = "test-user-001"
    profileType  = "premium"
    name         = "Test User"
    email        = "test@example.com"
    description  = "Test user created by Terraform"
  })
  
  depends_on = [time_sleep.wait_for_global_table]
}