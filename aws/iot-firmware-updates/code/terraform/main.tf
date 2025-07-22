# Main Terraform configuration for IoT firmware updates infrastructure

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for computed names
locals {
  # Resource names with random suffix
  firmware_bucket_name = var.firmware_bucket_name != "" ? var.firmware_bucket_name : "${var.project_name}-firmware-${random_string.suffix.result}"
  thing_name          = var.thing_name != "" ? var.thing_name : "${var.project_name}-device-${random_string.suffix.result}"
  thing_group_name    = var.thing_group_name != "" ? var.thing_group_name : "${var.project_name}-group-${random_string.suffix.result}"
  
  # IAM role names
  iot_jobs_role_name = "${var.project_name}-iot-jobs-role-${random_string.suffix.result}"
  lambda_role_name   = "${var.project_name}-lambda-role-${random_string.suffix.result}"
  
  # Function and profile names
  lambda_function_name    = "${var.project_name}-firmware-manager"
  signing_profile_name    = "${var.project_name}-signing-${random_string.suffix.result}"
  cloudwatch_dashboard_name = "${var.project_name}-firmware-updates"
  
  # Common tags
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# ============================================================================
# S3 BUCKET FOR FIRMWARE STORAGE
# ============================================================================

# S3 bucket for firmware storage and distribution
resource "aws_s3_bucket" "firmware_bucket" {
  bucket = local.firmware_bucket_name

  tags = merge(local.common_tags, {
    Name = local.firmware_bucket_name
    Purpose = "IoT firmware storage and distribution"
  })
}

# Enable versioning on the firmware bucket
resource "aws_s3_bucket_versioning" "firmware_bucket_versioning" {
  bucket = aws_s3_bucket.firmware_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# Configure server-side encryption for the firmware bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "firmware_bucket_encryption" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.firmware_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.s3_encryption_algorithm
      kms_master_key_id = var.s3_encryption_algorithm == "aws:kms" ? var.s3_kms_key_id : null
    }
    bucket_key_enabled = var.s3_encryption_algorithm == "aws:kms"
  }
}

# Block public access to the firmware bucket
resource "aws_s3_bucket_public_access_block" "firmware_bucket_pab" {
  bucket = aws_s3_bucket.firmware_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# IAM role for IoT Jobs service
resource "aws_iam_role" "iot_jobs_role" {
  name = local.iot_jobs_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = local.iot_jobs_role_name
    Purpose = "IoT Jobs service role for firmware distribution"
  })
}

# IAM policy for IoT Jobs to access S3 firmware bucket
resource "aws_iam_role_policy" "iot_jobs_s3_policy" {
  name = "IoTJobsS3Access"
  role = aws_iam_role.iot_jobs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.firmware_bucket.arn}/*"
      }
    ]
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = local.lambda_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = local.lambda_role_name
    Purpose = "Lambda execution role for firmware update management"
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom IAM policy for Lambda function permissions
resource "aws_iam_role_policy" "lambda_firmware_update_policy" {
  name = "FirmwareUpdatePermissions"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:CreateJob",
          "iot:DescribeJob",
          "iot:ListJobs",
          "iot:UpdateJob",
          "iot:CancelJob",
          "iot:DeleteJob",
          "iot:ListJobExecutionsForJob",
          "iot:ListJobExecutionsForThing",
          "iot:DescribeJobExecution"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion"
        ]
        Resource = [
          aws_s3_bucket.firmware_bucket.arn,
          "${aws_s3_bucket.firmware_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "signer:StartSigningJob",
          "signer:DescribeSigningJob",
          "signer:ListSigningJobs"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# AWS SIGNER SIGNING PROFILE
# ============================================================================

# AWS Signer signing profile for firmware code signing
resource "aws_signer_signing_profile" "firmware_signing_profile" {
  platform_id = var.signing_platform_id
  name        = local.signing_profile_name

  signature_validity_period {
    value = var.signature_validity_days
    type  = "Days"
  }

  tags = merge(local.common_tags, {
    Name = local.signing_profile_name
    Purpose = "Code signing for IoT firmware"
  })
}

# ============================================================================
# IOT RESOURCES
# ============================================================================

# IoT Thing Group for organizing devices
resource "aws_iot_thing_group" "firmware_update_group" {
  name = local.thing_group_name

  thing_group_properties {
    thing_group_description = "Device group for firmware updates managed by Terraform"
    attribute_payload {
      attributes = {
        Environment = var.environment
        Purpose     = "FirmwareUpdates"
        CreatedBy   = "Terraform"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = local.thing_group_name
    Purpose = "IoT device grouping for firmware updates"
  })
}

# IoT Thing for testing (conditional creation)
resource "aws_iot_thing" "test_device" {
  count = var.create_sample_device ? 1 : 0
  name  = local.thing_name

  thing_type_name = aws_iot_thing_type.device_type[0].name

  attributes = {
    Environment = var.environment
    DeviceType  = "TestDevice"
    CreatedBy   = "Terraform"
  }

  tags = merge(local.common_tags, {
    Name = local.thing_name
    Purpose = "Test device for firmware updates"
  })
}

# IoT Thing Type for device classification
resource "aws_iot_thing_type" "device_type" {
  count = var.create_sample_device ? 1 : 0
  name  = "${var.project_name}-device-type"

  thing_type_properties {
    thing_type_description = "Device type for firmware update testing"
    searchable_attributes  = ["Environment", "DeviceType"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-device-type"
    Purpose = "Device type classification"
  })
}

# Add test device to thing group
resource "aws_iot_thing_group_membership" "test_device_membership" {
  count            = var.create_sample_device ? 1 : 0
  thing_name       = aws_iot_thing.test_device[0].name
  thing_group_name = aws_iot_thing_group.firmware_update_group.name
}

# ============================================================================
# LAMBDA FUNCTION
# ============================================================================

# Create the Lambda function code
resource "local_file" "lambda_function_code" {
  content = <<EOF
import json
import boto3
import uuid
from datetime import datetime, timedelta

def lambda_handler(event, context):
    iot_client = boto3.client('iot')
    s3_client = boto3.client('s3')
    signer_client = boto3.client('signer')
    
    action = event.get('action')
    
    if action == 'create_job':
        return create_firmware_job(event, iot_client, s3_client)
    elif action == 'check_job_status':
        return check_job_status(event, iot_client)
    elif action == 'cancel_job':
        return cancel_job(event, iot_client)
    else:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid action'})
        }

def create_firmware_job(event, iot_client, s3_client):
    try:
        firmware_version = event['firmware_version']
        thing_group = event['thing_group']
        s3_bucket = event['s3_bucket']
        s3_key = event['s3_key']
        
        # Create job document
        job_document = {
            "operation": "firmware_update",
            "firmware": {
                "version": firmware_version,
                "url": f"https://{s3_bucket}.s3.amazonaws.com/{s3_key}",
                "size": get_object_size(s3_client, s3_bucket, s3_key),
                "checksum": get_object_checksum(s3_client, s3_bucket, s3_key)
            },
            "steps": [
                "download_firmware",
                "verify_signature",
                "backup_current_firmware",
                "install_firmware",
                "verify_installation",
                "report_status"
            ]
        }
        
        # Create unique job ID
        job_id = f"firmware-update-{firmware_version}-{uuid.uuid4().hex[:8]}"
        
        # Get region and account for ARN construction
        region = boto3.Session().region_name
        account_id = boto3.client('sts').get_caller_identity()['Account']
        
        # Create the job
        response = iot_client.create_job(
            jobId=job_id,
            targets=[f"arn:aws:iot:{region}:{account_id}:thinggroup/{thing_group}"],
            document=json.dumps(job_document),
            description=f"Firmware update to version {firmware_version}",
            targetSelection='SNAPSHOT',
            jobExecutionsRolloutConfig={
                'maximumPerMinute': int(event.get('max_per_minute', 10)),
                'exponentialRate': {
                    'baseRatePerMinute': int(event.get('base_rate_per_minute', 5)),
                    'incrementFactor': float(event.get('increment_factor', 2.0)),
                    'rateIncreaseCriteria': {
                        'numberOfNotifiedThings': 10,
                        'numberOfSucceededThings': 5
                    }
                }
            },
            abortConfig={
                'criteriaList': [
                    {
                        'failureType': 'FAILED',
                        'action': 'CANCEL',
                        'thresholdPercentage': float(event.get('failure_threshold', 20.0)),
                        'minNumberOfExecutedThings': 5
                    }
                ]
            },
            timeoutConfig={
                'inProgressTimeoutInMinutes': int(event.get('timeout_minutes', 60))
            }
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'job_id': job_id,
                'job_arn': response['jobArn'],
                'message': 'Firmware update job created successfully'
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def check_job_status(event, iot_client):
    try:
        job_id = event['job_id']
        
        response = iot_client.describe_job(jobId=job_id)
        job_executions = iot_client.list_job_executions_for_job(jobId=job_id)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'job_id': job_id,
                'status': response['job']['status'],
                'process_details': response['job']['jobProcessDetails'],
                'executions': job_executions['executionSummaries']
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def cancel_job(event, iot_client):
    try:
        job_id = event['job_id']
        
        iot_client.cancel_job(
            jobId=job_id,
            reasonCode='USER_INITIATED',
            comment='Job cancelled by user'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'job_id': job_id,
                'message': 'Job cancelled successfully'
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_object_size(s3_client, bucket, key):
    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)
        return response['ContentLength']
    except:
        return 0

def get_object_checksum(s3_client, bucket, key):
    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)
        return response.get('ETag', '').replace('"', '')
    except:
        return ''
EOF
  filename = "${path.module}/firmware_update_manager.py"
}

# Create ZIP archive for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_function_code.filename
  output_path = "${path.module}/firmware_update_manager.zip"
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.lambda_function_name}"
    Purpose = "Lambda function logs for firmware update management"
  })
}

# Lambda function for firmware update management
resource "aws_lambda_function" "firmware_update_manager" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "firmware_update_manager.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      FIRMWARE_BUCKET     = aws_s3_bucket.firmware_bucket.bucket
      THING_GROUP_NAME    = aws_iot_thing_group.firmware_update_group.name
      SIGNING_PROFILE     = aws_signer_signing_profile.firmware_signing_profile.name
      AWS_REGION          = data.aws_region.current.name
      PROJECT_NAME        = var.project_name
      ENVIRONMENT         = var.environment
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_firmware_update_policy,
    aws_cloudwatch_log_group.lambda_logs,
  ]

  tags = merge(local.common_tags, {
    Name = local.lambda_function_name
    Purpose = "Firmware update job management"
  })
}

# ============================================================================
# CLOUDWATCH DASHBOARD
# ============================================================================

# CloudWatch Dashboard for monitoring IoT Jobs (conditional creation)
resource "aws_cloudwatch_dashboard" "iot_jobs_dashboard" {
  count          = var.create_cloudwatch_dashboard ? 1 : 0
  dashboard_name = local.cloudwatch_dashboard_name

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
            ["AWS/IoT", "JobsCompleted"],
            [".", "JobsFailed"],
            [".", "JobsInProgress"],
            [".", "JobsQueued"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "IoT Jobs Status Overview"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
            }
          }
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.firmware_update_manager.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Function Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '/aws/lambda/${aws_lambda_function.firmware_update_manager.function_name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region = data.aws_region.current.name
          title  = "Recent Lambda Function Logs"
          view   = "table"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = local.cloudwatch_dashboard_name
    Purpose = "IoT firmware update monitoring dashboard"
  })
}

# ============================================================================
# SAMPLE FIRMWARE FILE
# ============================================================================

# Create sample firmware file for testing
resource "local_file" "sample_firmware" {
  content = <<EOF
# Sample Firmware v1.0.0
# This is a simulated firmware binary for testing IoT firmware updates
# In production, this would be your actual firmware image

FIRMWARE_VERSION=1.0.0
FIRMWARE_BUILD=20241211
FIRMWARE_FEATURES=["ota_support", "security_patch", "bug_fixes"]

# Simulated binary data
BINARY_DATA_START
00000000: 7f45 4c46 0101 0100 0000 0000 0000 0000  .ELF............
00000010: 0200 0300 0100 0000 8080 0408 3400 0000  ............4...
00000020: 0000 0000 0000 0000 3400 2000 0100 0000  ........4. .....
00000030: 0100 0000 0000 0000 0000 0408 0000 0408  ................
00000040: 0000 0000 0000 0000 0000 0000 0000 0000  ................
BINARY_DATA_END

CHECKSUM=sha256:$(echo -n "sample_firmware_v1.0.0" | sha256sum | cut -d' ' -f1)
SIGNATURE_REQUIRED=true
PLATFORM_TARGET=${var.signing_platform_id}
EOF
  filename = "${path.module}/sample_firmware_v1.0.0.bin"
}

# Upload sample firmware to S3
resource "aws_s3_object" "sample_firmware" {
  bucket = aws_s3_bucket.firmware_bucket.bucket
  key    = "firmware/sample_firmware_v1.0.0.bin"
  source = local_file.sample_firmware.filename
  etag   = filemd5(local_file.sample_firmware.filename)

  tags = merge(local.common_tags, {
    Name = "sample_firmware_v1.0.0.bin"
    Purpose = "Sample firmware for testing"
    Version = "1.0.0"
  })
}

# Create firmware metadata file
resource "local_file" "firmware_metadata" {
  content = jsonencode({
    version     = "1.0.0"
    build       = "20241211"
    description = "Sample firmware with OTA support and security patches"
    features    = ["ota_support", "security_patch", "bug_fixes"]
    size        = length(local_file.sample_firmware.content)
    checksum    = filebase64sha256(local_file.sample_firmware.filename)
    upload_date = timestamp()
    platform    = var.signing_platform_id
  })
  filename = "${path.module}/firmware_metadata.json"
}

# Upload firmware metadata to S3
resource "aws_s3_object" "firmware_metadata" {
  bucket  = aws_s3_bucket.firmware_bucket.bucket
  key     = "firmware/sample_firmware_v1.0.0.json"
  content = local_file.firmware_metadata.content
  etag    = md5(local_file.firmware_metadata.content)

  tags = merge(local.common_tags, {
    Name = "sample_firmware_v1.0.0.json"
    Purpose = "Sample firmware metadata"
    Version = "1.0.0"
  })
}