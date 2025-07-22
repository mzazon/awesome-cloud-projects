# Advanced DynamoDB Streaming Architectures with Global Tables
# This Terraform configuration creates a comprehensive multi-region DynamoDB architecture
# with Global Tables, DynamoDB Streams, Kinesis Data Streams, and Lambda processors

# Generate random suffix for unique resource naming
resource "random_password" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
}

locals {
  # Resource naming with random suffix
  table_name         = "${var.table_base_name}-${random_password.suffix.result}"
  kinesis_stream_name = "${var.kinesis_stream_base_name}-${random_password.suffix.result}"
  lambda_role_name   = "ecommerce-lambda-role-${random_password.suffix.result}"
  
  # Common tags for all resources
  common_tags = merge(
    {
      Application = "ECommerce"
      Environment = var.environment
      Recipe      = "advanced-dynamodb-streaming-global-tables"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# ========================================
# IAM Role for Lambda Functions
# ========================================

# IAM role for Lambda execution with necessary permissions
resource "aws_iam_role" "lambda_execution_role" {
  name = local.lambda_role_name

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

  tags = local.common_tags
}

# Attach basic execution role policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for DynamoDB, Kinesis, and EventBridge access
resource "aws_iam_role_policy" "lambda_custom_policy" {
  name = "${local.lambda_role_name}-custom-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams"
        ]
        Resource = [
          "arn:aws:dynamodb:*:*:table/${local.table_name}",
          "arn:aws:dynamodb:*:*:table/${local.table_name}/stream/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListStreams"
        ]
        Resource = "arn:aws:kinesis:*:*:stream/${local.kinesis_stream_name}"
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# ========================================
# Kinesis Data Streams (All Regions)
# ========================================

# Kinesis Data Stream in primary region
resource "aws_kinesis_stream" "primary" {
  provider   = aws.primary
  name       = local.kinesis_stream_name
  shard_count = var.kinesis_shard_count

  shard_level_metrics = var.enable_enhanced_monitoring ? [
    "IncomingBytes",
    "IncomingRecords",
    "IteratorAgeMilliseconds",
    "OutgoingBytes",
    "OutgoingRecords",
    "ReadProvisionedThroughputExceeded",
    "WriteProvisionedThroughputExceeded"
  ] : []

  tags = local.common_tags
}

# Kinesis Data Stream in secondary region
resource "aws_kinesis_stream" "secondary" {
  provider   = aws.secondary
  name       = local.kinesis_stream_name
  shard_count = var.kinesis_shard_count

  shard_level_metrics = var.enable_enhanced_monitoring ? [
    "IncomingBytes",
    "IncomingRecords",
    "IteratorAgeMilliseconds",
    "OutgoingBytes",
    "OutgoingRecords",
    "ReadProvisionedThroughputExceeded",
    "WriteProvisionedThroughputExceeded"
  ] : []

  tags = local.common_tags
}

# Kinesis Data Stream in tertiary region
resource "aws_kinesis_stream" "tertiary" {
  provider   = aws.tertiary
  name       = local.kinesis_stream_name
  shard_count = var.kinesis_shard_count

  shard_level_metrics = var.enable_enhanced_monitoring ? [
    "IncomingBytes",
    "IncomingRecords",
    "IteratorAgeMilliseconds",
    "OutgoingBytes",
    "OutgoingRecords",
    "ReadProvisionedThroughputExceeded",
    "WriteProvisionedThroughputExceeded"
  ] : []

  tags = local.common_tags
}

# ========================================
# DynamoDB Tables (All Regions)
# ========================================

# Primary DynamoDB table with streams enabled
resource "aws_dynamodb_table" "primary" {
  provider   = aws.primary
  name       = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key   = "PK"
  range_key  = "SK"

  # Table attributes
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

  # Global Secondary Index for alternate access patterns
  global_secondary_index {
    name     = "GSI1"
    hash_key = "GSI1PK"
    range_key = "GSI1SK"
    projection_type = "ALL"
  }

  # Enable DynamoDB Streams with new and old images
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  tags = local.common_tags
}

# Secondary DynamoDB table (replica)
resource "aws_dynamodb_table" "secondary" {
  provider   = aws.secondary
  name       = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key   = "PK"
  range_key  = "SK"

  # Table attributes
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

  # Global Secondary Index for alternate access patterns
  global_secondary_index {
    name     = "GSI1"
    hash_key = "GSI1PK"
    range_key = "GSI1SK"
    projection_type = "ALL"
  }

  # Enable DynamoDB Streams with new and old images
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  tags = local.common_tags
}

# Tertiary DynamoDB table (replica)
resource "aws_dynamodb_table" "tertiary" {
  provider   = aws.tertiary
  name       = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key   = "PK"
  range_key  = "SK"

  # Table attributes
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

  # Global Secondary Index for alternate access patterns
  global_secondary_index {
    name     = "GSI1"
    hash_key = "GSI1PK"
    range_key = "GSI1SK"
    projection_type = "ALL"
  }

  # Enable DynamoDB Streams with new and old images
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  tags = local.common_tags
}

# ========================================
# Global Tables Configuration
# ========================================

# Global tables configuration
resource "aws_dynamodb_global_table" "ecommerce_global" {
  provider = aws.primary
  name     = local.table_name

  replica {
    region_name = var.primary_region
  }

  replica {
    region_name = var.secondary_region
  }

  replica {
    region_name = var.tertiary_region
  }

  depends_on = [
    aws_dynamodb_table.primary,
    aws_dynamodb_table.secondary,
    aws_dynamodb_table.tertiary
  ]
}

# ========================================
# Kinesis Data Streams Integration
# ========================================

# Enable Kinesis Data Streams for DynamoDB (Primary region only for Global Tables)
resource "aws_dynamodb_kinesis_streaming_destination" "primary" {
  provider   = aws.primary
  stream_arn = aws_kinesis_stream.primary.arn
  table_name = aws_dynamodb_table.primary.name

  depends_on = [aws_dynamodb_global_table.ecommerce_global]
}

# ========================================
# Lambda Functions for Stream Processing
# ========================================

# Lambda function code for DynamoDB Streams processing
data "archive_file" "stream_processor_zip" {
  type        = "zip"
  output_path = "/tmp/stream-processor.zip"
  
  source {
    content = <<EOF
import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def decimal_default(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def lambda_handler(event, context):
    for record in event['Records']:
        if record['eventName'] in ['INSERT', 'MODIFY', 'REMOVE']:
            process_record(record)
    return {'statusCode': 200}

def process_record(record):
    event_name = record['eventName']
    table_name = record['eventSourceARN'].split('/')[-3]
    
    # Extract item data
    if 'NewImage' in record['dynamodb']:
        new_image = record['dynamodb']['NewImage']
        pk = new_image.get('PK', {}).get('S', '')
        
        # Process different entity types
        if pk.startswith('PRODUCT#'):
            process_product_event(event_name, new_image, record.get('dynamodb', {}).get('OldImage'))
        elif pk.startswith('ORDER#'):
            process_order_event(event_name, new_image, record.get('dynamodb', {}).get('OldImage'))
        elif pk.startswith('USER#'):
            process_user_event(event_name, new_image, record.get('dynamodb', {}).get('OldImage'))

def process_product_event(event_name, new_image, old_image):
    # Inventory management logic
    if event_name == 'MODIFY' and old_image:
        old_stock = int(old_image.get('Stock', {}).get('N', '0'))
        new_stock = int(new_image.get('Stock', {}).get('N', '0'))
        
        if old_stock != new_stock:
            send_inventory_alert(new_image, old_stock, new_stock)

def process_order_event(event_name, new_image, old_image):
    # Order processing logic
    if event_name == 'INSERT':
        send_order_notification(new_image)
    elif event_name == 'MODIFY':
        status_changed = check_order_status_change(new_image, old_image)
        if status_changed:
            send_status_update(new_image)

def process_user_event(event_name, new_image, old_image):
    # User activity tracking
    if event_name == 'MODIFY':
        send_user_activity_event(new_image)

def send_inventory_alert(product, old_stock, new_stock):
    eventbridge.put_events(
        Entries=[{
            'Source': 'ecommerce.inventory',
            'DetailType': 'Inventory Change',
            'Detail': json.dumps({
                'productId': product.get('PK', {}).get('S', ''),
                'oldStock': old_stock,
                'newStock': new_stock,
                'timestamp': product.get('UpdatedAt', {}).get('S', '')
            })
        }]
    )

def send_order_notification(order):
    eventbridge.put_events(
        Entries=[{
            'Source': 'ecommerce.orders',
            'DetailType': 'New Order',
            'Detail': json.dumps({
                'orderId': order.get('PK', {}).get('S', ''),
                'customerId': order.get('CustomerId', {}).get('S', ''),
                'amount': order.get('TotalAmount', {}).get('N', ''),
                'timestamp': order.get('CreatedAt', {}).get('S', '')
            })
        }]
    )

def send_status_update(order):
    eventbridge.put_events(
        Entries=[{
            'Source': 'ecommerce.orders',
            'DetailType': 'Order Status Update',
            'Detail': json.dumps({
                'orderId': order.get('PK', {}).get('S', ''),
                'status': order.get('Status', {}).get('S', ''),
                'timestamp': order.get('UpdatedAt', {}).get('S', '')
            })
        }]
    )

def send_user_activity_event(user):
    eventbridge.put_events(
        Entries=[{
            'Source': 'ecommerce.users',
            'DetailType': 'User Activity',
            'Detail': json.dumps({
                'userId': user.get('PK', {}).get('S', ''),
                'lastActive': user.get('LastActiveAt', {}).get('S', ''),
                'timestamp': user.get('UpdatedAt', {}).get('S', '')
            })
        }]
    )

def check_order_status_change(new_image, old_image):
    if not old_image:
        return False
    old_status = old_image.get('Status', {}).get('S', '')
    new_status = new_image.get('Status', {}).get('S', '')
    return old_status != new_status
EOF
    filename = "stream-processor.py"
  }
}

# Lambda function code for Kinesis Data Streams processing
data "archive_file" "kinesis_processor_zip" {
  type        = "zip"
  output_path = "/tmp/kinesis-processor.zip"
  
  source {
    content = <<EOF
import json
import boto3
import base64
from datetime import datetime

cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    metrics_data = []
    
    for record in event['Records']:
        # Decode Kinesis data
        payload = json.loads(base64.b64decode(record['kinesis']['data']))
        
        # Extract metrics based on event type
        if payload.get('eventName') == 'INSERT':
            process_insert_metrics(payload, metrics_data)
        elif payload.get('eventName') == 'MODIFY':
            process_modify_metrics(payload, metrics_data)
        elif payload.get('eventName') == 'REMOVE':
            process_remove_metrics(payload, metrics_data)
    
    # Send metrics to CloudWatch
    if metrics_data:
        send_metrics(metrics_data)
    
    return {'statusCode': 200, 'body': f'Processed {len(event["Records"])} records'}

def process_insert_metrics(payload, metrics_data):
    dynamodb_data = payload.get('dynamodb', {})
    new_image = dynamodb_data.get('NewImage', {})
    pk = new_image.get('PK', {}).get('S', '')
    
    if pk.startswith('ORDER#'):
        amount = float(new_image.get('TotalAmount', {}).get('N', '0'))
        metrics_data.append({
            'MetricName': 'NewOrders',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [{'Name': 'EntityType', 'Value': 'Order'}]
        })
        metrics_data.append({
            'MetricName': 'OrderValue',
            'Value': amount,
            'Unit': 'None',
            'Dimensions': [{'Name': 'EntityType', 'Value': 'Order'}]
        })
    elif pk.startswith('PRODUCT#'):
        metrics_data.append({
            'MetricName': 'NewProducts',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [{'Name': 'EntityType', 'Value': 'Product'}]
        })

def process_modify_metrics(payload, metrics_data):
    dynamodb_data = payload.get('dynamodb', {})
    new_image = dynamodb_data.get('NewImage', {})
    old_image = dynamodb_data.get('OldImage', {})
    pk = new_image.get('PK', {}).get('S', '')
    
    if pk.startswith('PRODUCT#'):
        old_stock = int(old_image.get('Stock', {}).get('N', '0'))
        new_stock = int(new_image.get('Stock', {}).get('N', '0'))
        stock_change = new_stock - old_stock
        
        if stock_change != 0:
            metrics_data.append({
                'MetricName': 'InventoryChange',
                'Value': abs(stock_change),
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'EntityType', 'Value': 'Product'},
                    {'Name': 'ChangeType', 'Value': 'Increase' if stock_change > 0 else 'Decrease'}
                ]
            })

def process_remove_metrics(payload, metrics_data):
    dynamodb_data = payload.get('dynamodb', {})
    old_image = dynamodb_data.get('OldImage', {})
    pk = old_image.get('PK', {}).get('S', '')
    
    if pk.startswith('ORDER#'):
        metrics_data.append({
            'MetricName': 'CancelledOrders',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [{'Name': 'EntityType', 'Value': 'Order'}]
        })

def send_metrics(metrics_data):
    cloudwatch.put_metric_data(
        Namespace='ECommerce/Global',
        MetricData=[{
            **metric,
            'Timestamp': datetime.utcnow()
        } for metric in metrics_data]
    )
EOF
    filename = "kinesis-processor.py"
  }
}

# DynamoDB Stream processor Lambda functions (all regions)
resource "aws_lambda_function" "stream_processor_primary" {
  provider      = aws.primary
  function_name = "${local.table_name}-stream-processor"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "stream-processor.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  filename         = data.archive_file.stream_processor_zip.output_path
  source_code_hash = data.archive_file.stream_processor_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = local.table_name
      REGION     = var.primary_region
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_function" "stream_processor_secondary" {
  provider      = aws.secondary
  function_name = "${local.table_name}-stream-processor"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "stream-processor.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  filename         = data.archive_file.stream_processor_zip.output_path
  source_code_hash = data.archive_file.stream_processor_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = local.table_name
      REGION     = var.secondary_region
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_function" "stream_processor_tertiary" {
  provider      = aws.tertiary
  function_name = "${local.table_name}-stream-processor"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "stream-processor.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  filename         = data.archive_file.stream_processor_zip.output_path
  source_code_hash = data.archive_file.stream_processor_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = local.table_name
      REGION     = var.tertiary_region
    }
  }

  tags = local.common_tags
}

# Kinesis processor Lambda functions (all regions)
resource "aws_lambda_function" "kinesis_processor_primary" {
  provider      = aws.primary
  function_name = "${local.kinesis_stream_name}-kinesis-processor"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "kinesis-processor.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  filename         = data.archive_file.kinesis_processor_zip.output_path
  source_code_hash = data.archive_file.kinesis_processor_zip.output_base64sha256

  tags = local.common_tags
}

resource "aws_lambda_function" "kinesis_processor_secondary" {
  provider      = aws.secondary
  function_name = "${local.kinesis_stream_name}-kinesis-processor"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "kinesis-processor.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  filename         = data.archive_file.kinesis_processor_zip.output_path
  source_code_hash = data.archive_file.kinesis_processor_zip.output_base64sha256

  tags = local.common_tags
}

resource "aws_lambda_function" "kinesis_processor_tertiary" {
  provider      = aws.tertiary
  function_name = "${local.kinesis_stream_name}-kinesis-processor"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "kinesis-processor.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  filename         = data.archive_file.kinesis_processor_zip.output_path
  source_code_hash = data.archive_file.kinesis_processor_zip.output_base64sha256

  tags = local.common_tags
}

# ========================================
# Event Source Mappings
# ========================================

# DynamoDB Streams event source mappings
resource "aws_lambda_event_source_mapping" "dynamodb_stream_primary" {
  provider          = aws.primary
  event_source_arn  = aws_dynamodb_table.primary.stream_arn
  function_name     = aws_lambda_function.stream_processor_primary.arn
  starting_position = "LATEST"
  batch_size        = var.stream_batch_size
  maximum_batching_window_in_seconds = 5
}

resource "aws_lambda_event_source_mapping" "dynamodb_stream_secondary" {
  provider          = aws.secondary
  event_source_arn  = aws_dynamodb_table.secondary.stream_arn
  function_name     = aws_lambda_function.stream_processor_secondary.arn
  starting_position = "LATEST"
  batch_size        = var.stream_batch_size
  maximum_batching_window_in_seconds = 5
}

resource "aws_lambda_event_source_mapping" "dynamodb_stream_tertiary" {
  provider          = aws.tertiary
  event_source_arn  = aws_dynamodb_table.tertiary.stream_arn
  function_name     = aws_lambda_function.stream_processor_tertiary.arn
  starting_position = "LATEST"
  batch_size        = var.stream_batch_size
  maximum_batching_window_in_seconds = 5
}

# Kinesis Data Streams event source mappings
resource "aws_lambda_event_source_mapping" "kinesis_stream_primary" {
  provider               = aws.primary
  event_source_arn       = aws_kinesis_stream.primary.arn
  function_name          = aws_lambda_function.kinesis_processor_primary.arn
  starting_position      = "LATEST"
  batch_size             = var.kinesis_batch_size
  maximum_batching_window_in_seconds = 10
  parallelization_factor = var.stream_parallelization_factor
}

resource "aws_lambda_event_source_mapping" "kinesis_stream_secondary" {
  provider               = aws.secondary
  event_source_arn       = aws_kinesis_stream.secondary.arn
  function_name          = aws_lambda_function.kinesis_processor_secondary.arn
  starting_position      = "LATEST"
  batch_size             = var.kinesis_batch_size
  maximum_batching_window_in_seconds = 10
  parallelization_factor = var.stream_parallelization_factor
}

resource "aws_lambda_event_source_mapping" "kinesis_stream_tertiary" {
  provider               = aws.tertiary
  event_source_arn       = aws_kinesis_stream.tertiary.arn
  function_name          = aws_lambda_function.kinesis_processor_tertiary.arn
  starting_position      = "LATEST"
  batch_size             = var.kinesis_batch_size
  maximum_batching_window_in_seconds = 10
  parallelization_factor = var.stream_parallelization_factor
}

# ========================================
# CloudWatch Dashboard
# ========================================

# CloudWatch dashboard for global monitoring
resource "aws_cloudwatch_dashboard" "global_monitoring" {
  provider       = aws.primary
  dashboard_name = var.cloudwatch_dashboard_name

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
            ["ECommerce/Global", "NewOrders", "EntityType", "Order"],
            [".", "OrderValue", ".", "."],
            [".", "CancelledOrders", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.primary_region
          title  = "Order Metrics - Global"
          view   = "timeSeries"
          stacked = false
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
            ["ECommerce/Global", "InventoryChange", "EntityType", "Product", "ChangeType", "Increase"],
            ["...", "Decrease"]
          ]
          period = 300
          stat   = "Sum"
          region = var.primary_region
          title  = "Inventory Changes - Global"
          view   = "timeSeries"
          stacked = false
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
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", local.table_name],
            [".", "ConsumedWriteCapacityUnits", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.primary_region
          title  = "DynamoDB Capacity - Primary Region"
          view   = "timeSeries"
          stacked = false
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
            ["AWS/Kinesis", "IncomingRecords", "StreamName", local.kinesis_stream_name],
            [".", "OutgoingRecords", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.primary_region
          title  = "Kinesis Stream Metrics - Primary Region"
          view   = "timeSeries"
          stacked = false
        }
      }
    ]
  })

  tags = local.common_tags
}