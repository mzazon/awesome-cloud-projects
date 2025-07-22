# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # Generate bucket names if not provided
  document_bucket_name = var.document_bucket_name != "" ? var.document_bucket_name : "${var.project_name}-documents-${random_id.suffix.hex}"
  results_bucket_name  = var.results_bucket_name != "" ? var.results_bucket_name : "${var.project_name}-results-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# =============================================================================
# KMS Key for Encryption
# =============================================================================

resource "aws_kms_key" "document_processing" {
  count = var.enable_s3_encryption || var.enable_dynamodb_encryption || var.enable_sns_encryption ? 1 : 0
  
  description             = "KMS key for document processing pipeline encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-kms-key"
  })
}

resource "aws_kms_alias" "document_processing" {
  count = var.enable_s3_encryption || var.enable_dynamodb_encryption || var.enable_sns_encryption ? 1 : 0
  
  name          = "alias/${var.project_name}-document-processing"
  target_key_id = aws_kms_key.document_processing[0].key_id
}

# =============================================================================
# S3 Buckets
# =============================================================================

# Document storage bucket
resource "aws_s3_bucket" "documents" {
  bucket = local.document_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-documents"
    Type = "DocumentStorage"
  })
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = var.enable_bucket_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.enable_s3_encryption ? aws_kms_key.document_processing[0].arn : null
      sse_algorithm     = var.enable_s3_encryption ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.enable_s3_encryption
  }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Results storage bucket
resource "aws_s3_bucket" "results" {
  bucket = local.results_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-results"
    Type = "ResultsStorage"
  })
}

resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id
  versioning_configuration {
    status = var.enable_bucket_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.enable_s3_encryption ? aws_kms_key.document_processing[0].arn : null
      sse_algorithm     = var.enable_s3_encryption ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.enable_s3_encryption
  }
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle configuration for both buckets
resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  depends_on = [aws_s3_bucket_versioning.documents]
  bucket     = aws_s3_bucket.documents.id

  rule {
    id     = "lifecycle_rule"
    status = "Enabled"

    dynamic "transition" {
      for_each = var.enable_intelligent_tiering ? [] : [1]
      content {
        days          = var.transition_to_ia_days
        storage_class = "STANDARD_IA"
      }
    }

    dynamic "transition" {
      for_each = var.enable_intelligent_tiering ? [] : [1]
      content {
        days          = var.transition_to_glacier_days
        storage_class = "GLACIER"
      }
    }

    expiration {
      days = var.bucket_lifecycle_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  dynamic "rule" {
    for_each = var.enable_intelligent_tiering ? [1] : []
    content {
      id     = "intelligent_tiering"
      status = "Enabled"

      transition {
        days          = 0
        storage_class = "INTELLIGENT_TIERING"
      }

      expiration {
        days = var.bucket_lifecycle_days
      }
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "results" {
  depends_on = [aws_s3_bucket_versioning.results]
  bucket     = aws_s3_bucket.results.id

  rule {
    id     = "lifecycle_rule"
    status = "Enabled"

    dynamic "transition" {
      for_each = var.enable_intelligent_tiering ? [] : [1]
      content {
        days          = var.transition_to_ia_days
        storage_class = "STANDARD_IA"
      }
    }

    dynamic "transition" {
      for_each = var.enable_intelligent_tiering ? [] : [1]
      content {
        days          = var.transition_to_glacier_days
        storage_class = "GLACIER"
      }
    }

    expiration {
      days = var.bucket_lifecycle_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  dynamic "rule" {
    for_each = var.enable_intelligent_tiering ? [1] : []
    content {
      id     = "intelligent_tiering"
      status = "Enabled"

      transition {
        days          = 0
        storage_class = "INTELLIGENT_TIERING"
      }

      expiration {
        days = var.bucket_lifecycle_days
      }
    }
  }
}

# =============================================================================
# DynamoDB Table
# =============================================================================

resource "aws_dynamodb_table" "processing_jobs" {
  name     = "${var.project_name}-processing-jobs"
  hash_key = "JobId"

  billing_mode   = var.dynamodb_billing_mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "JobId"
    type = "S"
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Enable encryption at rest
  server_side_encryption {
    enabled     = var.enable_dynamodb_encryption
    kms_key_arn = var.enable_dynamodb_encryption ? aws_kms_key.document_processing[0].arn : null
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-processing-jobs"
  })
}

# =============================================================================
# SNS Topic for Notifications
# =============================================================================

resource "aws_sns_topic" "notifications" {
  name = "${var.project_name}-notifications"

  kms_master_key_id = var.enable_sns_encryption ? aws_kms_key.document_processing[0].id : null

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-notifications"
  })
}

# Optional email subscription
resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# =============================================================================
# CloudWatch Log Groups
# =============================================================================

resource "aws_cloudwatch_log_group" "lambda_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name              = "/aws/lambda/${var.project_name}-trigger"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-lambda-logs"
  })
}

resource "aws_cloudwatch_log_group" "step_functions_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name              = "/aws/stepfunctions/${var.project_name}-pipeline"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-step-functions-logs"
  })
}

# =============================================================================
# IAM Roles and Policies
# =============================================================================

# Step Functions execution role
resource "aws_iam_role" "step_functions_role" {
  name = "${var.project_name}-step-functions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-step-functions-role"
  })
}

# Step Functions IAM policy
resource "aws_iam_role_policy" "step_functions_policy" {
  name = "${var.project_name}-step-functions-policy"
  role = aws_iam_role.step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "textract:AnalyzeDocument",
          "textract:DetectDocumentText",
          "textract:GetDocumentAnalysis",
          "textract:GetDocumentTextDetection",
          "textract:StartDocumentAnalysis",
          "textract:StartDocumentTextDetection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.documents.arn}/*",
          "${aws_s3_bucket.results.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.processing_jobs.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.notifications.arn
      }
    ]
  })
}

# Lambda execution role
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

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
    Name = "${var.project_name}-lambda-role"
  })
}

# Lambda IAM policy
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
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
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.document_processing.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.documents.arn}/*"
      }
    ]
  })
}

# =============================================================================
# Lambda Function
# =============================================================================

# Create Lambda function code
resource "local_file" "lambda_code" {
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    state_machine_arn = aws_sfn_state_machine.document_processing.arn
  })
  filename = "${path.module}/lambda_function.py"
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_code.filename
  output_path = "${path.module}/lambda_function.zip"
  depends_on  = [local_file.lambda_code]
}

# Lambda function
resource "aws_lambda_function" "document_trigger" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "${var.project_name}-trigger"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.document_processing.arn
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-trigger"
  })
}

# Lambda permission for S3
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.document_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.documents.arn
}

# =============================================================================
# Step Functions State Machine
# =============================================================================

resource "aws_sfn_state_machine" "document_processing" {
  name     = "${var.project_name}-pipeline"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = templatefile("${path.module}/state_machine.json.tpl", {
    results_bucket_name   = aws_s3_bucket.results.bucket
    dynamodb_table_name   = aws_dynamodb_table.processing_jobs.name
    sns_topic_arn         = aws_sns_topic.notifications.arn
    max_retry_attempts    = var.max_retry_attempts
    retry_interval        = var.retry_interval_seconds
    retry_backoff_rate    = var.retry_backoff_rate
  })

  logging_configuration {
    log_destination        = var.enable_cloudwatch_logs ? "${aws_cloudwatch_log_group.step_functions_logs[0].arn}:*" : null
    include_execution_data = var.enable_cloudwatch_logs
    level                  = var.step_functions_log_level
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-pipeline"
  })
}

# =============================================================================
# S3 Bucket Notification
# =============================================================================

resource "aws_s3_bucket_notification" "document_upload" {
  bucket = aws_s3_bucket.documents.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.document_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    
    # Filter for supported file types
    filter_suffix = ".pdf"
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}

# =============================================================================
# Template Files
# =============================================================================

# Lambda function template
resource "local_file" "lambda_template" {
  content = <<-EOF
import json
import boto3
import uuid
import os
from urllib.parse import unquote_plus

stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    """
    Lambda function to trigger Step Functions workflow when documents are uploaded to S3.
    
    This function:
    1. Processes S3 event notifications
    2. Determines document processing requirements
    3. Generates unique job IDs
    4. Starts Step Functions execution
    """
    
    for record in event['Records']:
        try:
            # Extract S3 event details
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            # Skip processing for non-document files
            if not any(key.lower().endswith(ext) for ext in ['.pdf', '.png', '.jpg', '.jpeg', '.tiff', '.tif']):
                print(f"Skipping non-document file: {key}")
                continue
            
            # Determine if document requires advanced analysis
            # PDF and TIFF files typically contain forms/tables
            # Files with 'form' in the name likely need advanced processing
            requires_analysis = (
                key.lower().endswith(('.pdf', '.tiff', '.tif')) or 
                'form' in key.lower() or
                'table' in key.lower()
            )
            
            # Generate unique job ID for tracking
            job_id = str(uuid.uuid4())
            
            # Prepare input data for Step Functions
            input_data = {
                'bucket': bucket,
                'key': key,
                'jobId': job_id,
                'requiresAnalysis': requires_analysis,
                'timestamp': context.aws_request_id
            }
            
            # Start Step Functions execution
            response = stepfunctions.start_execution(
                stateMachineArn=os.environ['STATE_MACHINE_ARN'],
                name=f'doc-processing-{job_id}',
                input=json.dumps(input_data)
            )
            
            print(f"Started processing job {job_id} for document {key}")
            print(f"Step Functions execution ARN: {response['executionArn']}")
            
        except Exception as e:
            print(f"Error processing record: {str(e)}")
            print(f"Record: {json.dumps(record)}")
            # Don't raise exception to avoid Lambda retry for other records
    
    return {
        'statusCode': 200,
        'body': json.dumps('Document processing triggered successfully')
    }
EOF
  filename = "${path.module}/lambda_function.py.tpl"
}

# Step Functions state machine template
resource "local_file" "state_machine_template" {
  content = <<-EOF
{
  "Comment": "Document processing pipeline with Amazon Textract and intelligent routing",
  "StartAt": "ProcessDocument",
  "States": {
    "ProcessDocument": {
      "Type": "Choice",
      "Comment": "Route documents to appropriate Textract API based on requirements",
      "Choices": [
        {
          "Variable": "$.requiresAnalysis",
          "BooleanEquals": true,
          "Next": "AnalyzeDocument"
        }
      ],
      "Default": "DetectText"
    },
    "AnalyzeDocument": {
      "Type": "Task",
      "Comment": "Use Textract AnalyzeDocument for forms, tables, and complex documents",
      "Resource": "arn:aws:states:::aws-sdk:textract:analyzeDocument",
      "Parameters": {
        "Document": {
          "S3Object": {
            "Bucket.$": "$.bucket",
            "Name.$": "$.key"
          }
        },
        "FeatureTypes": ["TABLES", "FORMS", "SIGNATURES", "LAYOUT"]
      },
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed", "Textract.ThrottlingException"],
          "IntervalSeconds": ${retry_interval},
          "MaxAttempts": ${max_retry_attempts},
          "BackoffRate": ${retry_backoff_rate}
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ProcessingFailed",
          "ResultPath": "$.error"
        }
      ],
      "Next": "StoreResults"
    },
    "DetectText": {
      "Type": "Task",
      "Comment": "Use Textract DetectDocumentText for simple text extraction",
      "Resource": "arn:aws:states:::aws-sdk:textract:detectDocumentText",
      "Parameters": {
        "Document": {
          "S3Object": {
            "Bucket.$": "$.bucket",
            "Name.$": "$.key"
          }
        }
      },
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed", "Textract.ThrottlingException"],
          "IntervalSeconds": ${retry_interval},
          "MaxAttempts": ${max_retry_attempts},
          "BackoffRate": ${retry_backoff_rate}
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ProcessingFailed",
          "ResultPath": "$.error"
        }
      ],
      "Next": "StoreResults"
    },
    "StoreResults": {
      "Type": "Task",
      "Comment": "Store processing results in S3 for downstream consumption",
      "Resource": "arn:aws:states:::aws-sdk:s3:putObject",
      "Parameters": {
        "Bucket": "${results_bucket_name}",
        "Key.$": "States.Format('{}/results.json', $.jobId)",
        "Body.$": "$",
        "ContentType": "application/json"
      },
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Next": "UpdateJobStatus"
    },
    "UpdateJobStatus": {
      "Type": "Task",
      "Comment": "Update job status in DynamoDB for tracking and auditing",
      "Resource": "arn:aws:states:::aws-sdk:dynamodb:putItem",
      "Parameters": {
        "TableName": "${dynamodb_table_name}",
        "Item": {
          "JobId": {
            "S.$": "$.jobId"
          },
          "Status": {
            "S": "COMPLETED"
          },
          "ProcessedAt": {
            "S.$": "$$.State.EnteredTime"
          },
          "ResultsLocation": {
            "S.$": "States.Format('s3://${results_bucket_name}/{}/results.json', $.jobId)"
          },
          "DocumentLocation": {
            "S.$": "States.Format('s3://{}/{}', $.bucket, $.key)"
          },
          "ProcessingType": {
            "S.$": "States.Format('{}', $.requiresAnalysis)"
          }
        }
      },
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Next": "SendNotification"
    },
    "SendNotification": {
      "Type": "Task",
      "Comment": "Send success notification via SNS",
      "Resource": "arn:aws:states:::aws-sdk:sns:publish",
      "Parameters": {
        "TopicArn": "${sns_topic_arn}",
        "Message.$": "States.Format('Document processing completed successfully for job {}. Results available at: s3://${results_bucket_name}/{}/results.json', $.jobId, $.jobId)",
        "Subject": "Document Processing Complete"
      },
      "End": true
    },
    "ProcessingFailed": {
      "Type": "Task",
      "Comment": "Record processing failure in DynamoDB",
      "Resource": "arn:aws:states:::aws-sdk:dynamodb:putItem",
      "Parameters": {
        "TableName": "${dynamodb_table_name}",
        "Item": {
          "JobId": {
            "S.$": "$.jobId"
          },
          "Status": {
            "S": "FAILED"
          },
          "FailedAt": {
            "S.$": "$$.State.EnteredTime"
          },
          "DocumentLocation": {
            "S.$": "States.Format('s3://{}/{}', $.bucket, $.key)"
          },
          "ErrorMessage": {
            "S.$": "$.error.Cause"
          }
        }
      },
      "Next": "NotifyFailure"
    },
    "NotifyFailure": {
      "Type": "Task",
      "Comment": "Send failure notification via SNS",
      "Resource": "arn:aws:states:::aws-sdk:sns:publish",
      "Parameters": {
        "TopicArn": "${sns_topic_arn}",
        "Message.$": "States.Format('Document processing failed for job {}. Error: {}', $.jobId, $.error.Cause)",
        "Subject": "Document Processing Failed"
      },
      "End": true
    }
  }
}
EOF
  filename = "${path.module}/state_machine.json.tpl"
}