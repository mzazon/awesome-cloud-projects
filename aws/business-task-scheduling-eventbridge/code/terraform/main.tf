# ==============================================================================
# Automated Business Task Scheduling with EventBridge Scheduler and Lambda
# ==============================================================================

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent naming and configuration
locals {
  name_prefix = "business-automation"
  name_suffix = random_id.suffix.hex
  
  # Resource names
  bucket_name            = "${local.name_prefix}-${local.name_suffix}"
  sns_topic_name        = "${local.name_prefix}-notifications-${local.name_suffix}"
  lambda_function_name  = "${local.name_prefix}-task-processor-${local.name_suffix}"
  schedule_group_name   = "${local.name_prefix}-group-${local.name_suffix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = "BusinessAutomation"
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# ==============================================================================
# Data Sources
# ==============================================================================

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==============================================================================
# S3 Bucket for Report Storage
# ==============================================================================

# S3 bucket for storing reports and processed data
resource "aws_s3_bucket" "reports" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Purpose     = "BusinessReports"
    Description = "Storage for automated business reports and processed data"
  })
}

# Enable versioning for data protection
resource "aws_s3_bucket_versioning" "reports" {
  bucket = aws_s3_bucket.reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  depends_on = [aws_s3_bucket_versioning.reports]
  bucket     = aws_s3_bucket.reports.id

  rule {
    id     = "business_reports_lifecycle"
    status = "Enabled"

    # Archive old reports to Intelligent Tiering after 30 days
    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }

    # Archive to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete old versions after 365 days
    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# ==============================================================================
# SNS Topic for Notifications
# ==============================================================================

# SNS topic for business notifications
resource "aws_sns_topic" "notifications" {
  name = local.sns_topic_name

  # Enable encryption at rest
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.common_tags, {
    Name        = local.sns_topic_name
    Purpose     = "BusinessNotifications"
    Description = "Notifications for automated business task completion"
  })
}

# SNS topic policy for secure access
resource "aws_sns_topic_policy" "notifications" {
  arn = aws_sns_topic.notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_execution.arn
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.notifications.arn
      }
    ]
  })
}

# Email subscription (requires manual confirmation)
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==============================================================================
# IAM Roles and Policies
# ==============================================================================

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
  name = "${local.name_prefix}-lambda-role-${local.name_suffix}"

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
    Name        = "${local.name_prefix}-lambda-role-${local.name_suffix}"
    Purpose     = "LambdaExecution"
    Description = "IAM role for business automation Lambda function"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for S3 and SNS access
resource "aws_iam_role_policy" "lambda_permissions" {
  name = "${local.name_prefix}-lambda-policy-${local.name_suffix}"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.reports.arn,
          "${aws_s3_bucket.reports.arn}/*"
        ]
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

# EventBridge Scheduler execution role
resource "aws_iam_role" "scheduler_execution" {
  name = "${local.name_prefix}-scheduler-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-scheduler-role-${local.name_suffix}"
    Purpose     = "SchedulerExecution"
    Description = "IAM role for EventBridge Scheduler to invoke Lambda"
  })
}

# Policy for Lambda invocation
resource "aws_iam_role_policy" "scheduler_permissions" {
  name = "${local.name_prefix}-scheduler-policy-${local.name_suffix}"
  role = aws_iam_role.scheduler_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.business_task_processor.arn
      }
    ]
  })
}

# ==============================================================================
# Lambda Function
# ==============================================================================

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/business-task-processor.zip"
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      bucket_name = aws_s3_bucket.reports.bucket
      topic_arn   = aws_sns_topic.notifications.arn
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for business task processing
resource "aws_lambda_function" "business_task_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 60
  memory_size     = 256
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.reports.bucket
      TOPIC_ARN   = aws_sns_topic.notifications.arn
    }
  }

  # Enable enhanced monitoring
  tracing_config {
    mode = "Active"
  }

  tags = merge(local.common_tags, {
    Name        = local.lambda_function_name
    Purpose     = "BusinessTaskProcessor"
    Description = "Processes automated business tasks"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_permissions,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "/aws/lambda/${local.lambda_function_name}"
    Purpose     = "LambdaLogs"
    Description = "CloudWatch logs for business task processor Lambda"
  })
}

# ==============================================================================
# EventBridge Scheduler
# ==============================================================================

# Schedule group for organizing business automation schedules
resource "aws_scheduler_schedule_group" "business_automation" {
  name = local.schedule_group_name

  tags = merge(local.common_tags, {
    Name        = local.schedule_group_name
    Purpose     = "BusinessAutomation"
    Description = "Schedule group for automated business tasks"
  })
}

# Daily report schedule (runs at 9 AM every day)
resource "aws_scheduler_schedule" "daily_reports" {
  name                         = "daily-report-schedule"
  group_name                   = aws_scheduler_schedule_group.business_automation.name
  description                  = "Daily business report generation"
  schedule_expression          = var.daily_report_schedule
  schedule_expression_timezone = var.timezone
  state                        = var.schedules_enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.business_task_processor.arn
    role_arn = aws_iam_role.scheduler_execution.arn
    input    = jsonencode({
      task_type = "report"
    })

    # Retry configuration
    retry_policy {
      maximum_retry_attempts        = 3
      maximum_event_age_in_seconds = 3600
    }
  }
}

# Hourly data processing schedule
resource "aws_scheduler_schedule" "hourly_processing" {
  count                        = var.enable_hourly_processing ? 1 : 0
  name                         = "hourly-data-processing"
  group_name                   = aws_scheduler_schedule_group.business_automation.name
  description                  = "Hourly business data processing"
  schedule_expression          = var.hourly_processing_schedule
  state                        = var.schedules_enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.business_task_processor.arn
    role_arn = aws_iam_role.scheduler_execution.arn
    input    = jsonencode({
      task_type = "data_processing"
    })

    # Retry configuration
    retry_policy {
      maximum_retry_attempts        = 2
      maximum_event_age_in_seconds = 1800
    }
  }
}

# Weekly notification schedule (runs every Monday at 10 AM)
resource "aws_scheduler_schedule" "weekly_notifications" {
  count                        = var.enable_weekly_notifications ? 1 : 0
  name                         = "weekly-notification-schedule"
  group_name                   = aws_scheduler_schedule_group.business_automation.name
  description                  = "Weekly business status notifications"
  schedule_expression          = var.weekly_notification_schedule
  schedule_expression_timezone = var.timezone
  state                        = var.schedules_enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.business_task_processor.arn
    role_arn = aws_iam_role.scheduler_execution.arn
    input    = jsonencode({
      task_type = "notification"
    })

    # Retry configuration
    retry_policy {
      maximum_retry_attempts        = 1
      maximum_event_age_in_seconds = 900
    }
  }
}

# ==============================================================================
# CloudWatch Alarms for Monitoring
# ==============================================================================

# Lambda error rate alarm
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "${local.lambda_function_name}-errors"
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
    FunctionName = aws_lambda_function.business_task_processor.function_name
  }

  tags = local.common_tags
}

# Lambda duration alarm
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "${local.lambda_function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = "30000" # 30 seconds
  alarm_description   = "This metric monitors lambda duration"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.business_task_processor.function_name
  }

  tags = local.common_tags
}