# Main Terraform configuration for Automated Data Analysis with Bedrock AgentCore Runtime
# This file creates the complete infrastructure for automated data analysis using AWS services

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Construct resource names with random suffix
  data_bucket_name    = "${var.project_name}-input-${random_id.suffix.hex}"
  results_bucket_name = "${var.project_name}-results-${random_id.suffix.hex}"
  function_name       = "${var.project_name}-orchestrator-${random_id.suffix.hex}"
  role_name          = "${title(var.project_name)}OrchestratorRole-${random_id.suffix.hex}"
  policy_name        = "${title(var.project_name)}OrchestratorPolicy-${random_id.suffix.hex}"
  dashboard_name     = "${title(var.project_name)}Automation-${random_id.suffix.hex}"
  
  # Common tags to apply to all resources
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "bedrock-agentcore-data-analysis"
  })
}

# S3 Bucket for input datasets
resource "aws_s3_bucket" "data_bucket" {
  bucket        = local.data_bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name = "Data Input Bucket"
    Type = "DataStorage"
  })
}

# S3 Bucket for analysis results
resource "aws_s3_bucket" "results_bucket" {
  bucket        = local.results_bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name = "Results Output Bucket"
    Type = "ResultsStorage"
  })
}

# S3 Bucket versioning for data bucket
resource "aws_s3_bucket_versioning" "data_bucket_versioning" {
  bucket = aws_s3_bucket.data_bucket.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# S3 Bucket versioning for results bucket
resource "aws_s3_bucket_versioning" "results_bucket_versioning" {
  bucket = aws_s3_bucket.results_bucket.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# S3 Bucket encryption for data bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "data_bucket_encryption" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket encryption for results bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "results_bucket_encryption" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.results_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access for data bucket
resource "aws_s3_bucket_public_access_block" "data_bucket_pab" {
  bucket = aws_s3_bucket.data_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Block public access for results bucket
resource "aws_s3_bucket_public_access_block" "results_bucket_pab" {
  bucket = aws_s3_bucket.results_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM policy document for Lambda execution role trust relationship
data "aws_iam_policy_document" "lambda_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json

  tags = merge(local.common_tags, {
    Name = "Lambda Execution Role"
    Type = "IAMRole"
  })
}

# IAM policy document for custom permissions
data "aws_iam_policy_document" "lambda_custom_policy" {
  # Bedrock AgentCore permissions
  statement {
    effect = "Allow"
    
    actions = [
      "bedrock-agentcore:CreateCodeInterpreter",
      "bedrock-agentcore:StartCodeInterpreterSession",
      "bedrock-agentcore:InvokeCodeInterpreter",
      "bedrock-agentcore:StopCodeInterpreterSession",
      "bedrock-agentcore:DeleteCodeInterpreter",
      "bedrock-agentcore:ListCodeInterpreters",
      "bedrock-agentcore:GetCodeInterpreter",
      "bedrock-agentcore:GetCodeInterpreterSession"
    ]
    
    resources = ["*"]
  }

  # S3 object permissions for both buckets
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    
    resources = [
      "${aws_s3_bucket.data_bucket.arn}/*",
      "${aws_s3_bucket.results_bucket.arn}/*"
    ]
  }

  # S3 bucket permissions
  statement {
    effect = "Allow"
    
    actions = ["s3:ListBucket"]
    
    resources = [
      aws_s3_bucket.data_bucket.arn,
      aws_s3_bucket.results_bucket.arn
    ]
  }
}

# Custom IAM policy for Lambda function
resource "aws_iam_policy" "lambda_custom_policy" {
  name   = local.policy_name
  policy = data.aws_iam_policy_document.lambda_custom_policy.json

  tags = merge(local.common_tags, {
    Name = "Lambda Custom Policy"
    Type = "IAMPolicy"
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_custom_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_custom_policy.arn
}

# Create the Lambda function source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      results_bucket_name = local.results_bucket_name
    })
    filename = "lambda_function.py"
  }
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "Lambda Log Group"
    Type = "LogGroup"
  })
}

# Lambda function for data analysis orchestration
resource "aws_lambda_function" "data_analysis_orchestrator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.11"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      RESULTS_BUCKET_NAME = local.results_bucket_name
      LOG_LEVEL          = "INFO"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_custom_policy_attachment,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name = "Data Analysis Orchestrator"
    Type = "LambdaFunction"
  })
}

# Lambda permission for S3 to invoke the function
resource "aws_lambda_permission" "s3_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_analysis_orchestrator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data_bucket.arn
}

# S3 bucket notification to trigger Lambda function
resource "aws_s3_bucket_notification" "data_bucket_notification" {
  bucket = aws_s3_bucket.data_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.data_analysis_orchestrator.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.dataset_prefix
  }

  depends_on = [aws_lambda_permission.s3_invoke_lambda]
}

# CloudWatch Dashboard for monitoring (optional)
resource "aws_cloudwatch_dashboard" "data_analysis_dashboard" {
  count = var.enable_dashboard ? 1 : 0
  
  dashboard_name = local.dashboard_name

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
            ["AWS/Lambda", "Invocations", "FunctionName", local.function_name],
            [".", "Duration", ".", "."],
            [".", "Errors", ".", "."],
            [".", "Throttles", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Data Analysis Lambda Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          query = join("", [
            "SOURCE '/aws/lambda/${local.function_name}'\n",
            "| fields @timestamp, @message\n",
            "| filter @message like /Processing file/\n",
            "| sort @timestamp desc\n",
            "| limit 20"
          ])
          region = data.aws_region.current.name
          title  = "Recent Analysis Activities"
          view   = "table"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Data Analysis Dashboard"
    Type = "Dashboard"
  })
}

# SNS Topic for notifications (optional)
resource "aws_sns_topic" "notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${var.project_name}-notifications-${random_id.suffix.hex}"

  tags = merge(local.common_tags, {
    Name = "Analysis Notifications"
    Type = "SNSTopic"
  })
}

# SNS Topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notifications" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}