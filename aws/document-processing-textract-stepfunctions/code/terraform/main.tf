# Main Terraform Configuration for Document Processing Pipeline
# This file contains the core infrastructure resources for the automated document processing system

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values for consistent naming and configuration
locals {
  project_id = "${var.project_name}-${random_string.suffix.result}"
  
  # S3 bucket names
  input_bucket_name   = "${local.project_id}-input"
  output_bucket_name  = "${local.project_id}-output"
  archive_bucket_name = "${local.project_id}-archive"
  
  # Lambda function names
  document_processor_name = "${local.project_id}-document-processor"
  results_processor_name  = "${local.project_id}-results-processor"
  s3_trigger_name        = "${local.project_id}-s3-trigger"
  
  # Step Functions state machine name
  state_machine_name = "${local.project_id}-document-pipeline"
  
  # Common tags
  common_tags = var.enable_cost_allocation_tags ? {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "building-automated-document-processing-pipelines"
    CostCenter  = "DocumentProcessing"
    Owner       = "DataTeam"
  } : {}
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# ========================================
# S3 BUCKETS FOR DOCUMENT STORAGE
# ========================================

# Input bucket for document uploads
resource "aws_s3_bucket" "input" {
  bucket = local.input_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "Document Input Bucket"
    Type = "InputStorage"
  })
}

# Output bucket for processed results
resource "aws_s3_bucket" "output" {
  bucket = local.output_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "Document Output Bucket"
    Type = "OutputStorage"
  })
}

# Archive bucket for document retention
resource "aws_s3_bucket" "archive" {
  bucket = local.archive_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "Document Archive Bucket"
    Type = "ArchiveStorage"
  })
}

# Configure versioning for input bucket
resource "aws_s3_bucket_versioning" "input" {
  bucket = aws_s3_bucket.input.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# Configure versioning for output bucket
resource "aws_s3_bucket_versioning" "output" {
  bucket = aws_s3_bucket.output.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# Configure versioning for archive bucket
resource "aws_s3_bucket_versioning" "archive" {
  bucket = aws_s3_bucket.archive.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# Server-side encryption for input bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.input.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Server-side encryption for output bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Server-side encryption for archive bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.archive.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access for input bucket
resource "aws_s3_bucket_public_access_block" "input" {
  bucket = aws_s3_bucket.input.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Block public access for output bucket
resource "aws_s3_bucket_public_access_block" "output" {
  bucket = aws_s3_bucket.output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Block public access for archive bucket
resource "aws_s3_bucket_public_access_block" "archive" {
  bucket = aws_s3_bucket.archive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for archive bucket
resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id

  rule {
    id     = "archive_transition"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.backup_retention_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.backup_retention_days + 365
    }
  }
}

# ========================================
# IAM ROLES AND POLICIES
# ========================================

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${local.project_id}-lambda-role"

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
    Name = "Lambda Execution Role"
    Type = "IAMRole"
  })
}

# IAM policy for Lambda functions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.project_id}-lambda-policy"
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
          "textract:StartDocumentAnalysis",
          "textract:StartDocumentTextDetection",
          "textract:GetDocumentAnalysis",
          "textract:GetDocumentTextDetection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.input.arn}/*",
          "${aws_s3_bucket.output.arn}/*",
          "${aws_s3_bucket.archive.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.input.arn,
          aws_s3_bucket.output.arn,
          aws_s3_bucket.archive.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.document_pipeline.arn
      }
    ]
  })
}

# Attach managed policy for X-Ray tracing
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count      = var.enable_xray_tracing ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
  role       = aws_iam_role.lambda_role.name
}

# IAM role for Step Functions
resource "aws_iam_role" "stepfunctions_role" {
  name = "${local.project_id}-stepfunctions-role"

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
    Name = "Step Functions Execution Role"
    Type = "IAMRole"
  })
}

# IAM policy for Step Functions
resource "aws_iam_role_policy" "stepfunctions_policy" {
  name = "${local.project_id}-stepfunctions-policy"
  role = aws_iam_role.stepfunctions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.document_processor.arn,
          aws_lambda_function.results_processor.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# ========================================
# LAMBDA FUNCTIONS
# ========================================

# Lambda function for document processing initiation
resource "aws_lambda_function" "document_processor" {
  filename         = "document-processor.zip"
  function_name    = local.document_processor_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "document_processor.lambda_handler"
  runtime         = "python3.11"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  description     = "Initiates Textract document processing"

  environment {
    variables = {
      TEXTRACT_FEATURES = jsonencode(var.textract_features)
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  tags = merge(local.common_tags, {
    Name = "Document Processor Lambda"
    Type = "LambdaFunction"
  })

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.document_processor
  ]
}

# Lambda function for results processing
resource "aws_lambda_function" "results_processor" {
  filename         = "results-processor.zip"
  function_name    = local.results_processor_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "results_processor.lambda_handler"
  runtime         = "python3.11"
  timeout         = var.results_processor_timeout
  memory_size     = var.results_processor_memory_size
  description     = "Processes and formats Textract extraction results"

  environment {
    variables = {
      OUTPUT_BUCKET  = aws_s3_bucket.output.id
      ARCHIVE_BUCKET = aws_s3_bucket.archive.id
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  tags = merge(local.common_tags, {
    Name = "Results Processor Lambda"
    Type = "LambdaFunction"
  })

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.results_processor
  ]
}

# Lambda function for S3 event trigger
resource "aws_lambda_function" "s3_trigger" {
  filename         = "s3-trigger.zip"
  function_name    = local.s3_trigger_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "s3_trigger.lambda_handler"
  runtime         = "python3.11"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  description     = "Triggers document processing pipeline from S3 events"

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.document_pipeline.arn
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  tags = merge(local.common_tags, {
    Name = "S3 Trigger Lambda"
    Type = "LambdaFunction"
  })

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.s3_trigger
  ]
}

# ========================================
# STEP FUNCTIONS STATE MACHINE
# ========================================

# Step Functions state machine for document processing pipeline
resource "aws_sfn_state_machine" "document_pipeline" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.stepfunctions_role.arn
  type     = "STANDARD"

  definition = jsonencode({
    Comment = "Document Processing Pipeline with Amazon Textract"
    StartAt = "ProcessDocument"
    States = {
      ProcessDocument = {
        Type     = "Task"
        Resource = aws_lambda_function.document_processor.arn
        Parameters = {
          "bucket.$" = "$.bucket"
          "key.$"    = "$.key"
        }
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 5
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "ProcessingFailed"
          }
        ]
        Next = "WaitForTextractCompletion"
      }
      WaitForTextractCompletion = {
        Type    = "Wait"
        Seconds = 30
        Next    = "CheckTextractStatus"
      }
      CheckTextractStatus = {
        Type     = "Task"
        Resource = aws_lambda_function.results_processor.arn
        Parameters = {
          "jobId.$"       = "$.jobId"
          "jobType.$"     = "$.jobType"
          "bucket.$"      = "$.bucket"
          "key.$"         = "$.key"
          "outputBucket"  = aws_s3_bucket.output.id
          "archiveBucket" = aws_s3_bucket.archive.id
        }
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 10
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Next = "EvaluateStatus"
      }
      EvaluateStatus = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.status"
            StringEquals  = "COMPLETED"
            Next          = "ProcessingCompleted"
          },
          {
            Variable      = "$.status"
            StringEquals  = "IN_PROGRESS"
            Next          = "WaitForTextractCompletion"
          },
          {
            Variable      = "$.status"
            StringEquals  = "FAILED"
            Next          = "ProcessingFailed"
          }
        ]
        Default = "ProcessingFailed"
      }
      ProcessingCompleted = {
        Type = "Succeed"
        Result = {
          message = "Document processing completed successfully"
        }
      }
      ProcessingFailed = {
        Type  = "Fail"
        Cause = "Document processing failed"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.stepfunctions.arn}:*"
    include_execution_data = true
    level                  = var.step_function_logging_level
  }

  tags = merge(local.common_tags, {
    Name = "Document Processing State Machine"
    Type = "StepFunctions"
  })
}

# ========================================
# S3 EVENT NOTIFICATIONS
# ========================================

# S3 bucket notification configuration
resource "aws_s3_bucket_notification" "input_bucket_notification" {
  bucket = aws_s3_bucket.input.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".pdf"
  }

  depends_on = [aws_lambda_permission.s3_trigger_permission]
}

# Lambda permission for S3 to invoke the trigger function
resource "aws_lambda_permission" "s3_trigger_permission" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input.arn
}

# ========================================
# CLOUDWATCH RESOURCES
# ========================================

# CloudWatch log group for document processor Lambda
resource "aws_cloudwatch_log_group" "document_processor" {
  name              = "/aws/lambda/${local.document_processor_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "Document Processor Logs"
    Type = "LogGroup"
  })
}

# CloudWatch log group for results processor Lambda
resource "aws_cloudwatch_log_group" "results_processor" {
  name              = "/aws/lambda/${local.results_processor_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "Results Processor Logs"
    Type = "LogGroup"
  })
}

# CloudWatch log group for S3 trigger Lambda
resource "aws_cloudwatch_log_group" "s3_trigger" {
  name              = "/aws/lambda/${local.s3_trigger_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "S3 Trigger Logs"
    Type = "LogGroup"
  })
}

# CloudWatch log group for Step Functions
resource "aws_cloudwatch_log_group" "stepfunctions" {
  name              = "/aws/stepfunctions/${local.state_machine_name}"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "Step Functions Logs"
    Type = "LogGroup"
  })
}

# CloudWatch dashboard for pipeline monitoring
resource "aws_cloudwatch_dashboard" "pipeline_dashboard" {
  count          = var.enable_dashboard ? 1 : 0
  dashboard_name = "${local.project_id}-pipeline-monitoring"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", local.document_processor_name],
            [".", "Duration", ".", "."],
            [".", "Errors", ".", "."],
            [".", "Throttles", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Document Processor Lambda Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/States", "ExecutionsStarted", "StateMachineArn", aws_sfn_state_machine.document_pipeline.arn],
            [".", "ExecutionsSucceeded", ".", "."],
            [".", "ExecutionsFailed", ".", "."],
            [".", "ExecutionTime", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Step Functions Pipeline Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.input.id, "StorageType", "StandardStorage"],
            [".", ".", ".", aws_s3_bucket.output.id, ".", "."],
            [".", ".", ".", aws_s3_bucket.archive.id, ".", "."]
          ]
          period = 86400
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "S3 Storage Usage"
          view   = "timeSeries"
        }
      }
    ]
  })
}

# ========================================
# SNS TOPIC FOR NOTIFICATIONS (OPTIONAL)
# ========================================

# SNS topic for failure notifications
resource "aws_sns_topic" "failure_notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${local.project_id}-failure-notifications"

  tags = merge(local.common_tags, {
    Name = "Failure Notifications"
    Type = "SNSTopic"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notifications" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.failure_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ========================================
# LAMBDA FUNCTION SOURCE CODE
# ========================================

# Archive file for document processor Lambda
data "archive_file" "document_processor" {
  type        = "zip"
  output_path = "document-processor.zip"
  
  source {
    content = <<EOF
import json
import boto3
import logging
import os
from urllib.parse import unquote_plus

logger = logging.getLogger()
logger.setLevel(logging.INFO)

textract = boto3.client('textract')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Extract S3 information from event
        bucket = event['bucket']
        key = unquote_plus(event['key'])
        
        logger.info(f"Processing document: s3://{bucket}/{key}")
        
        # Get Textract features from environment
        textract_features = json.loads(os.environ.get('TEXTRACT_FEATURES', '["TABLES", "FORMS"]'))
        
        # Determine document type and processing method
        file_extension = key.lower().split('.')[-1]
        
        # Configure Textract parameters based on document type
        if file_extension in ['pdf', 'png', 'jpg', 'jpeg', 'tiff']:
            # Start document analysis for complex documents
            response = textract.start_document_analysis(
                DocumentLocation={
                    'S3Object': {
                        'Bucket': bucket,
                        'Name': key
                    }
                },
                FeatureTypes=textract_features
            )
            
            job_id = response['JobId']
            
            return {
                'statusCode': 200,
                'jobId': job_id,
                'jobType': 'ANALYSIS',
                'bucket': bucket,
                'key': key,
                'documentType': file_extension
            }
        else:
            raise ValueError(f"Unsupported file type: {file_extension}")
            
    except Exception as e:
        logger.error(f"Error processing document: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }
EOF
    filename = "document_processor.py"
  }
}

# Archive file for results processor Lambda
data "archive_file" "results_processor" {
  type        = "zip"
  output_path = "results-processor.zip"
  
  source {
    content = <<EOF
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

textract = boto3.client('textract')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        job_id = event['jobId']
        job_type = event['jobType']
        bucket = event['bucket']
        key = event['key']
        output_bucket = event.get('outputBucket', bucket)
        archive_bucket = event.get('archiveBucket')
        
        logger.info(f"Processing results for job: {job_id}")
        
        # Get Textract results based on job type
        if job_type == 'ANALYSIS':
            response = textract.get_document_analysis(JobId=job_id)
        else:
            response = textract.get_document_text_detection(JobId=job_id)
        
        # Check job status
        job_status = response['JobStatus']
        
        if job_status == 'SUCCEEDED':
            # Process and structure the results
            processed_data = {
                'timestamp': datetime.utcnow().isoformat(),
                'sourceDocument': f"s3://{bucket}/{key}",
                'jobId': job_id,
                'jobType': job_type,
                'documentMetadata': response.get('DocumentMetadata', {}),
                'extractedData': {
                    'text': [],
                    'tables': [],
                    'forms': []
                }
            }
            
            # Parse blocks and extract meaningful data
            blocks = response.get('Blocks', [])
            
            for block in blocks:
                if block['BlockType'] == 'LINE':
                    processed_data['extractedData']['text'].append({
                        'text': block.get('Text', ''),
                        'confidence': block.get('Confidence', 0),
                        'geometry': block.get('Geometry', {})
                    })
                elif block['BlockType'] == 'TABLE':
                    # Process table data
                    table_data = {
                        'id': block.get('Id', ''),
                        'confidence': block.get('Confidence', 0),
                        'geometry': block.get('Geometry', {}),
                        'rowCount': block.get('RowCount', 0),
                        'columnCount': block.get('ColumnCount', 0)
                    }
                    processed_data['extractedData']['tables'].append(table_data)
                elif block['BlockType'] == 'KEY_VALUE_SET':
                    # Process form data
                    if block.get('EntityTypes') and 'KEY' in block['EntityTypes']:
                        form_data = {
                            'id': block.get('Id', ''),
                            'confidence': block.get('Confidence', 0),
                            'geometry': block.get('Geometry', {}),
                            'text': block.get('Text', '')
                        }
                        processed_data['extractedData']['forms'].append(form_data)
            
            # Save processed results to S3 output bucket
            output_key = f"processed/{key.replace('.', '_')}_results.json"
            
            s3.put_object(
                Bucket=output_bucket,
                Key=output_key,
                Body=json.dumps(processed_data, indent=2),
                ContentType='application/json',
                Metadata={
                    'source-bucket': bucket,
                    'source-key': key,
                    'processing-timestamp': datetime.utcnow().isoformat()
                }
            )
            
            # Archive original document if archive bucket is specified
            if archive_bucket:
                archive_key = f"archive/{datetime.utcnow().strftime('%Y/%m/%d')}/{key}"
                s3.copy_object(
                    CopySource={'Bucket': bucket, 'Key': key},
                    Bucket=archive_bucket,
                    Key=archive_key
                )
            
            return {
                'statusCode': 200,
                'status': 'COMPLETED',
                'outputLocation': f"s3://{output_bucket}/{output_key}",
                'extractedItems': {
                    'textLines': len(processed_data['extractedData']['text']),
                    'tables': len(processed_data['extractedData']['tables']),
                    'forms': len(processed_data['extractedData']['forms'])
                }
            }
            
        elif job_status == 'FAILED':
            logger.error(f"Textract job failed: {job_id}")
            return {
                'statusCode': 500,
                'status': 'FAILED',
                'error': 'Textract job failed'
            }
        else:
            # Job still in progress
            return {
                'statusCode': 202,
                'status': 'IN_PROGRESS',
                'message': f"Job status: {job_status}"
            }
            
    except Exception as e:
        logger.error(f"Error processing results: {str(e)}")
        return {
            'statusCode': 500,
            'status': 'ERROR',
            'error': str(e)
        }
EOF
    filename = "results_processor.py"
  }
}

# Archive file for S3 trigger Lambda
data "archive_file" "s3_trigger" {
  type        = "zip"
  output_path = "s3-trigger.zip"
  
  source {
    content = <<EOF
import json
import boto3
import logging
import os
from urllib.parse import unquote_plus

logger = logging.getLogger()
logger.setLevel(logging.INFO)

stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    try:
        state_machine_arn = os.environ['STATE_MACHINE_ARN']
        
        # Process S3 event records
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"New document uploaded: s3://{bucket}/{key}")
            
            # Start Step Functions execution
            execution_input = {
                'bucket': bucket,
                'key': key,
                'eventTime': record['eventTime']
            }
            
            execution_name = f"doc-processing-{key.replace('/', '-').replace('.', '-')}-{context.aws_request_id[:8]}"
            
            response = stepfunctions.start_execution(
                stateMachineArn=state_machine_arn,
                name=execution_name,
                input=json.dumps(execution_input)
            )
            
            logger.info(f"Started execution: {response['executionArn']}")
            
        return {
            'statusCode': 200,
            'message': f"Processed {len(event['Records'])} document(s)"
        }
        
    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }
EOF
    filename = "s3_trigger.py"
  }
}