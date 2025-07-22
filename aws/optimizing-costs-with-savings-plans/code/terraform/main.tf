# Main Terraform Configuration for Savings Plans Recommendations
# This file contains the primary infrastructure resources for automated
# Savings Plans analysis using Cost Explorer APIs

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values for resource naming and configuration
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_string.suffix.result
  
  # S3 bucket name - use provided name or generate unique one
  s3_bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "${local.name_prefix}-cost-recommendations-${data.aws_caller_identity.current.account_id}-${local.name_suffix}"
  
  # Lambda function name with suffix
  lambda_function_name = "${var.lambda_function_name}-${local.name_suffix}"
  
  # IAM role name
  iam_role_name = "${local.name_prefix}-role-${local.name_suffix}"
  
  # Common tags
  common_tags = merge(
    var.tags,
    {
      Name        = local.name_prefix
      Environment = var.environment
      Project     = var.project_name
    }
  )
}

# S3 Bucket for storing cost recommendations and analysis reports
resource "aws_s3_bucket" "cost_recommendations" {
  bucket = local.s3_bucket_name
  
  tags = merge(
    local.common_tags,
    {
      Name        = local.s3_bucket_name
      Description = "Storage for Savings Plans recommendations and cost analysis reports"
    }
  )
}

# S3 Bucket versioning configuration
resource "aws_s3_bucket_versioning" "cost_recommendations" {
  bucket = aws_s3_bucket.cost_recommendations.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 Bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cost_recommendations" {
  bucket = aws_s3_bucket.cost_recommendations.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "cost_recommendations" {
  bucket = aws_s3_bucket.cost_recommendations.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "cost_recommendations" {
  bucket = aws_s3_bucket.cost_recommendations.id

  rule {
    id     = "cost_reports_lifecycle"
    status = "Enabled"

    transition {
      days          = var.s3_bucket_lifecycle_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_bucket_lifecycle_days + 60
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = local.iam_role_name

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
    local.common_tags,
    {
      Name        = local.iam_role_name
      Description = "IAM role for Savings Plans analyzer Lambda function"
    }
  )
}

# IAM policy for Cost Explorer and Savings Plans access
resource "aws_iam_role_policy" "cost_explorer_policy" {
  name = "CostExplorerAccess"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:GetSavingsPlansPurchaseRecommendation",
          "ce:StartSavingsPlansPurchaseRecommendationGeneration",
          "ce:GetCostAndUsage",
          "ce:GetDimensionValues",
          "ce:GetUsageReport",
          "savingsplans:DescribeSavingsPlans",
          "savingsplans:DescribeSavingsPlansOfferings"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.cost_recommendations.arn,
          "${aws_s3_bucket.cost_recommendations.arn}/*"
        ]
      }
    ]
  })
}

# Attach basic Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name        = "/aws/lambda/${local.lambda_function_name}"
      Description = "CloudWatch logs for Savings Plans analyzer Lambda function"
    }
  )
}

# Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/savings_analyzer.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      s3_bucket_name = aws_s3_bucket.cost_recommendations.id
    })
    filename = "savings_analyzer.py"
  }
}

# Lambda function for Savings Plans analysis
resource "aws_lambda_function" "savings_analyzer" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "savings_analyzer.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_NAME          = aws_s3_bucket.cost_recommendations.id
      DEFAULT_LOOKBACK_DAYS   = var.lambda_analysis_parameters.lookback_days
      DEFAULT_TERM_YEARS      = var.lambda_analysis_parameters.term_years
      DEFAULT_PAYMENT_OPTION  = var.lambda_analysis_parameters.payment_option
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(
    local.common_tags,
    {
      Name        = local.lambda_function_name
      Description = "Lambda function for automated Savings Plans analysis"
    }
  )
}

# EventBridge rule for scheduled analysis (optional)
resource "aws_cloudwatch_event_rule" "monthly_analysis" {
  count = var.eventbridge_schedule_enabled ? 1 : 0
  
  name                = "${local.name_prefix}-monthly-analysis"
  description         = "Monthly Savings Plans recommendations generation"
  schedule_expression = var.eventbridge_schedule_expression

  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-monthly-analysis"
      Description = "EventBridge rule for scheduled Savings Plans analysis"
    }
  )
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  count = var.eventbridge_schedule_enabled ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.monthly_analysis[0].name
  target_id = "SavingsPlansAnalyzerTarget"
  arn       = aws_lambda_function.savings_analyzer.arn

  input = jsonencode({
    lookback_days   = var.lambda_analysis_parameters.lookback_days
    term_years      = var.lambda_analysis_parameters.term_years
    payment_option  = var.lambda_analysis_parameters.payment_option
    bucket_name     = aws_s3_bucket.cost_recommendations.id
  })
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.eventbridge_schedule_enabled ? 1 : 0
  
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.savings_analyzer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monthly_analysis[0].arn
}

# CloudWatch Dashboard for monitoring (optional)
resource "aws_cloudwatch_dashboard" "savings_plans_dashboard" {
  count = var.cloudwatch_dashboard_enabled ? 1 : 0
  
  dashboard_name = "${local.name_prefix}-dashboard"

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
            ["AWS/Lambda", "Duration", "FunctionName", local.lambda_function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", local.lambda_function_name],
            ["AWS/Lambda", "Errors", "FunctionName", local.lambda_function_name]
          ]
          view      = "timeSeries"
          stacked   = false
          region    = data.aws_region.current.name
          title     = "Savings Plans Analyzer Performance"
          period    = 300
          stat      = "Average"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '/aws/lambda/${local.lambda_function_name}' | fields @timestamp, @message | sort @timestamp desc | limit 50"
          region = data.aws_region.current.name
          title  = "Recent Analysis Logs"
        }
      }
    ]
  })
}

# Lambda function code template
resource "local_file" "lambda_function_template" {
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    s3_bucket_name = aws_s3_bucket.cost_recommendations.id
  })
  filename = "${path.module}/lambda_function.py"
}