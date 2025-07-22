# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "bucket_suffix" {
  byte_length = 3
  keepers = {
    bucket_prefix = var.bucket_prefix
  }
}

# S3 Bucket for multipart upload demonstrations
resource "aws_s3_bucket" "multipart_demo" {
  bucket = "${var.bucket_prefix}-${random_id.bucket_suffix.hex}"

  tags = merge(
    {
      Name        = "${var.bucket_prefix}-${random_id.bucket_suffix.hex}"
      Purpose     = "Multipart upload demonstration and testing"
      Recipe      = "multi-part-upload-strategies-large-files-s3"
    },
    var.additional_tags
  )
}

# S3 Bucket Public Access Block - Security best practice
resource "aws_s3_bucket_public_access_block" "multipart_demo" {
  bucket = aws_s3_bucket.multipart_demo.id

  block_public_acls       = var.bucket_public_access_block.block_public_acls
  block_public_policy     = var.bucket_public_access_block.block_public_policy
  ignore_public_acls      = var.bucket_public_access_block.ignore_public_acls
  restrict_public_buckets = var.bucket_public_access_block.restrict_public_buckets

  depends_on = [aws_s3_bucket.multipart_demo]
}

# S3 Bucket Versioning Configuration
resource "aws_s3_bucket_versioning" "multipart_demo" {
  bucket = aws_s3_bucket.multipart_demo.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }

  depends_on = [aws_s3_bucket.multipart_demo]
}

# S3 Bucket Server-Side Encryption Configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "multipart_demo" {
  count  = var.enable_server_side_encryption ? 1 : 0
  bucket = aws_s3_bucket.multipart_demo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }

  depends_on = [aws_s3_bucket.multipart_demo]
}

# S3 Bucket Lifecycle Configuration - Critical for multipart upload cleanup
resource "aws_s3_bucket_lifecycle_configuration" "multipart_demo" {
  bucket = aws_s3_bucket.multipart_demo.id

  # Rule for cleaning up incomplete multipart uploads
  rule {
    id     = "cleanup-incomplete-multipart-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = var.lifecycle_incomplete_days
    }

    filter {
      prefix = ""
    }
  }

  # Rule for managing object versions (if versioning is enabled)
  dynamic "rule" {
    for_each = var.enable_versioning ? [1] : []
    content {
      id     = "manage-object-versions"
      status = "Enabled"

      filter {
        prefix = ""
      }

      noncurrent_version_expiration {
        noncurrent_days = var.lifecycle_noncurrent_days
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.multipart_demo]
}

# S3 Transfer Acceleration Configuration (optional for improved performance)
resource "aws_s3_bucket_accelerate_configuration" "multipart_demo" {
  count  = var.enable_transfer_acceleration ? 1 : 0
  bucket = aws_s3_bucket.multipart_demo.id
  status = "Enabled"

  depends_on = [aws_s3_bucket.multipart_demo]
}

# S3 Bucket CORS Configuration for web-based uploads
resource "aws_s3_bucket_cors_configuration" "multipart_demo" {
  bucket = aws_s3_bucket.multipart_demo.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = var.cors_allowed_methods
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag", "x-amz-meta-*"]
    max_age_seconds = 3000
  }

  depends_on = [aws_s3_bucket.multipart_demo]
}

# S3 Bucket Metric Configuration for CloudWatch monitoring
resource "aws_s3_bucket_metric" "multipart_demo" {
  count  = var.enable_cloudwatch_metrics ? 1 : 0
  bucket = aws_s3_bucket.multipart_demo.id
  name   = "entire-bucket-metrics"

  depends_on = [aws_s3_bucket.multipart_demo]
}

# CloudWatch Dashboard for monitoring S3 multipart upload metrics
resource "aws_cloudwatch_dashboard" "multipart_monitoring" {
  count          = var.enable_cloudwatch_metrics ? 1 : 0
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
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.multipart_demo.id, "StorageType", "AllStorageTypes"],
            [".", "BucketSizeBytes", ".", ".", "StorageType", "StandardStorage"]
          ]
          period = 86400
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "S3 Bucket Object Count and Size"
          view   = "timeSeries"
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
            ["AWS/S3", "AllRequests", "BucketName", aws_s3_bucket.multipart_demo.id],
            [".", "GetRequests", ".", "."],
            [".", "PutRequests", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "S3 Request Metrics"
          view   = "timeSeries"
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket.multipart_demo]
}

# IAM Role for Lambda function (if demo Lambda is enabled)
resource "aws_iam_role" "lambda_multipart_role" {
  count = var.create_demo_lambda ? 1 : 0
  name  = "lambda-multipart-upload-role-${random_id.bucket_suffix.hex}"

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

  tags = merge(
    {
      Name    = "lambda-multipart-upload-role-${random_id.bucket_suffix.hex}"
      Purpose = "IAM role for multipart upload Lambda function"
    },
    var.additional_tags
  )
}

# IAM Policy for Lambda function to access S3 bucket
resource "aws_iam_role_policy" "lambda_s3_policy" {
  count = var.create_demo_lambda ? 1 : 0
  name  = "lambda-s3-multipart-policy"
  role  = aws_iam_role.lambda_multipart_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:CreateMultipartUpload",
          "s3:UploadPart",
          "s3:CompleteMultipartUpload",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploads",
          "s3:ListParts",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.multipart_demo.arn,
          "${aws_s3_bucket.multipart_demo.arn}/*"
        ]
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

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  count      = var.create_demo_lambda ? 1 : 0
  role       = aws_iam_role.lambda_multipart_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Demo Lambda function for multipart upload operations (optional)
resource "aws_lambda_function" "multipart_demo" {
  count            = var.create_demo_lambda ? 1 : 0
  filename         = data.archive_file.lambda_zip[0].output_path
  function_name    = "multipart-upload-demo-${random_id.bucket_suffix.hex}"
  role            = aws_iam_role.lambda_multipart_role[0].arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256
  runtime         = "python3.11"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.multipart_demo.id
      AWS_REGION  = data.aws_region.current.name
    }
  }

  tags = merge(
    {
      Name    = "multipart-upload-demo-${random_id.bucket_suffix.hex}"
      Purpose = "Demo Lambda function for multipart upload operations"
    },
    var.additional_tags
  )

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_multipart_demo
  ]
}

# Lambda function source code (if demo Lambda is enabled)
data "archive_file" "lambda_zip" {
  count       = var.create_demo_lambda ? 1 : 0
  type        = "zip"
  output_path = "/tmp/lambda_multipart_demo.zip"
  
  source {
    content = <<EOF
import json
import boto3
import os
from botocore.exceptions import ClientError

def handler(event, context):
    """
    Demo Lambda function for S3 multipart upload operations.
    Supports initiating, listing, and aborting multipart uploads.
    """
    
    s3_client = boto3.client('s3')
    bucket_name = os.environ['BUCKET_NAME']
    
    try:
        operation = event.get('operation', 'list')
        
        if operation == 'initiate':
            # Initiate multipart upload
            key = event.get('key', 'demo-file.bin')
            response = s3_client.create_multipart_upload(
                Bucket=bucket_name,
                Key=key,
                Metadata={
                    'upload-strategy': 'multipart',
                    'created-by': 'lambda-demo'
                }
            )
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Multipart upload initiated',
                    'upload_id': response['UploadId'],
                    'key': key,
                    'bucket': bucket_name
                })
            }
            
        elif operation == 'list':
            # List incomplete multipart uploads
            response = s3_client.list_multipart_uploads(Bucket=bucket_name)
            uploads = response.get('Uploads', [])
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Found {len(uploads)} incomplete multipart uploads',
                    'uploads': uploads
                })
            }
            
        elif operation == 'abort':
            # Abort multipart upload
            key = event.get('key')
            upload_id = event.get('upload_id')
            
            if not key or not upload_id:
                raise ValueError('Key and upload_id required for abort operation')
                
            s3_client.abort_multipart_upload(
                Bucket=bucket_name,
                Key=key,
                UploadId=upload_id
            )
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Multipart upload aborted successfully',
                    'key': key,
                    'upload_id': upload_id
                })
            }
            
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': f'Unknown operation: {operation}',
                    'supported_operations': ['initiate', 'list', 'abort']
                })
            }
            
    except ClientError as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'AWS error: {e.response["Error"]["Message"]}'
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Unexpected error: {str(e)}'
            })
        }
EOF
    filename = "index.py"
  }
}

# CloudWatch Log Group for Lambda function (if demo Lambda is enabled)
resource "aws_cloudwatch_log_group" "lambda_multipart_demo" {
  count             = var.create_demo_lambda ? 1 : 0
  name              = "/aws/lambda/multipart-upload-demo-${random_id.bucket_suffix.hex}"
  retention_in_days = 14

  tags = merge(
    {
      Name    = "/aws/lambda/multipart-upload-demo-${random_id.bucket_suffix.hex}"
      Purpose = "Log group for multipart upload demo Lambda function"
    },
    var.additional_tags
  )
}

# Local file to store AWS CLI configuration commands
resource "local_file" "aws_cli_config" {
  content = <<-EOT
#!/bin/bash
# AWS CLI Configuration for Multipart Upload Optimization
# Run these commands to configure optimal multipart upload settings

echo "Setting up AWS CLI for optimal multipart upload performance..."

# Configure multipart upload settings
aws configure set default.s3.multipart_threshold 100MB
aws configure set default.s3.multipart_chunksize 100MB
aws configure set default.s3.max_concurrent_requests 10
aws configure set default.s3.max_bandwidth 1GB/s

# Verify configuration
echo "Current S3 configuration:"
aws configure list | grep s3

echo ""
echo "S3 Bucket: ${aws_s3_bucket.multipart_demo.id}"
echo "Bucket Region: ${data.aws_region.current.name}"
echo ""
echo "Example multipart upload commands:"
echo ""
echo "# Upload a large file using optimized settings"
echo "aws s3 cp large-file.bin s3://${aws_s3_bucket.multipart_demo.id}/"
echo ""
echo "# Monitor upload progress"
echo "aws s3api list-multipart-uploads --bucket ${aws_s3_bucket.multipart_demo.id}"
echo ""
echo "# List objects in bucket"
echo "aws s3 ls s3://${aws_s3_bucket.multipart_demo.id}/"
echo ""
echo "Configuration complete!"
EOT

  filename        = "aws-cli-config.sh"
  file_permission = "0755"
}