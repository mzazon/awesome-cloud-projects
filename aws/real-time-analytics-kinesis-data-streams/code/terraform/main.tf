# Data sources for current AWS configuration
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and tagging
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  resource_suffix = random_string.suffix.result
  
  common_tags = merge(
    var.enable_cost_allocation_tags ? {
      CostCenter = var.cost_center
      Owner      = var.owner
    } : {},
    {
      Name        = "${local.name_prefix}-${local.resource_suffix}"
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Recipe      = "real-time-analytics-amazon-kinesis-data-streams"
    }
  )
}

# S3 bucket for storing processed analytics data
resource "aws_s3_bucket" "analytics_data" {
  bucket        = "${local.name_prefix}-analytics-data-${local.resource_suffix}"
  force_destroy = var.s3_bucket_force_destroy

  tags = merge(local.common_tags, {
    Purpose = "Analytics data storage"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "analytics_data" {
  bucket = aws_s3_bucket.analytics_data.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "analytics_data" {
  bucket = aws_s3_bucket.analytics_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "analytics_data" {
  bucket = aws_s3_bucket.analytics_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Kinesis Data Stream
resource "aws_kinesis_stream" "analytics_stream" {
  name             = "${local.name_prefix}-stream-${local.resource_suffix}"
  shard_count      = var.shard_count
  retention_period = var.retention_period

  # Enable enhanced monitoring if specified
  dynamic "shard_level_metrics" {
    for_each = var.enable_enhanced_monitoring ? [1] : []
    content {
      enabled = true
      metrics = var.shard_level_metrics
    }
  }

  # Enable encryption at rest
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  tags = merge(local.common_tags, {
    Purpose = "Real-time analytics data stream"
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role-${local.resource_suffix}"

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
    Purpose = "Lambda execution role for stream processing"
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_prefix}-lambda-policy-${local.resource_suffix}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListStreams"
        ]
        Resource = aws_kinesis_stream.analytics_stream.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.analytics_data.arn}/*"
      },
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
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach basic execution role policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "stream_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      s3_bucket_name = aws_s3_bucket.analytics_data.bucket
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for stream processing
resource "aws_lambda_function" "stream_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-processor-${local.resource_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.analytics_data.bucket
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Purpose = "Stream processing function"
  })
}

# Lambda function code template
resource "local_file" "lambda_function" {
  content = <<-EOF
import json
import boto3
import base64
import datetime
import os
from decimal import Decimal

s3_client = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    processed_records = 0
    total_amount = 0
    
    for record in event['Records']:
        # Decode Kinesis data
        payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
        data = json.loads(payload)
        
        # Process analytics data
        processed_records += 1
        
        # Example: Extract transaction amount for financial data
        if 'amount' in data:
            total_amount += float(data['amount'])
        
        # Store processed record to S3
        timestamp = datetime.datetime.now().isoformat()
        s3_key = f"analytics-data/{timestamp[:10]}/{record['kinesis']['sequenceNumber']}.json"
        
        # Add processing metadata
        enhanced_data = {
            'original_data': data,
            'processed_at': timestamp,
            'shard_id': record['kinesis']['partitionKey'],
            'sequence_number': record['kinesis']['sequenceNumber']
        }
        
        s3_client.put_object(
            Bucket=os.environ['S3_BUCKET'],
            Key=s3_key,
            Body=json.dumps(enhanced_data),
            ContentType='application/json'
        )
    
    # Send custom metrics to CloudWatch
    cloudwatch.put_metric_data(
        Namespace='KinesisAnalytics',
        MetricData=[
            {
                'MetricName': 'ProcessedRecords',
                'Value': processed_records,
                'Unit': 'Count'
            },
            {
                'MetricName': 'TotalAmount',
                'Value': total_amount,
                'Unit': 'None'
            }
        ]
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed_records': processed_records,
            'total_amount': total_amount
        })
    }
EOF
  filename = "${path.module}/lambda_function.py"
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-processor-${local.resource_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Purpose = "Lambda function logs"
  })
}

# Lambda event source mapping
resource "aws_lambda_event_source_mapping" "kinesis_lambda" {
  event_source_arn  = aws_kinesis_stream.analytics_stream.arn
  function_name     = aws_lambda_function.stream_processor.arn
  starting_position = "LATEST"
  batch_size        = var.batch_size
  maximum_batching_window_in_seconds = var.maximum_batching_window_in_seconds

  depends_on = [aws_iam_role_policy.lambda_policy]
}

# SNS topic for CloudWatch alarms (if email endpoints provided)
resource "aws_sns_topic" "alerts" {
  count = length(var.alarm_email_endpoints) > 0 ? 1 : 0
  name  = "${local.name_prefix}-alerts-${local.resource_suffix}"

  tags = merge(local.common_tags, {
    Purpose = "CloudWatch alarm notifications"
  })
}

# SNS topic subscriptions for email alerts
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = length(var.alarm_email_endpoints)
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email_endpoints[count.index]
}

# CloudWatch alarm for high incoming records
resource "aws_cloudwatch_metric_alarm" "high_incoming_records" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-high-incoming-records-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.high_incoming_records_threshold
  alarm_description   = "This metric monitors Kinesis incoming records"
  alarm_actions       = length(var.alarm_email_endpoints) > 0 ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    StreamName = aws_kinesis_stream.analytics_stream.name
  }

  tags = merge(local.common_tags, {
    Purpose = "High incoming records monitoring"
  })
}

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-lambda-errors-${local.resource_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.lambda_error_threshold
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = length(var.alarm_email_endpoints) > 0 ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.stream_processor.function_name
  }

  tags = merge(local.common_tags, {
    Purpose = "Lambda error monitoring"
  })
}

# CloudWatch dashboard
resource "aws_cloudwatch_dashboard" "analytics_dashboard" {
  dashboard_name = "${local.name_prefix}-dashboard-${local.resource_suffix}"

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
            ["AWS/Kinesis", "IncomingRecords", "StreamName", aws_kinesis_stream.analytics_stream.name],
            [".", "OutgoingRecords", ".", "."],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.stream_processor.function_name],
            ["KinesisAnalytics", "ProcessedRecords"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Real-Time Analytics Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 6
        height = 6

        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.stream_processor.function_name],
            [".", "Errors", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Performance"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = 6
        width  = 6
        height = 6

        properties = {
          metrics = [
            ["AWS/Kinesis", "IteratorAgeMilliseconds", "StreamName", aws_kinesis_stream.analytics_stream.name],
            [".", "WriteProvisionedThroughputExceeded", ".", "."],
            [".", "ReadProvisionedThroughputExceeded", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Stream Health"
          view   = "timeSeries"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "Analytics monitoring dashboard"
  })
}