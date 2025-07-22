# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # S3 bucket names (must be globally unique)
  input_bucket_name  = var.input_bucket_name != "" ? var.input_bucket_name : "${local.name_prefix}-input-${local.name_suffix}"
  output_bucket_name = var.output_bucket_name != "" ? var.output_bucket_name : "${local.name_prefix}-output-${local.name_suffix}"
  
  # DynamoDB table name
  metadata_table_name = "${local.name_prefix}-metadata-${local.name_suffix}"
  
  # SNS topic name
  sns_topic_name = "${local.name_prefix}-notifications-${local.name_suffix}"
  
  # Common tags
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "document-analysis-amazon-textract"
    ManagedBy   = "terraform"
  })
}

# ===============================
# S3 BUCKETS
# ===============================

# S3 bucket for document input
resource "aws_s3_bucket" "input" {
  bucket        = local.input_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-input-bucket"
    Type = "DocumentInput"
  })
}

# S3 bucket versioning for input bucket
resource "aws_s3_bucket_versioning" "input" {
  bucket = aws_s3_bucket.input.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption for input bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.input.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for input bucket
resource "aws_s3_bucket_public_access_block" "input" {
  bucket = aws_s3_bucket.input.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket for document output/results
resource "aws_s3_bucket" "output" {
  bucket        = local.output_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-output-bucket"
    Type = "DocumentOutput"
  })
}

# S3 bucket versioning for output bucket
resource "aws_s3_bucket_versioning" "output" {
  bucket = aws_s3_bucket.output.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption for output bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for output bucket
resource "aws_s3_bucket_public_access_block" "output" {
  bucket = aws_s3_bucket.output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 lifecycle configuration for input bucket
resource "aws_s3_bucket_lifecycle_configuration" "input" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.input.id

  rule {
    id     = "document_lifecycle"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_lifecycle_days * 2
      storage_class = "GLACIER"
    }

    expiration {
      days = var.s3_lifecycle_days * 12 # 1 year for dev
    }
  }
}

# ===============================
# DYNAMODB TABLE
# ===============================

# DynamoDB table for document metadata
resource "aws_dynamodb_table" "metadata" {
  name           = local.metadata_table_name
  billing_mode   = var.dynamodb_billing_mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  hash_key       = "documentId"

  attribute {
    name = "documentId"
    type = "S"
  }

  # Global Secondary Index for querying by document type
  global_secondary_index {
    name            = "DocumentTypeIndex"
    hash_key        = "documentType"
    projection_type = "ALL"
    read_capacity   = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  attribute {
    name = "documentType"
    type = "S"
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Encryption at rest
  server_side_encryption {
    enabled = var.enable_dynamodb_encryption
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-metadata-table"
    Type = "DocumentMetadata"
  })
}

# ===============================
# SNS TOPIC AND SUBSCRIPTIONS
# ===============================

# SNS topic for notifications
resource "aws_sns_topic" "notifications" {
  name = local.sns_topic_name

  # Enable server-side encryption
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-notifications-topic"
    Type = "Notifications"
  })
}

# SNS topic policy for Textract to publish
resource "aws_sns_topic_policy" "notifications" {
  arn = aws_sns_topic.notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "textract.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Optional email subscription
resource "aws_sns_topic_subscription" "email" {
  count     = var.sns_email_endpoint != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = var.sns_email_protocol
  endpoint  = var.sns_email_endpoint
}

# ===============================
# IAM ROLES AND POLICIES
# ===============================

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution" {
  name = "${local.name_prefix}-lambda-execution-role"

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
    Name = "${local.name_prefix}-lambda-execution-role"
    Type = "IAMRole"
  })
}

# IAM role for Step Functions
resource "aws_iam_role" "step_functions" {
  name = "${local.name_prefix}-step-functions-role"

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
    Name = "${local.name_prefix}-step-functions-role"
    Type = "IAMRole"
  })
}

# IAM policy for Lambda functions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda_execution.id

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
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.input.arn}/*",
          "${aws_s3_bucket.output.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.input.arn,
          aws_s3_bucket.output.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.metadata.arn,
          "${aws_dynamodb_table.metadata.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "textract:AnalyzeDocument",
          "textract:DetectDocumentText",
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
          "sns:Publish"
        ]
        Resource = aws_sns_topic.notifications.arn
      }
    ]
  })
}

# IAM policy for Step Functions
resource "aws_iam_role_policy" "step_functions_policy" {
  name = "${local.name_prefix}-step-functions-policy"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.document_classifier.arn,
          aws_lambda_function.textract_processor.arn,
          aws_lambda_function.async_results_processor.arn,
          aws_lambda_function.document_query.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "textract:GetDocumentAnalysis",
          "textract:GetDocumentTextDetection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# ===============================
# LAMBDA FUNCTIONS
# ===============================

# Lambda function package for document classifier
data "archive_file" "document_classifier" {
  type        = "zip"
  output_path = "${path.module}/document_classifier.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/document_classifier.py", {
      output_bucket    = local.output_bucket_name
      metadata_table   = local.metadata_table_name
    })
    filename = "lambda_function.py"
  }
}

# Document classifier Lambda function
resource "aws_lambda_function" "document_classifier" {
  filename         = data.archive_file.document_classifier.output_path
  function_name    = "${local.name_prefix}-document-classifier"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 30
  memory_size     = 256
  source_code_hash = data.archive_file.document_classifier.output_base64sha256

  environment {
    variables = {
      OUTPUT_BUCKET   = aws_s3_bucket.output.bucket
      METADATA_TABLE  = aws_dynamodb_table.metadata.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.document_classifier]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-document-classifier"
    Type = "LambdaFunction"
  })
}

# Lambda function package for Textract processor
data "archive_file" "textract_processor" {
  type        = "zip"
  output_path = "${path.module}/textract_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/textract_processor.py", {
      output_bucket      = local.output_bucket_name
      metadata_table     = local.metadata_table_name
      sns_topic_arn      = aws_sns_topic.notifications.arn
      execution_role_arn = aws_iam_role.lambda_execution.arn
    })
    filename = "lambda_function.py"
  }
}

# Textract processor Lambda function
resource "aws_lambda_function" "textract_processor" {
  filename         = data.archive_file.textract_processor.output_path
  function_name    = "${local.name_prefix}-textract-processor"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.textract_processor.output_base64sha256

  environment {
    variables = {
      OUTPUT_BUCKET      = aws_s3_bucket.output.bucket
      METADATA_TABLE     = aws_dynamodb_table.metadata.name
      SNS_TOPIC_ARN      = aws_sns_topic.notifications.arn
      EXECUTION_ROLE_ARN = aws_iam_role.lambda_execution.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.textract_processor]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-textract-processor"
    Type = "LambdaFunction"
  })
}

# Lambda function package for async results processor
data "archive_file" "async_results_processor" {
  type        = "zip"
  output_path = "${path.module}/async_results_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/async_results_processor.py", {
      output_bucket  = local.output_bucket_name
      metadata_table = local.metadata_table_name
    })
    filename = "lambda_function.py"
  }
}

# Async results processor Lambda function
resource "aws_lambda_function" "async_results_processor" {
  filename         = data.archive_file.async_results_processor.output_path
  function_name    = "${local.name_prefix}-async-results-processor"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.async_results_processor.output_base64sha256

  environment {
    variables = {
      OUTPUT_BUCKET  = aws_s3_bucket.output.bucket
      METADATA_TABLE = aws_dynamodb_table.metadata.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.async_results_processor]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-async-results-processor"
    Type = "LambdaFunction"
  })
}

# Lambda function package for document query
data "archive_file" "document_query" {
  type        = "zip"
  output_path = "${path.module}/document_query.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/document_query.py", {
      metadata_table = local.metadata_table_name
    })
    filename = "lambda_function.py"
  }
}

# Document query Lambda function
resource "aws_lambda_function" "document_query" {
  filename         = data.archive_file.document_query.output_path
  function_name    = "${local.name_prefix}-document-query"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 30
  memory_size     = 256
  source_code_hash = data.archive_file.document_query.output_base64sha256

  environment {
    variables = {
      METADATA_TABLE = aws_dynamodb_table.metadata.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.document_query]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-document-query"
    Type = "LambdaFunction"
  })
}

# ===============================
# CLOUDWATCH LOG GROUPS
# ===============================

# CloudWatch log group for document classifier
resource "aws_cloudwatch_log_group" "document_classifier" {
  name              = "/aws/lambda/${local.name_prefix}-document-classifier"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-document-classifier-logs"
    Type = "LogGroup"
  })
}

# CloudWatch log group for Textract processor
resource "aws_cloudwatch_log_group" "textract_processor" {
  name              = "/aws/lambda/${local.name_prefix}-textract-processor"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-textract-processor-logs"
    Type = "LogGroup"
  })
}

# CloudWatch log group for async results processor
resource "aws_cloudwatch_log_group" "async_results_processor" {
  name              = "/aws/lambda/${local.name_prefix}-async-results-processor"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-async-results-processor-logs"
    Type = "LogGroup"
  })
}

# CloudWatch log group for document query
resource "aws_cloudwatch_log_group" "document_query" {
  name              = "/aws/lambda/${local.name_prefix}-document-query"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-document-query-logs"
    Type = "LogGroup"
  })
}

# CloudWatch log group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/stepfunctions/${local.name_prefix}-workflow"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-step-functions-logs"
    Type = "LogGroup"
  })
}

# ===============================
# STEP FUNCTIONS
# ===============================

# Step Functions state machine
resource "aws_sfn_state_machine" "textract_workflow" {
  name     = "${local.name_prefix}-workflow"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "Document Analysis Workflow with Amazon Textract"
    StartAt = "ClassifyDocument"
    States = {
      ClassifyDocument = {
        Type     = "Task"
        Resource = aws_lambda_function.document_classifier.arn
        Next     = "ProcessDocument"
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"]
            IntervalSeconds = 2
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
      }
      ProcessDocument = {
        Type     = "Task"
        Resource = aws_lambda_function.textract_processor.arn
        Next     = "CheckProcessingType"
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"]
            IntervalSeconds = 2
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
      }
      CheckProcessingType = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.body.processingType"
            StringEquals  = "async"
            Next          = "WaitForAsyncCompletion"
          }
        ]
        Default = "ProcessingComplete"
      }
      WaitForAsyncCompletion = {
        Type    = "Wait"
        Seconds = 30
        Next    = "CheckAsyncStatus"
      }
      CheckAsyncStatus = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:textract:getDocumentAnalysis"
        Parameters = {
          "JobId.$" = "$.body.result.jobId"
        }
        Next = "IsAsyncComplete"
        Retry = [
          {
            ErrorEquals     = ["Textract.InvalidJobIdException"]
            IntervalSeconds = 1
            MaxAttempts     = 0
          },
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 2
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
      }
      IsAsyncComplete = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.JobStatus"
            StringEquals = "SUCCEEDED"
            Next         = "ProcessingComplete"
          },
          {
            Variable     = "$.JobStatus"
            StringEquals = "FAILED"
            Next         = "ProcessingFailed"
          }
        ]
        Default = "WaitForAsyncCompletion"
      }
      ProcessingComplete = {
        Type   = "Pass"
        Result = "Document processing completed successfully"
        End    = true
      }
      ProcessingFailed = {
        Type  = "Fail"
        Error = "DocumentProcessingFailed"
        Cause = "Textract processing failed"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = var.step_functions_log_level
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-step-functions-workflow"
    Type = "StepFunction"
  })
}

# ===============================
# S3 EVENT NOTIFICATIONS
# ===============================

# Lambda permission for S3 to invoke document classifier
resource "aws_lambda_permission" "s3_invoke_classifier" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.document_classifier.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input.arn
}

# S3 bucket notification configuration
resource "aws_s3_bucket_notification" "input_bucket_notification" {
  bucket = aws_s3_bucket.input.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.document_classifier.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "documents/"
    filter_suffix       = ".pdf"
  }

  depends_on = [aws_lambda_permission.s3_invoke_classifier]
}

# ===============================
# SNS SUBSCRIPTIONS FOR LAMBDA
# ===============================

# Lambda permission for SNS to invoke async results processor
resource "aws_lambda_permission" "sns_invoke_async_processor" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.async_results_processor.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.notifications.arn
}

# SNS subscription for async results processor
resource "aws_sns_topic_subscription" "async_processor" {
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.async_results_processor.arn

  depends_on = [aws_lambda_permission.sns_invoke_async_processor]
}

# ===============================
# CLOUDWATCH ALARMS (OPTIONAL)
# ===============================

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_enhanced_monitoring ? 1 : 0

  alarm_name          = "${local.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.textract_processor.function_name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-errors-alarm"
    Type = "CloudWatchAlarm"
  })
}

# CloudWatch alarm for DynamoDB throttling
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  count = var.enable_enhanced_monitoring ? 1 : 0

  alarm_name          = "${local.name_prefix}-dynamodb-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors DynamoDB throttling"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    TableName = aws_dynamodb_table.metadata.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dynamodb-throttles-alarm"
    Type = "CloudWatchAlarm"
  })
}