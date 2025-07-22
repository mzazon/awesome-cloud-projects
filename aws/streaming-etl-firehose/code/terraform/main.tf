# Main Terraform configuration for Kinesis Data Firehose Streaming ETL

# Get current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Unique suffix for resources that need global uniqueness
  unique_suffix = random_id.suffix.hex
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# S3 bucket for storing processed data
resource "aws_s3_bucket" "data_bucket" {
  bucket = "${local.name_prefix}-data-${local.unique_suffix}"
  
  tags = merge(local.common_tags, {
    Purpose = "Firehose data storage"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "data_bucket_versioning" {
  bucket = aws_s3_bucket.data_bucket.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_bucket_encryption" {
  bucket = aws_s3_bucket.data_bucket.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "data_bucket_pab" {
  bucket = aws_s3_bucket.data_bucket.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "data_bucket_lifecycle" {
  count = var.s3_lifecycle_enabled ? 1 : 0
  
  bucket = aws_s3_bucket.data_bucket.id
  
  rule {
    id     = "transition_to_ia"
    status = "Enabled"
    
    transition {
      days          = var.s3_transition_days
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    
    expiration {
      days = 365
    }
  }
  
  rule {
    id     = "cleanup_incomplete_uploads"
    status = "Enabled"
    
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# IAM role for Kinesis Data Firehose
resource "aws_iam_role" "firehose_role" {
  name = "${local.name_prefix}-firehose-role-${local.unique_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM policy for Firehose S3 access
resource "aws_iam_role_policy" "firehose_s3_policy" {
  name = "${local.name_prefix}-firehose-s3-policy"
  role = aws_iam_role.firehose_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.data_bucket.arn,
          "${aws_s3_bucket.data_bucket.arn}/*"
        ]
      }
    ]
  })
}

# IAM policy for Firehose Lambda invocation
resource "aws_iam_role_policy" "firehose_lambda_policy" {
  name = "${local.name_prefix}-firehose-lambda-policy"
  role = aws_iam_role.firehose_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.transform_function.arn
      }
    ]
  })
}

# Attach CloudWatch logs policy to Firehose role
resource "aws_iam_role_policy_attachment" "firehose_cloudwatch_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  role       = aws_iam_role.firehose_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSKinesisFirehoseServiceRolePolicy"
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role-${local.unique_suffix}"
  
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

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name              = "/aws/lambda/${local.name_prefix}-transform-${local.unique_suffix}"
  retention_in_days = 14
  
  tags = local.common_tags
}

# Create Lambda function code as a zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = <<EOF
import json
import base64
import boto3
from datetime import datetime

def lambda_handler(event, context):
    output = []
    
    for record in event['records']:
        # Decode the data
        compressed_payload = base64.b64decode(record['data'])
        uncompressed_payload = compressed_payload.decode('utf-8')
        
        try:
            # Parse JSON data
            data = json.loads(uncompressed_payload)
            
            # Transform the data - add timestamp and enrich
            transformed_data = {
                'timestamp': datetime.utcnow().isoformat(),
                'event_type': data.get('event_type', 'unknown'),
                'user_id': data.get('user_id', 'anonymous'),
                'session_id': data.get('session_id', ''),
                'page_url': data.get('page_url', ''),
                'referrer': data.get('referrer', ''),
                'user_agent': data.get('user_agent', ''),
                'ip_address': data.get('ip_address', ''),
                'processed_by': 'lambda-firehose-transform'
            }
            
            # Convert back to JSON and encode
            output_record = {
                'recordId': record['recordId'],
                'result': 'Ok',
                'data': base64.b64encode(
                    json.dumps(transformed_data).encode('utf-8')
                ).decode('utf-8')
            }
            
        except Exception as e:
            print(f"Error processing record: {e}")
            # Mark as processing failed
            output_record = {
                'recordId': record['recordId'],
                'result': 'ProcessingFailed'
            }
        
        output.append(output_record)
    
    return {'records': output}
EOF
    filename = "lambda_function.py"
  }
}

# Lambda function for data transformation
resource "aws_lambda_function" "transform_function" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-transform-${local.unique_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs,
  ]
  
  tags = merge(local.common_tags, {
    Purpose = "Firehose data transformation"
  })
}

# Kinesis Data Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "main" {
  name        = "${local.name_prefix}-stream-${local.unique_suffix}"
  destination = "extended_s3"
  
  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose_role.arn
    bucket_arn         = aws_s3_bucket.data_bucket.arn
    prefix             = "processed-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "error-data/"
    
    # Buffering configuration
    buffering_size     = var.firehose_buffer_size
    buffering_interval = var.firehose_buffer_interval
    
    # Compression
    compression_format = "GZIP"
    
    # Data transformation configuration
    processing_configuration {
      enabled = true
      
      processors {
        type = "Lambda"
        
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = aws_lambda_function.transform_function.arn
        }
        
        parameters {
          parameter_name  = "BufferSizeInMBs"
          parameter_value = "1"
        }
        
        parameters {
          parameter_name  = "BufferIntervalInSeconds"
          parameter_value = "60"
        }
      }
    }
    
    # Data format conversion to Parquet
    data_format_conversion_configuration {
      enabled = true
      
      output_format_configuration {
        serializer {
          parquet_ser_de {}
        }
      }
      
      schema_configuration {
        database_name = "default"
        table_name    = "streaming_etl_data"
        role_arn      = aws_iam_role.firehose_role.arn
      }
    }
    
    # CloudWatch logging configuration
    dynamic "cloudwatch_logging_options" {
      for_each = var.enable_cloudwatch_logs ? [1] : []
      
      content {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.firehose_logs[0].name
        log_stream_name = "S3Delivery"
      }
    }
  }
  
  tags = local.common_tags
  
  depends_on = [
    aws_iam_role_policy.firehose_s3_policy,
    aws_iam_role_policy.firehose_lambda_policy,
  ]
}

# CloudWatch log group for Firehose
resource "aws_cloudwatch_log_group" "firehose_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name              = "/aws/kinesisfirehose/${local.name_prefix}-stream-${local.unique_suffix}"
  retention_in_days = 14
  
  tags = local.common_tags
}

# CloudWatch alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "firehose_delivery_errors" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-firehose-delivery-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DeliveryToS3.Records"
  namespace           = "AWS/KinesisFirehose"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors Kinesis Firehose delivery errors"
  alarm_actions       = []
  
  dimensions = {
    DeliveryStreamName = aws_kinesis_firehose_delivery_stream.main.name
  }
  
  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = []
  
  dimensions = {
    FunctionName = aws_lambda_function.transform_function.function_name
  }
  
  tags = local.common_tags
}