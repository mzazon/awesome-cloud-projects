# Main Terraform configuration for Log Analytics Solution
# This file creates the complete infrastructure for CloudWatch Logs Insights analytics

# Data sources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Construct resource names with random suffix
  log_group_name       = "/aws/lambda/${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  sns_topic_name       = "${var.project_name}-alerts-${var.environment}-${random_id.suffix.hex}"
  lambda_function_name = "${var.project_name}-processor-${var.environment}-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}"
      Environment = var.environment
      Project     = var.project_name
    }
  )
}

# CloudWatch Log Group for centralized logging
resource "aws_cloudwatch_log_group" "main" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  
  tags = merge(
    local.common_tags,
    {
      Purpose = "Centralized application logging"
    }
  )
}

# SNS Topic for alert notifications
resource "aws_sns_topic" "alerts" {
  name = local.sns_topic_name
  
  tags = merge(
    local.common_tags,
    {
      Purpose = "Log analytics alert notifications"
    }
  )
}

# SNS Topic Subscription for email notifications
resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# IAM Role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.lambda_function_name}-role"
  
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
      Purpose = "Lambda execution role for log analytics"
    }
  )
}

# IAM Policy for CloudWatch Logs Insights access
resource "aws_iam_policy" "logs_insights_policy" {
  name        = "${local.lambda_function_name}-logs-policy"
  description = "Policy for CloudWatch Logs Insights access"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:StartQuery",
          "logs:GetQueryResults",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM Policy for SNS publishing
resource "aws_iam_policy" "sns_publish_policy" {
  name        = "${local.lambda_function_name}-sns-policy"
  description = "Policy for SNS publishing access"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach custom CloudWatch Logs Insights policy
resource "aws_iam_role_policy_attachment" "logs_insights_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.logs_insights_policy.arn
}

# Attach custom SNS publishing policy
resource "aws_iam_role_policy_attachment" "sns_publish_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.sns_publish_policy.arn
}

# Lambda function source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      log_group_name       = local.log_group_name
      sns_topic_arn        = aws_sns_topic.alerts.arn
      error_threshold      = var.error_threshold
      analysis_window_hours = var.analysis_window_hours
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for automated log analysis
resource "aws_lambda_function" "log_analyzer" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      LOG_GROUP_NAME        = local.log_group_name
      SNS_TOPIC_ARN         = aws_sns_topic.alerts.arn
      ERROR_THRESHOLD       = var.error_threshold
      ANALYSIS_WINDOW_HOURS = var.analysis_window_hours
    }
  }
  
  tags = merge(
    local.common_tags,
    {
      Purpose = "Automated log analysis and alerting"
    }
  )
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.logs_insights_policy,
    aws_iam_role_policy_attachment.sns_publish_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda function logs
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(
    local.common_tags,
    {
      Purpose = "Lambda function logs"
    }
  )
}

# EventBridge Rule for scheduled log analysis
resource "aws_cloudwatch_event_rule" "log_analysis_schedule" {
  name                = "${local.lambda_function_name}-schedule"
  description         = "Automated log analysis schedule"
  schedule_expression = var.analysis_schedule
  
  tags = merge(
    local.common_tags,
    {
      Purpose = "Scheduled log analysis trigger"
    }
  )
}

# EventBridge Target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.log_analysis_schedule.name
  target_id = "TriggerLambdaFunction"
  arn       = aws_lambda_function.log_analyzer.arn
}

# Lambda permission for EventBridge to invoke function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_analyzer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.log_analysis_schedule.arn
}

# Optional: Sample log data for testing (if enabled)
resource "aws_cloudwatch_log_stream" "sample_stream" {
  count          = var.enable_sample_data ? 1 : 0
  name           = "api-server-001"
  log_group_name = aws_cloudwatch_log_group.main.name
  
  depends_on = [aws_cloudwatch_log_group.main]
}

# Lambda function for generating sample log data (if enabled)
resource "aws_lambda_function" "sample_data_generator" {
  count            = var.enable_sample_data ? 1 : 0
  filename         = data.archive_file.sample_data_zip[0].output_path
  function_name    = "${local.lambda_function_name}-sample-data"
  role            = aws_iam_role.sample_data_role[0].arn
  handler         = "sample_data.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  source_code_hash = data.archive_file.sample_data_zip[0].output_base64sha256
  
  environment {
    variables = {
      LOG_GROUP_NAME = local.log_group_name
      LOG_STREAM_NAME = aws_cloudwatch_log_stream.sample_stream[0].name
    }
  }
  
  tags = merge(
    local.common_tags,
    {
      Purpose = "Sample log data generation"
    }
  )
}

# IAM Role for sample data generation Lambda (if enabled)
resource "aws_iam_role" "sample_data_role" {
  count = var.enable_sample_data ? 1 : 0
  name  = "${local.lambda_function_name}-sample-data-role"
  
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

# IAM Policy for sample data generation (if enabled)
resource "aws_iam_policy" "sample_data_policy" {
  count       = var.enable_sample_data ? 1 : 0
  name        = "${local.lambda_function_name}-sample-data-policy"
  description = "Policy for sample data generation"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.main.arn}:*"
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach policies to sample data role (if enabled)
resource "aws_iam_role_policy_attachment" "sample_data_basic_execution" {
  count      = var.enable_sample_data ? 1 : 0
  role       = aws_iam_role.sample_data_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "sample_data_logs_policy" {
  count      = var.enable_sample_data ? 1 : 0
  role       = aws_iam_role.sample_data_role[0].name
  policy_arn = aws_iam_policy.sample_data_policy[0].arn
}

# Sample data generator Lambda source code (if enabled)
data "archive_file" "sample_data_zip" {
  count       = var.enable_sample_data ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/sample_data.zip"
  
  source {
    content = templatefile("${path.module}/sample_data.py.tpl", {
      log_group_name  = local.log_group_name
      log_stream_name = "api-server-001"
    })
    filename = "sample_data.py"
  }
}

# Lambda invocation to generate sample data (if enabled)
resource "aws_lambda_invocation" "sample_data_trigger" {
  count         = var.enable_sample_data ? 1 : 0
  function_name = aws_lambda_function.sample_data_generator[0].function_name
  
  input = jsonencode({
    generate_sample_data = true
  })
  
  depends_on = [
    aws_lambda_function.sample_data_generator,
    aws_cloudwatch_log_stream.sample_stream
  ]
}