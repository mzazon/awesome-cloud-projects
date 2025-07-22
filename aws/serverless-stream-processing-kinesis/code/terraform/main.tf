# Real-time Data Processing with Amazon Kinesis and Lambda
# This Terraform configuration deploys a complete serverless data processing pipeline

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  
  # S3 bucket name with random suffix for uniqueness
  s3_bucket_name = var.s3_bucket_suffix != "" ? 
    "${local.name_prefix}-processed-data-${var.s3_bucket_suffix}" : 
    "${local.name_prefix}-processed-data-${random_id.suffix.hex}"

  # Common tags for all resources
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "kinesis-lambda-processing"
    ManagedBy   = "Terraform"
  })
}

# Data source to get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ============================================================================
# S3 BUCKET FOR PROCESSED DATA STORAGE
# ============================================================================

# S3 bucket for storing processed data with versioning and lifecycle management
resource "aws_s3_bucket" "processed_data" {
  bucket = local.s3_bucket_name

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-processed-data-bucket"
    Description = "Storage for processed streaming data from Lambda"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Suspended"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "processed_data" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.processed_data.id

  rule {
    id     = "processed_data_lifecycle"
    status = "Enabled"

    # Transition to Infrequent Access after specified days
    transition {
      days          = var.s3_transition_ia_days
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after specified days
    transition {
      days          = var.s3_transition_glacier_days
      storage_class = "GLACIER"
    }

    # Delete incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ============================================================================
# KINESIS DATA STREAM
# ============================================================================

# Kinesis Data Stream for real-time data ingestion
resource "aws_kinesis_stream" "data_stream" {
  name                      = var.kinesis_stream_name
  shard_count              = var.kinesis_shard_count
  retention_period         = var.kinesis_retention_period
  shard_level_metrics      = var.enable_enhanced_monitoring ? ["IncomingRecords", "OutgoingRecords"] : []
  enforce_consumer_deletion = false

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-kinesis-stream"
    Description = "Kinesis stream for real-time data ingestion"
  })
}

# ============================================================================
# IAM ROLES AND POLICIES FOR LAMBDA
# ============================================================================

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution_role" {
  name               = "${local.name_prefix}-lambda-execution-role"
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
    Name        = "${local.name_prefix}-lambda-execution-role"
    Description = "IAM role for Kinesis data processing Lambda function"
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach AWS managed policy for Kinesis execution
resource "aws_iam_role_policy_attachment" "lambda_kinesis_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole"
}

# Custom IAM policy for S3 access
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "${local.name_prefix}-lambda-s3-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.processed_data.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.processed_data.arn
      }
    ]
  })
}

# Optional X-Ray tracing policy
resource "aws_iam_role_policy_attachment" "lambda_xray_policy" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ============================================================================
# LAMBDA FUNCTION
# ============================================================================

# Create the Lambda function source code
resource "local_file" "lambda_source" {
  filename = "${path.module}/lambda_function.py"
  content  = <<EOF
import json
import base64
import boto3
import os
from datetime import datetime
from typing import Dict, Any, List

# Initialize S3 client
s3_client = boto3.client('s3')
BUCKET_NAME = os.environ['S3_BUCKET_NAME']

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Kinesis records and store processed data in S3
    
    Args:
        event: Kinesis event containing records
        context: Lambda context object
        
    Returns:
        Dictionary with processing results
    """
    processed_records = []
    
    # Process each record in the Kinesis event
    for record in event['Records']:
        try:
            # Decode the Kinesis record data
            kinesis_data = record['kinesis']
            encoded_data = kinesis_data['data']
            decoded_data = base64.b64decode(encoded_data).decode('utf-8')
            
            # Parse the JSON data
            try:
                json_data = json.loads(decoded_data)
            except json.JSONDecodeError:
                # If not JSON, treat as plain text
                json_data = {"message": decoded_data}
                
            # Add processing metadata
            processed_record = {
                "original_data": json_data,
                "processing_timestamp": datetime.utcnow().isoformat(),
                "partition_key": kinesis_data['partitionKey'],
                "sequence_number": kinesis_data['sequenceNumber'],
                "event_id": record['eventID'],
                "event_source_arn": record['eventSourceARN'],
                "processed": True
            }
            
            processed_records.append(processed_record)
            
            print(f"Processed record with EventID: {record['eventID']}")
            
        except Exception as e:
            print(f"Error processing record {record.get('eventID', 'unknown')}: {str(e)}")
            # Continue processing other records
            continue
    
    # Store processed records in S3 if any were successfully processed
    if processed_records:
        try:
            # Create hierarchical S3 key based on timestamp
            now = datetime.utcnow()
            s3_key = f"processed-data/{now.strftime('%Y/%m/%d/%H')}/batch-{context.aws_request_id}.json"
            
            # Store the processed data in S3
            s3_client.put_object(
                Bucket=BUCKET_NAME,
                Key=s3_key,
                Body=json.dumps(processed_records, indent=2),
                ContentType='application/json',
                Metadata={
                    'processed_count': str(len(processed_records)),
                    'processing_timestamp': now.isoformat(),
                    'lambda_request_id': context.aws_request_id
                }
            )
            
            print(f"Successfully stored {len(processed_records)} processed records to S3: {s3_key}")
            
        except Exception as e:
            print(f"Error storing data to S3: {str(e)}")
            # Re-raise the exception to trigger retry logic
            raise
    
    # Return success response
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed_count': len(processed_records),
            'message': 'Successfully processed Kinesis records',
            'request_id': context.aws_request_id
        })
    }
EOF
}

# Archive the Lambda function source code
data "archive_file" "lambda_zip" {
  depends_on  = [local_file.lambda_source]
  type        = "zip"
  source_file = local_file.lambda_source.filename
  output_path = "${path.module}/lambda_function.zip"
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-lambda-logs"
    Description = "CloudWatch logs for Kinesis data processing Lambda"
  })
}

# Lambda function for processing Kinesis records
resource "aws_lambda_function" "data_processor" {
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_kinesis_execution,
    aws_iam_role_policy.lambda_s3_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.processed_data.bucket
    }
  }

  # Optional X-Ray tracing configuration
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-lambda-function"
    Description = "Lambda function for processing Kinesis stream data"
  })
}

# ============================================================================
# KINESIS-LAMBDA EVENT SOURCE MAPPING
# ============================================================================

# Event source mapping to connect Kinesis stream to Lambda function
resource "aws_lambda_event_source_mapping" "kinesis_lambda_mapping" {
  event_source_arn                   = aws_kinesis_stream.data_stream.arn
  function_name                      = aws_lambda_function.data_processor.arn
  starting_position                  = "LATEST"
  batch_size                         = var.lambda_batch_size
  maximum_batching_window_in_seconds = var.lambda_maximum_batching_window
  parallelization_factor            = 1

  # Error handling configuration
  maximum_retry_attempts = 3

  # Optional: Destination configuration for failed records
  # This can be configured to send failed records to an SQS queue or SNS topic
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_kinesis_execution
  ]
}

# ============================================================================
# CLOUDWATCH MONITORING (OPTIONAL)
# ============================================================================

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  count = var.enable_enhanced_monitoring ? 1 : 0

  alarm_name          = "${local.name_prefix}-lambda-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda error rate"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    FunctionName = aws_lambda_function.data_processor.function_name
  }

  tags = local.common_tags
}

# CloudWatch alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count = var.enable_enhanced_monitoring ? 1 : 0

  alarm_name          = "${local.name_prefix}-lambda-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.lambda_timeout * 1000 * 0.8}" # 80% of timeout
  alarm_description   = "This metric monitors lambda duration"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    FunctionName = aws_lambda_function.data_processor.function_name
  }

  tags = local.common_tags
}

# CloudWatch alarm for Kinesis stream incoming records
resource "aws_cloudwatch_metric_alarm" "kinesis_incoming_records" {
  count = var.enable_enhanced_monitoring ? 1 : 0

  alarm_name          = "${local.name_prefix}-kinesis-no-incoming-records"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors for lack of incoming records to Kinesis stream"
  treat_missing_data  = "breaching"

  dimensions = {
    StreamName = aws_kinesis_stream.data_stream.name
  }

  tags = local.common_tags
}