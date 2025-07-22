# Reserved Instance Management Automation Infrastructure
# This file creates all AWS resources for automated RI management

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# Local values for resource naming and configuration
locals {
  random_suffix       = random_id.suffix.hex
  account_id         = data.aws_caller_identity.current.account_id
  s3_bucket_name     = "${var.project_name}-ri-reports-${local.account_id}-${local.random_suffix}"
  sns_topic_name     = "${var.project_name}-ri-alerts-${local.random_suffix}"
  dynamodb_table_name = "${var.project_name}-ri-tracking-${local.random_suffix}"
  
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "RI-Management-Automation"
  })
}

# =====================================================
# S3 Bucket for RI Reports Storage
# =====================================================

# S3 bucket for storing RI analysis reports and recommendations
resource "aws_s3_bucket" "ri_reports" {
  bucket = local.s3_bucket_name

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-ri-reports"
    Description = "Storage for Reserved Instance reports and analysis"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "ri_reports_versioning" {
  bucket = aws_s3_bucket.ri_reports.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "ri_reports_encryption" {
  bucket = aws_s3_bucket.ri_reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "ri_reports_pab" {
  bucket = aws_s3_bucket.ri_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "ri_reports_lifecycle" {
  bucket = aws_s3_bucket.ri_reports.id

  rule {
    id     = "ri_reports_lifecycle"
    status = "Enabled"

    # Transition to Infrequent Access storage after specified days
    transition {
      days          = var.s3_bucket_lifecycle_days
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete objects after 2 years
    expiration {
      days = 730
    }

    # Delete incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# =====================================================
# DynamoDB Table for RI Tracking
# =====================================================

# DynamoDB table to store RI tracking data and history
resource "aws_dynamodb_table" "ri_tracking" {
  name           = local.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "ReservationId"
  range_key      = "Timestamp"

  attribute {
    name = "ReservationId"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "N"
  }

  # Optional point-in-time recovery
  point_in_time_recovery {
    enabled = var.dynamodb_point_in_time_recovery
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-ri-tracking"
    Description = "Tracking table for Reserved Instance data"
  })
}

# =====================================================
# SNS Topic for Notifications
# =====================================================

# SNS topic for RI alerts and notifications
resource "aws_sns_topic" "ri_alerts" {
  name = local.sns_topic_name

  # Server-side encryption for SNS
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-ri-alerts"
    Description = "SNS topic for Reserved Instance alerts"
  })
}

# SNS topic policy to allow Lambda functions to publish
resource "aws_sns_topic_policy" "ri_alerts_policy" {
  arn = aws_sns_topic.ri_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.ri_alerts.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# Email subscription to SNS topic (if email provided)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.ri_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# =====================================================
# IAM Role and Policies for Lambda Functions
# =====================================================

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-role-${local.random_suffix}"

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
    Name        = "${var.project_name}-lambda-role"
    Description = "Execution role for RI management Lambda functions"
  })
}

# Custom IAM policy for RI management operations
resource "aws_iam_policy" "lambda_ri_policy" {
  name        = "${var.project_name}-lambda-ri-policy-${local.random_suffix}"
  description = "Policy for RI management Lambda functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:GetDimensionValues",
          "ce:GetUsageAndCosts",
          "ce:GetReservationCoverage",
          "ce:GetReservationPurchaseRecommendation",
          "ce:GetReservationUtilization",
          "ce:GetRightsizingRecommendation"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeReservedInstances",
          "ec2:DescribeInstances",
          "rds:DescribeReservedDBInstances"
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
        Resource = "${aws_s3_bucket.ri_reports.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.ri_tracking.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.ri_alerts.arn
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach custom RI management policy
resource "aws_iam_role_policy_attachment" "lambda_ri_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_ri_policy.arn
}

# Optional X-Ray tracing policy
resource "aws_iam_role_policy_attachment" "lambda_xray_policy" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# =====================================================
# CloudWatch Log Groups for Lambda Functions
# =====================================================

# Log group for RI utilization analysis function
resource "aws_cloudwatch_log_group" "ri_utilization_logs" {
  name              = "/aws/lambda/${var.project_name}-ri-utilization-${local.random_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-ri-utilization-logs"
    Description = "Log group for RI utilization analysis function"
  })
}

# Log group for RI recommendations function
resource "aws_cloudwatch_log_group" "ri_recommendations_logs" {
  name              = "/aws/lambda/${var.project_name}-ri-recommendations-${local.random_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-ri-recommendations-logs"
    Description = "Log group for RI recommendations function"
  })
}

# Log group for RI monitoring function
resource "aws_cloudwatch_log_group" "ri_monitoring_logs" {
  name              = "/aws/lambda/${var.project_name}-ri-monitoring-${local.random_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-ri-monitoring-logs"
    Description = "Log group for RI monitoring function"
  })
}

# =====================================================
# Lambda Function Source Code Archives
# =====================================================

# Archive for RI utilization analysis function
data "archive_file" "ri_utilization_zip" {
  type        = "zip"
  output_path = "${path.module}/ri_utilization_analysis.zip"
  
  source {
    content  = file("${path.module}/lambda_functions/ri_utilization_analysis.py")
    filename = "ri_utilization_analysis.py"
  }
}

# Archive for RI recommendations function
data "archive_file" "ri_recommendations_zip" {
  type        = "zip"
  output_path = "${path.module}/ri_recommendations.zip"
  
  source {
    content  = file("${path.module}/lambda_functions/ri_recommendations.py")
    filename = "ri_recommendations.py"
  }
}

# Archive for RI monitoring function
data "archive_file" "ri_monitoring_zip" {
  type        = "zip"
  output_path = "${path.module}/ri_monitoring.zip"
  
  source {
    content  = file("${path.module}/lambda_functions/ri_monitoring.py")
    filename = "ri_monitoring.py"
  }
}

# =====================================================
# Lambda Functions
# =====================================================

# Lambda function for RI utilization analysis
resource "aws_lambda_function" "ri_utilization" {
  filename         = data.archive_file.ri_utilization_zip.output_path
  function_name    = "${var.project_name}-ri-utilization-${local.random_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "ri_utilization_analysis.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.ri_utilization_zip.output_base64sha256

  # Reserved concurrency (optional)
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  environment {
    variables = {
      S3_BUCKET_NAME         = aws_s3_bucket.ri_reports.bucket
      SNS_TOPIC_ARN         = aws_sns_topic.ri_alerts.arn
      UTILIZATION_THRESHOLD = var.utilization_threshold
      SLACK_WEBHOOK_URL     = var.slack_webhook_url
    }
  }

  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  depends_on = [
    aws_cloudwatch_log_group.ri_utilization_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_ri_policy_attachment
  ]

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-ri-utilization"
    Description = "Analyzes Reserved Instance utilization rates"
  })
}

# Lambda function for RI recommendations
resource "aws_lambda_function" "ri_recommendations" {
  filename         = data.archive_file.ri_recommendations_zip.output_path
  function_name    = "${var.project_name}-ri-recommendations-${local.random_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "ri_recommendations.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.ri_recommendations_zip.output_base64sha256

  # Reserved concurrency (optional)
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  environment {
    variables = {
      S3_BUCKET_NAME    = aws_s3_bucket.ri_reports.bucket
      SNS_TOPIC_ARN     = aws_sns_topic.ri_alerts.arn
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }

  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  depends_on = [
    aws_cloudwatch_log_group.ri_recommendations_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_ri_policy_attachment
  ]

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-ri-recommendations"
    Description = "Generates Reserved Instance purchase recommendations"
  })
}

# Lambda function for RI monitoring
resource "aws_lambda_function" "ri_monitoring" {
  filename         = data.archive_file.ri_monitoring_zip.output_path
  function_name    = "${var.project_name}-ri-monitoring-${local.random_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "ri_monitoring.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.ri_monitoring_zip.output_base64sha256

  # Reserved concurrency (optional)
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  environment {
    variables = {
      DYNAMODB_TABLE_NAME      = aws_dynamodb_table.ri_tracking.name
      SNS_TOPIC_ARN           = aws_sns_topic.ri_alerts.arn
      EXPIRATION_WARNING_DAYS  = var.expiration_warning_days
      CRITICAL_EXPIRATION_DAYS = var.critical_expiration_days
      SLACK_WEBHOOK_URL       = var.slack_webhook_url
    }
  }

  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  depends_on = [
    aws_cloudwatch_log_group.ri_monitoring_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_ri_policy_attachment
  ]

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-ri-monitoring"
    Description = "Monitors Reserved Instance expirations and status"
  })
}

# =====================================================
# EventBridge Rules for Scheduling
# =====================================================

# EventBridge rule for daily RI utilization analysis
resource "aws_cloudwatch_event_rule" "daily_utilization" {
  name                = "${var.project_name}-daily-utilization-${local.random_suffix}"
  description         = "Daily RI utilization analysis"
  schedule_expression = var.daily_analysis_schedule
  state               = "ENABLED"

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-daily-utilization"
    Description = "Daily trigger for RI utilization analysis"
  })
}

# EventBridge rule for weekly RI recommendations
resource "aws_cloudwatch_event_rule" "weekly_recommendations" {
  name                = "${var.project_name}-weekly-recommendations-${local.random_suffix}"
  description         = "Weekly RI purchase recommendations"
  schedule_expression = var.weekly_recommendations_schedule
  state               = "ENABLED"

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-weekly-recommendations"
    Description = "Weekly trigger for RI recommendations"
  })
}

# EventBridge rule for weekly RI monitoring
resource "aws_cloudwatch_event_rule" "weekly_monitoring" {
  name                = "${var.project_name}-weekly-monitoring-${local.random_suffix}"
  description         = "Weekly RI expiration monitoring"
  schedule_expression = var.weekly_monitoring_schedule
  state               = "ENABLED"

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-weekly-monitoring"
    Description = "Weekly trigger for RI monitoring"
  })
}

# =====================================================
# EventBridge Targets
# =====================================================

# Target for daily utilization analysis
resource "aws_cloudwatch_event_target" "utilization_target" {
  rule      = aws_cloudwatch_event_rule.daily_utilization.name
  target_id = "UtilizationLambdaTarget"
  arn       = aws_lambda_function.ri_utilization.arn
}

# Target for weekly recommendations
resource "aws_cloudwatch_event_target" "recommendations_target" {
  rule      = aws_cloudwatch_event_rule.weekly_recommendations.name
  target_id = "RecommendationsLambdaTarget"
  arn       = aws_lambda_function.ri_recommendations.arn
}

# Target for weekly monitoring
resource "aws_cloudwatch_event_target" "monitoring_target" {
  rule      = aws_cloudwatch_event_rule.weekly_monitoring.name
  target_id = "MonitoringLambdaTarget"
  arn       = aws_lambda_function.ri_monitoring.arn
}

# =====================================================
# Lambda Permissions for EventBridge
# =====================================================

# Permission for EventBridge to invoke utilization Lambda
resource "aws_lambda_permission" "utilization_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ri_utilization.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_utilization.arn
}

# Permission for EventBridge to invoke recommendations Lambda
resource "aws_lambda_permission" "recommendations_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ri_recommendations.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_recommendations.arn
}

# Permission for EventBridge to invoke monitoring Lambda
resource "aws_lambda_permission" "monitoring_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ri_monitoring.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_monitoring.arn
}

# =====================================================
# CloudWatch Alarms for Monitoring
# =====================================================

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = {
    utilization     = aws_lambda_function.ri_utilization.function_name
    recommendations = aws_lambda_function.ri_recommendations.function_name
    monitoring      = aws_lambda_function.ri_monitoring.function_name
  }

  alarm_name          = "${each.value}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors Lambda function errors for ${each.value}"
  alarm_actions       = [aws_sns_topic.ri_alerts.arn]

  dimensions = {
    FunctionName = each.value
  }

  tags = merge(local.common_tags, {
    Name        = "${each.value}-errors-alarm"
    Description = "CloudWatch alarm for ${each.value} errors"
  })
}

# CloudWatch alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each = {
    utilization     = aws_lambda_function.ri_utilization.function_name
    recommendations = aws_lambda_function.ri_recommendations.function_name
    monitoring      = aws_lambda_function.ri_monitoring.function_name
  }

  alarm_name          = "${each.value}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = "240000" # 4 minutes (240 seconds in milliseconds)
  alarm_description   = "This metric monitors Lambda function duration for ${each.value}"
  alarm_actions       = [aws_sns_topic.ri_alerts.arn]

  dimensions = {
    FunctionName = each.value
  }

  tags = merge(local.common_tags, {
    Name        = "${each.value}-duration-alarm"
    Description = "CloudWatch alarm for ${each.value} duration"
  })
}