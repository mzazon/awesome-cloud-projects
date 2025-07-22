# EventBridge Archive and Replay Infrastructure
# This file contains the main infrastructure resources for event replay capabilities

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  suffix              = random_string.suffix.result
  event_bus_name     = var.event_bus_name != "" ? var.event_bus_name : "${var.project_name}-bus-${local.suffix}"
  archive_name       = var.archive_name != "" ? var.archive_name : "${var.project_name}-archive-${local.suffix}"
  lambda_function_name = var.lambda_function_name != "" ? var.lambda_function_name : "${var.project_name}-processor-${local.suffix}"
  s3_bucket_name     = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-logs-${local.suffix}"
  rule_name          = "${var.project_name}-rule-${local.suffix}"
  iam_role_name      = "${var.project_name}-lambda-role-${local.suffix}"
  
  # Event pattern for archive filtering
  event_pattern = jsonencode({
    source      = var.event_pattern_sources
    detail-type = var.event_pattern_detail_types
  })
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Purpose     = "EventReplayDemo"
    },
    var.tags
  )
}

# S3 bucket for storing logs and artifacts
resource "aws_s3_bucket" "logs" {
  bucket = local.s3_bucket_name
  
  tags = merge(local.common_tags, {
    Name = local.s3_bucket_name
    Type = "LogStorage"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Custom EventBridge event bus
resource "aws_cloudwatch_event_bus" "custom" {
  name = local.event_bus_name
  
  tags = merge(local.common_tags, {
    Name = local.event_bus_name
    Type = "EventBus"
  })
}

# EventBridge archive for event replay
resource "aws_cloudwatch_event_archive" "main" {
  name             = local.archive_name
  source_arn       = aws_cloudwatch_event_bus.custom.arn
  event_pattern    = local.event_pattern
  retention_days   = var.archive_retention_days
  description      = "Archive for ${var.project_name} events with ${var.archive_retention_days}-day retention"
  
  depends_on = [aws_cloudwatch_event_bus.custom]
}

# IAM role for Lambda function
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
    Type = "IAMRole"
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.iam_role_name}-policy"
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
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.logs.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = aws_cloudwatch_event_bus.custom.arn
      }
    ]
  })
}

# Attach basic Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = <<EOF
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process events and log details for replay analysis
    """
    try:
        # Log the complete event for debugging
        logger.info(f"Received event: {json.dumps(event, indent=2)}")
        
        # Extract event details
        event_source = event.get('source', 'unknown')
        event_type = event.get('detail-type', 'unknown')
        event_time = event.get('time', datetime.utcnow().isoformat())
        
        # Check if this is a replayed event
        replay_name = event.get('replay-name')
        if replay_name:
            logger.info(f"Processing REPLAYED event from: {replay_name}")
            
        # Simulate business logic processing
        if event_source == 'myapp.orders':
            process_order_event(event)
        elif event_source == 'myapp.users':
            process_user_event(event)
        else:
            logger.info(f"Processing generic event: {event_type}")
        
        # Return successful response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'eventSource': event_source,
                'eventType': event_type,
                'isReplay': bool(replay_name)
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        raise

def process_order_event(event):
    """Process order-related events"""
    order_id = event.get('detail', {}).get('orderId', 'unknown')
    logger.info(f"Processing order event for order: {order_id}")
    
def process_user_event(event):
    """Process user-related events"""
    user_id = event.get('detail', {}).get('userId', 'unknown')
    logger.info(f"Processing user event for user: {user_id}")
EOF
    filename = "lambda_function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "event_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.logs.bucket
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.custom.name
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = merge(local.common_tags, {
    Name = local.lambda_function_name
    Type = "LambdaFunction"
  })
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.lambda_function_name}"
    Type = "LogGroup"
  })
}

# EventBridge rule for routing events
resource "aws_cloudwatch_event_rule" "event_rule" {
  name           = local.rule_name
  event_bus_name = aws_cloudwatch_event_bus.custom.name
  description    = "Rule for processing ${var.project_name} events"
  state          = "ENABLED"
  
  event_pattern = local.event_pattern
  
  tags = merge(local.common_tags, {
    Name = local.rule_name
    Type = "EventRule"
  })
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule           = aws_cloudwatch_event_rule.event_rule.name
  event_bus_name = aws_cloudwatch_event_bus.custom.name
  target_id      = "LambdaTarget"
  arn            = aws_lambda_function.event_processor.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.event_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.event_rule.arn
}

# CloudWatch alarm for replay failures (optional)
resource "aws_cloudwatch_metric_alarm" "replay_failures" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "EventBridge-Replay-Failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedReplays"
  namespace           = "AWS/Events"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors EventBridge replay failures"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  
  tags = merge(local.common_tags, {
    Name = "EventBridge-Replay-Failures"
    Type = "CloudWatchAlarm"
  })
}

# CloudWatch log group for replay monitoring
resource "aws_cloudwatch_log_group" "replay_monitoring" {
  name              = "/aws/events/replay-monitoring"
  retention_in_days = 30
  
  tags = merge(local.common_tags, {
    Name = "/aws/events/replay-monitoring"
    Type = "LogGroup"
  })
}

# S3 object for replay automation script
resource "aws_s3_object" "replay_script" {
  bucket = aws_s3_bucket.logs.bucket
  key    = "scripts/replay-automation.sh"
  
  content = <<EOF
#!/bin/bash

# Replay automation script for EventBridge Archive
# Usage: ./replay-automation.sh <archive-name> [hours-back]

ARCHIVE_NAME=$1
HOURS_BACK=$${2:-1}

if [ -z "$ARCHIVE_NAME" ]; then
    echo "Usage: $0 <archive-name> [hours-back]"
    exit 1
fi

# Calculate replay time window
START_TIME=$(date -u -d "$${HOURS_BACK} hours ago" +%Y-%m-%dT%H:%M:%SZ)
END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Generate replay name
REPLAY_NAME="auto-replay-$(date +%Y%m%d-%H%M%S)"

echo "Starting automated replay:"
echo "Archive: $${ARCHIVE_NAME}"
echo "Time window: $${START_TIME} to $${END_TIME}"
echo "Replay name: $${REPLAY_NAME}"

# Get archive source ARN
SOURCE_ARN=$(aws events describe-archive --archive-name $${ARCHIVE_NAME} --query 'SourceArn' --output text)

# Start replay
aws events start-replay \
    --replay-name $${REPLAY_NAME} \
    --event-source-arn $${SOURCE_ARN} \
    --event-start-time $${START_TIME} \
    --event-end-time $${END_TIME} \
    --destination "{\"Arn\": \"$${SOURCE_ARN}\"}"

echo "Replay started successfully: $${REPLAY_NAME}"
EOF
  
  content_type = "text/plain"
  
  tags = merge(local.common_tags, {
    Name = "replay-automation-script"
    Type = "S3Object"
  })
}

# Cross-region replication resources (optional)
resource "aws_cloudwatch_event_bus" "replication" {
  count = var.enable_cross_region_replication ? 1 : 0
  
  provider = aws.replication
  name     = "${local.event_bus_name}-replica"
  
  tags = merge(local.common_tags, {
    Name = "${local.event_bus_name}-replica"
    Type = "EventBus"
    Purpose = "CrossRegionReplication"
  })
}

# Provider configuration for cross-region replication
provider "aws" {
  alias  = "replication"
  region = var.replication_region
  
  default_tags {
    tags = local.common_tags
  }
}