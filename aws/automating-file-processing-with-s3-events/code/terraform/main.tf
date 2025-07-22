# S3 Event Notifications and Automated Processing Infrastructure

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  bucket_name          = "${var.project_name}-${var.bucket_name_suffix}-${random_string.suffix.result}"
  sns_topic_name       = "${var.project_name}-notifications-${random_string.suffix.result}"
  sqs_queue_name       = "${var.project_name}-queue-${random_string.suffix.result}"
  lambda_function_name = "${var.project_name}-processor-${random_string.suffix.result}"
  
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# S3 Bucket for file uploads and processing
resource "aws_s3_bucket" "file_processing" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Purpose     = "File processing and event notifications"
    Component   = "Storage"
  })
}

# S3 Bucket versioning configuration
resource "aws_s3_bucket_versioning" "file_processing" {
  bucket = aws_s3_bucket.file_processing.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "file_processing" {
  bucket = aws_s3_bucket.file_processing.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket public access block for security
resource "aws_s3_bucket_public_access_block" "file_processing" {
  bucket = aws_s3_bucket.file_processing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create test directory structure in S3 (optional)
resource "aws_s3_object" "test_directories" {
  for_each = var.create_test_directories ? toset(["uploads/", "batch/", "immediate/"]) : toset([])
  
  bucket = aws_s3_bucket.file_processing.id
  key    = each.value
  
  tags = merge(local.common_tags, {
    Name      = each.value
    Purpose   = "Test directory structure"
    Component = "Storage"
  })
}

# SNS Topic for file upload notifications
resource "aws_sns_topic" "file_notifications" {
  name = local.sns_topic_name

  tags = merge(local.common_tags, {
    Name        = local.sns_topic_name
    Purpose     = "File upload notifications"
    Component   = "Messaging"
  })
}

# SNS Topic policy to allow S3 to publish messages
resource "aws_sns_topic_policy" "file_notifications" {
  arn = aws_sns_topic.file_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.file_notifications.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.file_processing.arn
          }
        }
      }
    ]
  })
}

# SNS Topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "your-email@example.com" ? 1 : 0
  topic_arn = aws_sns_topic.file_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SQS Queue for batch processing
resource "aws_sqs_queue" "batch_processing" {
  name                       = local.sqs_queue_name
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention_seconds
  receive_wait_time_seconds  = 20 # Enable long polling

  tags = merge(local.common_tags, {
    Name        = local.sqs_queue_name
    Purpose     = "Batch file processing queue"
    Component   = "Messaging"
  })
}

# SQS Queue policy to allow S3 to send messages
resource "aws_sqs_queue_policy" "batch_processing" {
  queue_url = aws_sqs_queue.batch_processing.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SQS:SendMessage"
        Resource = aws_sqs_queue.batch_processing.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.file_processing.arn
          }
        }
      }
    ]
  })
}

# Dead Letter Queue for failed message processing
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.sqs_queue_name}-dlq"
  message_retention_seconds = var.sqs_message_retention_seconds

  tags = merge(local.common_tags, {
    Name        = "${local.sqs_queue_name}-dlq"
    Purpose     = "Dead letter queue for failed processing"
    Component   = "Messaging"
  })
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "/aws/lambda/${local.lambda_function_name}"
    Purpose     = "Lambda function logs"
    Component   = "Monitoring"
  })
}

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution" {
  name = "${local.lambda_function_name}-role"

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
    Name        = "${local.lambda_function_name}-role"
    Purpose     = "Lambda execution role"
    Component   = "Security"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM policy for Lambda to access S3 bucket
resource "aws_iam_role_policy" "lambda_s3_access" {
  name = "${local.lambda_function_name}-s3-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectTagging"
        ]
        Resource = "${aws_s3_bucket.file_processing.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.file_processing.arn
      }
    ]
  })
}

# Lambda function source code
resource "local_file" "lambda_source" {
  content = <<EOF
import json
import boto3
import urllib.parse
from datetime import datetime

def lambda_handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    for record in event['Records']:
        # Parse S3 event
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'])
        size = record['s3']['object']['size']
        event_name = record['eventName']
        
        print(f"Processing {event_name} for {key} in bucket {bucket}")
        print(f"File size: {size} bytes")
        
        # Simulate processing based on file type
        if key.lower().endswith(('.jpg', '.jpeg', '.png', '.gif')):
            print("Processing image file - would trigger image processing")
        elif key.lower().endswith(('.mp4', '.mov', '.avi')):
            print("Processing video file - would trigger video transcoding")
        elif key.lower().endswith(('.pdf', '.doc', '.docx')):
            print("Processing document - would extract metadata")
        else:
            print("Unknown file type - logging for review")
        
        # Log processing completion
        print(f"Completed processing {key} at {datetime.now()}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('File processing completed successfully')
    }
EOF
  filename = "${path.module}/lambda_function.py"
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_source.filename
  output_path = "${path.module}/lambda_function.zip"
  depends_on  = [local_file.lambda_source]
}

# Lambda function for immediate file processing
resource "aws_lambda_function" "file_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs,
  ]

  tags = merge(local.common_tags, {
    Name        = local.lambda_function_name
    Purpose     = "Immediate file processing"
    Component   = "Compute"
  })
}

# Lambda permission for S3 to invoke the function
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.file_processing.arn
}

# S3 Event Notifications Configuration
resource "aws_s3_bucket_notification" "file_processing_events" {
  count  = var.enable_s3_event_notifications ? 1 : 0
  bucket = aws_s3_bucket.file_processing.id

  # SNS Topic configuration for uploads/ prefix
  topic {
    topic_arn = aws_sns_topic.file_notifications.arn
    events    = ["s3:ObjectCreated:*"]
    
    filter_prefix = "uploads/"
  }

  # SQS Queue configuration for batch/ prefix
  queue {
    queue_arn = aws_sqs_queue.batch_processing.arn
    events    = ["s3:ObjectCreated:*"]
    
    filter_prefix = "batch/"
  }

  # Lambda function configuration for immediate/ prefix
  lambda_function {
    lambda_function_arn = aws_lambda_function.file_processor.arn
    events              = ["s3:ObjectCreated:*"]
    
    filter_prefix = "immediate/"
  }

  depends_on = [
    aws_sns_topic_policy.file_notifications,
    aws_sqs_queue_policy.batch_processing,
    aws_lambda_permission.s3_invoke,
  ]
}

# CloudWatch Alarms for monitoring

# Alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.lambda_function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [aws_sns_topic.file_notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.file_processor.function_name
  }

  tags = local.common_tags
}

# Alarm for SQS queue depth
resource "aws_cloudwatch_metric_alarm" "sqs_queue_depth" {
  alarm_name          = "${local.sqs_queue_name}-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateNumberOfVisibleMessages"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "100"
  alarm_description   = "This metric monitors SQS queue depth"
  alarm_actions       = [aws_sns_topic.file_notifications.arn]

  dimensions = {
    QueueName = aws_sqs_queue.batch_processing.name
  }

  tags = local.common_tags
}