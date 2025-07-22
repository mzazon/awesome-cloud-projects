# Main Terraform configuration for serverless real-time analytics pipeline
# This creates a complete data streaming pipeline using Kinesis, Lambda, and DynamoDB

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common resource naming
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Resource names
  kinesis_stream_name    = "${local.name_prefix}-stream-${local.name_suffix}"
  lambda_function_name   = "${local.name_prefix}-processor-${local.name_suffix}"
  dynamodb_table_name    = "${local.name_prefix}-results-${local.name_suffix}"
  iam_role_name         = "${local.name_prefix}-lambda-role-${local.name_suffix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Name        = local.name_prefix
    Environment = var.environment
    Project     = var.project_name
  })
}

# =====================================
# DynamoDB Table for Analytics Results
# =====================================

resource "aws_dynamodb_table" "analytics_results" {
  name           = local.dynamodb_table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "eventId"
  range_key      = "timestamp"

  attribute {
    name = "eventId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  # Global Secondary Index for querying by event type
  global_secondary_index {
    name            = "EventTypeIndex"
    hash_key        = "eventType"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  attribute {
    name = "eventType"
    type = "S"
  }

  # Point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    ResourceType = "DynamoDB"
    Purpose      = "Analytics Data Storage"
  })
}

# =====================================
# Kinesis Data Stream
# =====================================

resource "aws_kinesis_stream" "analytics_stream" {
  name             = local.kinesis_stream_name
  shard_count      = var.kinesis_shard_count
  retention_period = var.kinesis_retention_period

  # Enable server-side encryption
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  # Shard level metrics for monitoring
  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
    "WriteProvisionedThroughputExceeded",
    "ReadProvisionedThroughputExceeded",
    "IncomingBytes",
    "OutgoingBytes"
  ]

  tags = merge(local.common_tags, {
    ResourceType = "Kinesis"
    Purpose      = "Data Stream Ingestion"
  })
}

# =====================================
# IAM Role and Policies for Lambda
# =====================================

# Trust policy document for Lambda service
data "aws_iam_policy_document" "lambda_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# Policy document for Lambda execution permissions
data "aws_iam_policy_document" "lambda_execution_policy" {
  # CloudWatch Logs permissions
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }

  # Kinesis permissions
  statement {
    effect = "Allow"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListShards",
      "kinesis:ListStreams",
      "kinesis:SubscribeToShard"
    ]
    resources = [aws_kinesis_stream.analytics_stream.arn]
  }

  # DynamoDB permissions
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      aws_dynamodb_table.analytics_results.arn,
      "${aws_dynamodb_table.analytics_results.arn}/index/*"
    ]
  }

  # CloudWatch metrics permissions
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name               = local.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json

  tags = merge(local.common_tags, {
    ResourceType = "IAM"
    Purpose      = "Lambda Execution Role"
  })
}

# Attach execution policy to role
resource "aws_iam_role_policy" "lambda_execution_policy" {
  name   = "KinesisLambdaProcessorPolicy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_execution_policy.json
}

# =====================================
# Lambda Function Code Package
# =====================================

# Create Lambda function code
resource "local_file" "lambda_function_code" {
  filename = "${path.module}/lambda_function.py"
  content  = <<EOF
import json
import boto3
import base64
import time
import os
from datetime import datetime
from decimal import Decimal

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')

# Get table reference from environment variable
table_name = os.environ.get('DYNAMODB_TABLE_NAME')
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    """
    Process Kinesis stream records and store analytics in DynamoDB
    """
    print(f"Received {len(event['Records'])} records from Kinesis")
    
    processed_records = 0
    failed_records = 0
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data'])
            data = json.loads(payload.decode('utf-8'))
            
            # Extract event information
            event_id = record['kinesis']['sequenceNumber']
            timestamp = int(record['kinesis']['approximateArrivalTimestamp'])
            
            # Process the data (example: calculate metrics)
            processed_data = process_analytics_data(data)
            
            # Store in DynamoDB
            store_analytics_result(event_id, timestamp, processed_data, data)
            
            # Send custom metrics to CloudWatch
            send_custom_metrics(processed_data)
            
            processed_records += 1
            
        except Exception as e:
            print(f"Error processing record: {str(e)}")
            failed_records += 1
            continue
    
    print(f"Successfully processed {processed_records} records, {failed_records} failed")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': processed_records,
            'failed': failed_records
        })
    }

def process_analytics_data(data):
    """
    Process incoming data and calculate analytics metrics
    """
    processed = {
        'event_type': data.get('eventType', 'unknown'),
        'user_id': data.get('userId', 'anonymous'),
        'session_id': data.get('sessionId', ''),
        'device_type': data.get('deviceType', 'unknown'),
        'location': data.get('location', {}),
        'metrics': {}
    }
    
    # Calculate custom metrics based on event type
    if data.get('eventType') == 'page_view':
        processed['metrics'] = {
            'page_url': data.get('pageUrl', ''),
            'load_time': data.get('loadTime', 0),
            'bounce_rate': calculate_bounce_rate(data)
        }
    elif data.get('eventType') == 'purchase':
        processed['metrics'] = {
            'amount': Decimal(str(data.get('amount', 0))),
            'currency': data.get('currency', 'USD'),
            'items_count': data.get('itemsCount', 0)
        }
    elif data.get('eventType') == 'user_signup':
        processed['metrics'] = {
            'signup_method': data.get('signupMethod', 'email'),
            'campaign_source': data.get('campaignSource', 'direct')
        }
    
    return processed

def calculate_bounce_rate(data):
    """
    Example calculation for bounce rate analytics
    """
    session_length = data.get('sessionLength', 0)
    pages_viewed = data.get('pagesViewed', 1)
    
    # Simple bounce rate calculation
    if session_length < 30 and pages_viewed == 1:
        return 1.0  # High bounce rate
    else:
        return 0.0  # Low bounce rate

def store_analytics_result(event_id, timestamp, processed_data, raw_data):
    """
    Store processed analytics in DynamoDB
    """
    try:
        table.put_item(
            Item={
                'eventId': event_id,
                'timestamp': timestamp,
                'processedAt': int(time.time()),
                'eventType': processed_data['event_type'],
                'userId': processed_data['user_id'],
                'sessionId': processed_data['session_id'],
                'deviceType': processed_data['device_type'],
                'location': processed_data['location'],
                'metrics': processed_data['metrics'],
                'rawData': raw_data
            }
        )
    except Exception as e:
        print(f"Error storing data in DynamoDB: {str(e)}")
        raise

def send_custom_metrics(processed_data):
    """
    Send custom metrics to CloudWatch
    """
    try:
        # Send event type metrics
        cloudwatch.put_metric_data(
            Namespace='RealTimeAnalytics',
            MetricData=[
                {
                    'MetricName': 'EventsProcessed',
                    'Dimensions': [
                        {
                            'Name': 'EventType',
                            'Value': processed_data['event_type']
                        },
                        {
                            'Name': 'DeviceType',
                            'Value': processed_data['device_type']
                        }
                    ],
                    'Value': 1,
                    'Unit': 'Count'
                }
            ]
        )
        
        # Send purchase metrics if applicable
        if processed_data['event_type'] == 'purchase':
            cloudwatch.put_metric_data(
                Namespace='RealTimeAnalytics',
                MetricData=[
                    {
                        'MetricName': 'PurchaseAmount',
                        'Value': float(processed_data['metrics']['amount']),
                        'Unit': 'None'
                    }
                ]
            )
            
    except Exception as e:
        print(f"Error sending CloudWatch metrics: {str(e)}")
        # Don't raise exception to avoid processing failure
EOF
}

# Create deployment package for Lambda
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_function_code.filename
  output_path = "${path.module}/lambda_function.zip"
  depends_on  = [local_file.lambda_function_code]
}

# =====================================
# Lambda Function
# =====================================

resource "aws_lambda_function" "kinesis_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.analytics_results.name
    }
  }

  # Dead letter queue configuration for failed invocations
  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  depends_on = [
    aws_iam_role_policy.lambda_execution_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    ResourceType = "Lambda"
    Purpose      = "Stream Processing"
  })
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    ResourceType = "CloudWatch"
    Purpose      = "Lambda Logs"
  })
}

# Dead Letter Queue for failed Lambda invocations
resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "${local.name_prefix}-lambda-dlq-${local.name_suffix}"
  message_retention_seconds = 1209600 # 14 days

  tags = merge(local.common_tags, {
    ResourceType = "SQS"
    Purpose      = "Dead Letter Queue"
  })
}

# =====================================
# Event Source Mapping
# =====================================

resource "aws_lambda_event_source_mapping" "kinesis_lambda_mapping" {
  event_source_arn          = aws_kinesis_stream.analytics_stream.arn
  function_name             = aws_lambda_function.kinesis_processor.arn
  starting_position         = "LATEST"
  batch_size               = var.lambda_batch_size
  maximum_batching_window_in_seconds = var.lambda_maximum_batching_window

  # Error handling configuration
  maximum_retry_attempts = 3
  maximum_record_age_in_seconds = 3600

  depends_on = [
    aws_iam_role_policy.lambda_execution_policy
  ]
}

# =====================================
# CloudWatch Alarms (Optional)
# =====================================

# SNS Topic for alarm notifications (if email is provided)
resource "aws_sns_topic" "alarm_notifications" {
  count = var.enable_cloudwatch_alarms && var.alarm_email_endpoint != "" ? 1 : 0
  name  = "${local.name_prefix}-alarms-${local.name_suffix}"

  tags = merge(local.common_tags, {
    ResourceType = "SNS"
    Purpose      = "Alarm Notifications"
  })
}

# SNS Topic Subscription for email notifications
resource "aws_sns_topic_subscription" "email_notifications" {
  count     = var.enable_cloudwatch_alarms && var.alarm_email_endpoint != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarm_notifications[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email_endpoint
}

# CloudWatch Alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = var.alarm_email_endpoint != "" ? [aws_sns_topic.alarm_notifications[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.kinesis_processor.function_name
  }

  tags = merge(local.common_tags, {
    ResourceType = "CloudWatch"
    Purpose      = "Error Monitoring"
  })
}

# CloudWatch Alarm for DynamoDB throttling
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttling" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.name_prefix}-dynamodb-throttling"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors DynamoDB throttling events"
  alarm_actions       = var.alarm_email_endpoint != "" ? [aws_sns_topic.alarm_notifications[0].arn] : []

  dimensions = {
    TableName = aws_dynamodb_table.analytics_results.name
  }

  tags = merge(local.common_tags, {
    ResourceType = "CloudWatch"
    Purpose      = "Throttling Monitoring"
  })
}

# CloudWatch Alarm for Kinesis incoming records
resource "aws_cloudwatch_metric_alarm" "kinesis_incoming_records" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.name_prefix}-kinesis-low-throughput"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors Kinesis stream activity"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesis_stream.analytics_stream.name
  }

  tags = merge(local.common_tags, {
    ResourceType = "CloudWatch"
    Purpose      = "Stream Activity Monitoring"
  })
}