# Data source for current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for computed resources
locals {
  bucket_name         = "${var.bucket_name_prefix}-${random_string.suffix.result}"
  lambda_function_name = "${var.project_name}-processor-${random_string.suffix.result}"
  error_handler_name   = "${var.project_name}-error-handler-${random_string.suffix.result}"
  dlq_name            = "${var.project_name}-dlq-${random_string.suffix.result}"
  sns_topic_name      = "${var.project_name}-alerts-${random_string.suffix.result}"
  lambda_role_name    = "${var.project_name}-lambda-role-${random_string.suffix.result}"
}

# S3 bucket for data processing
resource "aws_s3_bucket" "data_processing_bucket" {
  bucket = local.bucket_name
  
  tags = merge(var.tags, {
    Name = local.bucket_name
    Purpose = "Data processing event source"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "data_processing_bucket_versioning" {
  bucket = aws_s3_bucket.data_processing_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "data_processing_bucket_encryption" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.data_processing_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "data_processing_bucket_pab" {
  bucket = aws_s3_bucket.data_processing_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SNS topic for error notifications
resource "aws_sns_topic" "data_processing_alerts" {
  name = local.sns_topic_name
  
  tags = merge(var.tags, {
    Name = local.sns_topic_name
    Purpose = "Data processing error notifications"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notifications" {
  topic_arn = aws_sns_topic.data_processing_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SQS Dead Letter Queue for failed processing
resource "aws_sqs_queue" "dead_letter_queue" {
  name                      = local.dlq_name
  visibility_timeout_seconds = var.dlq_visibility_timeout
  message_retention_seconds = var.dlq_message_retention
  
  # Enable server-side encryption if specified
  dynamic "kms_master_key_id" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_master_key_id = "alias/aws/sqs"
    }
  }
  
  tags = merge(var.tags, {
    Name = local.dlq_name
    Purpose = "Dead letter queue for failed data processing"
  })
}

# IAM role for Lambda functions
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
  
  tags = merge(var.tags, {
    Name = local.lambda_role_name
    Purpose = "Lambda execution role for data processing"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom IAM policy for Lambda functions
resource "aws_iam_role_policy" "lambda_data_processing_policy" {
  name = "DataProcessingPolicy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "${aws_s3_bucket.data_processing_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage"
        ]
        Resource = [
          aws_sqs_queue.dead_letter_queue.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.data_processing_alerts.arn
        ]
      }
    ]
  })
}

# CloudWatch log group for data processing Lambda
resource "aws_cloudwatch_log_group" "data_processor_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.cloudwatch_log_retention
  
  tags = merge(var.tags, {
    Name = "/aws/lambda/${local.lambda_function_name}"
    Purpose = "Data processing Lambda logs"
  })
}

# CloudWatch log group for error handler Lambda
resource "aws_cloudwatch_log_group" "error_handler_logs" {
  name              = "/aws/lambda/${local.error_handler_name}"
  retention_in_days = var.cloudwatch_log_retention
  
  tags = merge(var.tags, {
    Name = "/aws/lambda/${local.error_handler_name}"
    Purpose = "Error handler Lambda logs"
  })
}

# Archive Lambda function code for data processor
data "archive_file" "data_processor_zip" {
  type        = "zip"
  output_path = "${path.module}/data_processor.zip"
  
  source {
    content = <<EOF
import json
import boto3
import urllib.parse
from datetime import datetime

s3 = boto3.client('s3')
sqs = boto3.client('sqs')

def lambda_handler(event, context):
    try:
        # Process each S3 event record
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = urllib.parse.unquote_plus(record['s3']['object']['key'])
            
            print(f"Processing object: {key} from bucket: {bucket}")
            
            # Get object metadata
            response = s3.head_object(Bucket=bucket, Key=key)
            file_size = response['ContentLength']
            
            # Example processing logic based on file type
            if key.endswith('.csv'):
                process_csv_file(bucket, key, file_size)
            elif key.endswith('.json'):
                process_json_file(bucket, key, file_size)
            elif key.endswith('.txt'):
                process_text_file(bucket, key, file_size)
            else:
                print(f"Unsupported file type: {key}")
                continue
            
            # Create processing report
            create_processing_report(bucket, key, file_size)
            
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed S3 events')
        }
        
    except Exception as e:
        print(f"Error processing S3 event: {str(e)}")
        # Send to DLQ for retry logic
        send_to_dlq(event, str(e))
        raise e

def process_csv_file(bucket, key, file_size):
    """Process CSV files - add your business logic here"""
    print(f"Processing CSV file: {key} (Size: {file_size} bytes)")
    # Add your CSV processing logic here
    
def process_json_file(bucket, key, file_size):
    """Process JSON files - add your business logic here"""
    print(f"Processing JSON file: {key} (Size: {file_size} bytes)")
    # Add your JSON processing logic here
    
def process_text_file(bucket, key, file_size):
    """Process text files - add your business logic here"""
    print(f"Processing text file: {key} (Size: {file_size} bytes)")
    # Add your text processing logic here

def create_processing_report(bucket, key, file_size):
    """Create a processing report and store it in S3"""
    report_key = f"reports/{key}-report-{datetime.now().strftime('%Y%m%d%H%M%S')}.json"
    
    report = {
        'file_processed': key,
        'file_size': file_size,
        'processing_time': datetime.now().isoformat(),
        'status': 'completed'
    }
    
    s3.put_object(
        Bucket=bucket,
        Key=report_key,
        Body=json.dumps(report),
        ContentType='application/json'
    )
    
    print(f"Processing report created: {report_key}")

def send_to_dlq(event, error_message):
    """Send failed event to DLQ for retry"""
    import os
    dlq_url = os.environ.get('DLQ_URL')
    
    if dlq_url:
        message = {
            'original_event': event,
            'error_message': error_message,
            'timestamp': datetime.now().isoformat()
        }
        
        sqs.send_message(
            QueueUrl=dlq_url,
            MessageBody=json.dumps(message)
        )
EOF
    filename = "data_processor.py"
  }
}

# Data processing Lambda function
resource "aws_lambda_function" "data_processor" {
  filename         = data.archive_file.data_processor_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "data_processor.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.data_processing_timeout
  memory_size     = var.data_processing_memory
  
  source_code_hash = data.archive_file.data_processor_zip.output_base64sha256
  
  environment {
    variables = {
      DLQ_URL = aws_sqs_queue.dead_letter_queue.url
    }
  }
  
  dead_letter_config {
    target_arn = aws_sqs_queue.dead_letter_queue.arn
  }
  
  depends_on = [
    aws_cloudwatch_log_group.data_processor_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_data_processing_policy
  ]
  
  tags = merge(var.tags, {
    Name = local.lambda_function_name
    Purpose = "Data processing Lambda function"
  })
}

# Archive Lambda function code for error handler
data "archive_file" "error_handler_zip" {
  type        = "zip"
  output_path = "${path.module}/error_handler.zip"
  
  source {
    content = <<EOF
import json
import boto3
from datetime import datetime

sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        # Process SQS messages from DLQ
        for record in event['Records']:
            message_body = json.loads(record['body'])
            
            # Extract error details
            error_message = message_body.get('error_message', 'Unknown error')
            timestamp = message_body.get('timestamp', datetime.now().isoformat())
            
            # Send alert via SNS
            alert_message = f"""
Data Processing Error Alert

Error: {error_message}
Timestamp: {timestamp}

Please investigate the failed processing job.
"""
            
            import os
            sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
            
            if sns_topic_arn:
                sns.publish(
                    TopicArn=sns_topic_arn,
                    Message=alert_message,
                    Subject='Data Processing Error Alert'
                )
            
            print(f"Error alert sent for: {error_message}")
            
    except Exception as e:
        print(f"Error in error handler: {str(e)}")
        raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('Error handling completed')
    }
EOF
    filename = "error_handler.py"
  }
}

# Error handler Lambda function
resource "aws_lambda_function" "error_handler" {
  filename         = data.archive_file.error_handler_zip.output_path
  function_name    = local.error_handler_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "error_handler.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.error_handler_timeout
  memory_size     = var.error_handler_memory
  
  source_code_hash = data.archive_file.error_handler_zip.output_base64sha256
  
  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.data_processing_alerts.arn
    }
  }
  
  depends_on = [
    aws_cloudwatch_log_group.error_handler_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_data_processing_policy
  ]
  
  tags = merge(var.tags, {
    Name = local.error_handler_name
    Purpose = "Error handler Lambda function"
  })
}

# SQS event source mapping for error handler
resource "aws_lambda_event_source_mapping" "dlq_to_error_handler" {
  event_source_arn = aws_sqs_queue.dead_letter_queue.arn
  function_name    = aws_lambda_function.error_handler.arn
  batch_size       = 10
  maximum_batching_window_in_seconds = 5
}

# Lambda permission for S3 to invoke data processor
resource "aws_lambda_permission" "s3_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data_processing_bucket.arn
}

# S3 bucket notification configuration
resource "aws_s3_bucket_notification" "data_processing_notification" {
  bucket = aws_s3_bucket.data_processing_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.data_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.data_prefix
  }

  depends_on = [aws_lambda_permission.s3_invoke_lambda]
}

# CloudWatch alarms for monitoring (conditionally created)
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "${local.lambda_function_name}-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = [aws_sns_topic.data_processing_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.data_processor.function_name
  }
  
  tags = merge(var.tags, {
    Name = "${local.lambda_function_name}-errors"
    Purpose = "Lambda error monitoring"
  })
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "${local.dlq_name}-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfVisibleMessages"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "5"
  alarm_description   = "This metric monitors DLQ message count"
  alarm_actions       = [aws_sns_topic.data_processing_alerts.arn]

  dimensions = {
    QueueName = aws_sqs_queue.dead_letter_queue.name
  }
  
  tags = merge(var.tags, {
    Name = "${local.dlq_name}-messages"
    Purpose = "DLQ message monitoring"
  })
}