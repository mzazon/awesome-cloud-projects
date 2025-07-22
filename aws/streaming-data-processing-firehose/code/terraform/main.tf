# Main Terraform configuration for Real-Time Data Processing with Kinesis Data Firehose
# This configuration creates a complete streaming data pipeline with:
# - Kinesis Data Firehose delivery streams
# - Lambda transformation functions
# - S3 data lake storage
# - OpenSearch domain for real-time search
# - IAM roles and policies
# - CloudWatch monitoring and alarms

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
  resource_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# S3 bucket for data storage with versioning and lifecycle policies
resource "aws_s3_bucket" "data_lake" {
  bucket = "${local.resource_prefix}-data-lake"
  
  tags = local.tags
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "data_lake_versioning" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake_encryption" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "data_lake_lifecycle" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "cost_optimization"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 2555  # 7 years retention
    }
  }
}

# Block public access to S3 bucket
resource "aws_s3_bucket_public_access_block" "data_lake_pab" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create directory structure in S3 bucket
resource "aws_s3_object" "raw_data_prefix" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "raw-data/"
  source = "/dev/null"
  
  tags = local.tags
}

resource "aws_s3_object" "transformed_data_prefix" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "transformed-data/"
  source = "/dev/null"
  
  tags = local.tags
}

resource "aws_s3_object" "error_data_prefix" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "error-data/"
  source = "/dev/null"
  
  tags = local.tags
}

# IAM role for Kinesis Data Firehose
resource "aws_iam_role" "firehose_role" {
  name = "${local.resource_prefix}-firehose-role"
  
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
  
  tags = local.tags
}

# IAM policy for Firehose to access S3, Lambda, and OpenSearch
resource "aws_iam_role_policy" "firehose_policy" {
  name = "${local.resource_prefix}-firehose-policy"
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
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "lambda:GetFunctionConfiguration"
        ]
        Resource = aws_lambda_function.data_transform.arn
      },
      {
        Effect = "Allow"
        Action = [
          "es:DescribeElasticsearchDomain",
          "es:DescribeElasticsearchDomains",
          "es:DescribeElasticsearchDomainConfig",
          "es:ESHttpPost",
          "es:ESHttpPut"
        ]
        Resource = "${aws_opensearch_domain.search_domain.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# Lambda execution role
resource "aws_iam_role" "lambda_role" {
  name = "${local.resource_prefix}-lambda-role"
  
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
  
  tags = local.tags
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function for data transformation
resource "aws_lambda_function" "data_transform" {
  filename         = "transform_function.zip"
  function_name    = "${local.resource_prefix}-transform"
  role            = aws_iam_role.lambda_role.arn
  handler         = "transform_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 256
  
  depends_on = [data.archive_file.transform_function_zip]
  
  tags = local.tags
}

# Create Lambda function package
data "archive_file" "transform_function_zip" {
  type        = "zip"
  output_path = "transform_function.zip"
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
            
            # Add timestamp and processing metadata
            data['processed_timestamp'] = datetime.utcnow().isoformat()
            data['processing_status'] = 'SUCCESS'
            
            # Enrich data with additional fields
            if 'user_id' in data:
                data['user_category'] = 'registered' if data['user_id'] else 'guest'
            
            if 'amount' in data:
                data['amount_category'] = 'high' if float(data['amount']) > 100 else 'low'
            
            # Convert back to JSON
            transformed_data = json.dumps(data) + '\n'
            
            output_record = {
                'recordId': record['recordId'],
                'result': 'Ok',
                'data': base64.b64encode(transformed_data.encode('utf-8')).decode('utf-8')
            }
            
        except Exception as e:
            # Handle transformation errors
            error_data = {
                'recordId': record['recordId'],
                'error': str(e),
                'original_data': uncompressed_payload,
                'timestamp': datetime.utcnow().isoformat()
            }
            
            output_record = {
                'recordId': record['recordId'],
                'result': 'ProcessingFailed',
                'data': base64.b64encode(json.dumps(error_data).encode('utf-8')).decode('utf-8')
            }
        
        output.append(output_record)
    
    return {'records': output}
EOF
    filename = "transform_function.py"
  }
}

# OpenSearch domain for real-time search and analytics
resource "aws_opensearch_domain" "search_domain" {
  domain_name           = "${local.resource_prefix}-search"
  engine_version        = "OpenSearch_1.3"
  
  cluster_config {
    instance_type  = var.opensearch_instance_type
    instance_count = var.opensearch_instance_count
  }
  
  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.opensearch_volume_size
  }
  
  encrypt_at_rest {
    enabled = true
  }
  
  node_to_node_encryption {
    enabled = true
  }
  
  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }
  
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${local.resource_prefix}-search/*"
      }
    ]
  })
  
  tags = local.tags
}

# CloudWatch Log Group for S3 delivery stream
resource "aws_cloudwatch_log_group" "s3_delivery_log" {
  name              = "/aws/kinesisfirehose/${local.resource_prefix}-s3-stream"
  retention_in_days = 7
  
  tags = local.tags
}

resource "aws_cloudwatch_log_stream" "s3_delivery_log_stream" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.s3_delivery_log.name
}

# CloudWatch Log Group for OpenSearch delivery stream
resource "aws_cloudwatch_log_group" "opensearch_delivery_log" {
  name              = "/aws/kinesisfirehose/${local.resource_prefix}-opensearch-stream"
  retention_in_days = 7
  
  tags = local.tags
}

resource "aws_cloudwatch_log_stream" "opensearch_delivery_log_stream" {
  name           = "OpenSearchDelivery"
  log_group_name = aws_cloudwatch_log_group.opensearch_delivery_log.name
}

# Kinesis Data Firehose delivery stream for S3
resource "aws_kinesis_firehose_delivery_stream" "s3_stream" {
  name        = "${local.resource_prefix}-s3-stream"
  destination = "extended_s3"
  
  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.data_lake.arn
    prefix     = "transformed-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "error-data/"
    
    buffering_size     = var.s3_buffer_size
    buffering_interval = var.s3_buffer_interval
    compression_format = "GZIP"
    
    # Data format conversion to Parquet
    data_format_conversion_configuration {
      enabled = true
      output_format_configuration {
        serializer {
          parquet_ser_de {}
        }
      }
    }
    
    # Lambda data transformation
    processing_configuration {
      enabled = true
      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = aws_lambda_function.data_transform.arn
        }
        parameters {
          parameter_name  = "BufferSizeInMBs"
          parameter_value = "3"
        }
        parameters {
          parameter_name  = "BufferIntervalInSeconds"
          parameter_value = "60"
        }
      }
    }
    
    # CloudWatch logging
    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.s3_delivery_log.name
      log_stream_name = aws_cloudwatch_log_stream.s3_delivery_log_stream.name
    }
  }
  
  tags = local.tags
  
  depends_on = [
    aws_iam_role_policy.firehose_policy,
    aws_opensearch_domain.search_domain
  ]
}

# Kinesis Data Firehose delivery stream for OpenSearch
resource "aws_kinesis_firehose_delivery_stream" "opensearch_stream" {
  name        = "${local.resource_prefix}-opensearch-stream"
  destination = "opensearch"
  
  opensearch_configuration {
    domain_arn = aws_opensearch_domain.search_domain.arn
    role_arn   = aws_iam_role.firehose_role.arn
    index_name = "realtime-events"
    type_name  = "_doc"
    
    index_rotation_period = "OneDay"
    
    buffering_size     = var.opensearch_buffer_size
    buffering_interval = var.opensearch_buffer_interval
    
    retry_duration = 3600
    
    # S3 backup configuration
    s3_backup_mode = "AllDocuments"
    s3_configuration {
      role_arn           = aws_iam_role.firehose_role.arn
      bucket_arn         = aws_s3_bucket.data_lake.arn
      prefix             = "opensearch-backup/"
      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"
    }
    
    # Lambda data transformation
    processing_configuration {
      enabled = true
      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = aws_lambda_function.data_transform.arn
        }
      }
    }
    
    # CloudWatch logging
    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.opensearch_delivery_log.name
      log_stream_name = aws_cloudwatch_log_stream.opensearch_delivery_log_stream.name
    }
  }
  
  tags = local.tags
  
  depends_on = [
    aws_iam_role_policy.firehose_policy,
    aws_opensearch_domain.search_domain
  ]
}

# SQS Dead Letter Queue for error handling
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.resource_prefix}-dlq"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 1209600  # 14 days
  
  tags = local.tags
}

# Lambda function for error handling
resource "aws_lambda_function" "error_handler" {
  filename         = "error_handler.zip"
  function_name    = "${local.resource_prefix}-error-handler"
  role            = aws_iam_role.lambda_role.arn
  handler         = "error_handler.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 128
  
  environment {
    variables = {
      DLQ_URL = aws_sqs_queue.dlq.url
    }
  }
  
  depends_on = [data.archive_file.error_handler_zip]
  
  tags = local.tags
}

# Create error handler Lambda package
data "archive_file" "error_handler_zip" {
  type        = "zip"
  output_path = "error_handler.zip"
  source {
    content = <<EOF
import json
import boto3
import os

def lambda_handler(event, context):
    sqs = boto3.client('sqs')
    
    for record in event['Records']:
        if record['eventName'] == 'ERROR':
            # Send failed record to DLQ
            sqs.send_message(
                QueueUrl=os.environ['DLQ_URL'],
                MessageBody=json.dumps(record)
            )
    
    return {'statusCode': 200}
EOF
    filename = "error_handler.py"
  }
}

# CloudWatch alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "s3_delivery_errors" {
  alarm_name          = "${local.resource_prefix}-s3-delivery-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DeliveryToS3.Records"
  namespace           = "AWS/KinesisFirehose"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Firehose S3 delivery errors"
  
  dimensions = {
    DeliveryStreamName = aws_kinesis_firehose_delivery_stream.s3_stream.name
  }
  
  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_delivery_errors" {
  alarm_name          = "${local.resource_prefix}-opensearch-delivery-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DeliveryToOpenSearch.Records"
  namespace           = "AWS/KinesisFirehose"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Firehose OpenSearch delivery errors"
  
  dimensions = {
    DeliveryStreamName = aws_kinesis_firehose_delivery_stream.opensearch_stream.name
  }
  
  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.resource_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Lambda transformation errors"
  
  dimensions = {
    FunctionName = aws_lambda_function.data_transform.function_name
  }
  
  tags = local.tags
}