# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique resource names
  project_id           = "${var.project_name}-${random_id.suffix.hex}"
  lambda_function_name = "${local.project_id}-email-processor"
  event_bus_name       = var.enable_eventbridge_custom_bus ? (var.eventbridge_bus_name != "" ? var.eventbridge_bus_name : "${local.project_id}-event-bus") : "default"
  s3_bucket_name       = "${local.project_id}-lambda-deployment"

  # Merge additional tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "automated-email-notification-systems-ses-lambda-eventbridge"
    },
    var.additional_tags
  )
}

# ============================================================================
# S3 Bucket for Lambda Deployment Package
# ============================================================================

resource "aws_s3_bucket" "lambda_deployment" {
  bucket = local.s3_bucket_name

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "lambda_deployment" {
  bucket = aws_s3_bucket.lambda_deployment.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_deployment" {
  bucket = aws_s3_bucket.lambda_deployment.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "lambda_deployment" {
  bucket = aws_s3_bucket.lambda_deployment.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# SES Configuration
# ============================================================================

# Verify sender email address
resource "aws_ses_email_identity" "sender" {
  count = var.verify_email_addresses ? 1 : 0
  email = var.sender_email

  tags = local.common_tags
}

# Verify recipient email address (for testing in sandbox mode)
resource "aws_ses_email_identity" "recipient" {
  count = var.verify_email_addresses && var.recipient_email != "" ? 1 : 0
  email = var.recipient_email

  tags = local.common_tags
}

# Create SES email template
resource "aws_ses_template" "notification_template" {
  name    = var.email_template_name
  subject = var.email_template_subject
  html    = var.email_template_html
  text    = var.email_template_text

  tags = local.common_tags
}

# ============================================================================
# IAM Roles and Policies
# ============================================================================

# Lambda execution role
resource "aws_iam_role" "lambda_execution_role" {
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

  tags = local.common_tags
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SES permissions policy
resource "aws_iam_policy" "ses_permissions" {
  name        = "${local.project_id}-ses-policy"
  description = "IAM policy for SES email sending permissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail",
          "ses:SendTemplatedEmail"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach SES permissions to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_ses_permissions" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.ses_permissions.arn
}

# ============================================================================
# Lambda Function
# ============================================================================

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      sender_email      = var.sender_email
      template_name     = var.email_template_name
      default_recipient = var.recipient_email != "" ? var.recipient_email : "default-recipient@example.com"
    })
    filename = "lambda_function.py"
  }
}

# Upload Lambda package to S3
resource "aws_s3_object" "lambda_package" {
  bucket = aws_s3_bucket.lambda_deployment.id
  key    = "lambda_function.zip"
  source = data.archive_file.lambda_zip.output_path
  etag   = data.archive_file.lambda_zip.output_md5

  tags = local.common_tags
}

# Lambda function
resource "aws_lambda_function" "email_processor" {
  function_name = local.lambda_function_name
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "lambda_function.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  memory_size  = var.lambda_memory_size

  s3_bucket = aws_s3_bucket.lambda_deployment.id
  s3_key    = aws_s3_object.lambda_package.key

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  description = "Email notification processor for event-driven system"

  environment {
    variables = {
      SENDER_EMAIL  = var.sender_email
      TEMPLATE_NAME = var.email_template_name
      PROJECT_NAME  = var.project_name
      ENVIRONMENT   = var.environment
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_ses_permissions,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = local.common_tags
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14

  tags = local.common_tags
}

# ============================================================================
# EventBridge Configuration
# ============================================================================

# Custom EventBridge bus (optional)
resource "aws_cloudwatch_event_bus" "custom_bus" {
  count = var.enable_eventbridge_custom_bus ? 1 : 0
  name  = local.event_bus_name

  tags = local.common_tags
}

# EventBridge rule for email notifications
resource "aws_cloudwatch_event_rule" "email_notification_rule" {
  name           = "${local.project_id}-email-rule"
  description    = "Route email notification requests to Lambda processor"
  event_bus_name = var.enable_eventbridge_custom_bus ? aws_cloudwatch_event_bus.custom_bus[0].name : "default"

  event_pattern = jsonencode({
    source       = ["custom.application"]
    detail-type  = ["Email Notification Request"]
  })

  tags = local.common_tags
}

# EventBridge target for email notifications
resource "aws_cloudwatch_event_target" "email_notification_target" {
  rule           = aws_cloudwatch_event_rule.email_notification_rule.name
  target_id      = "EmailProcessorTarget"
  arn            = aws_lambda_function.email_processor.arn
  event_bus_name = var.enable_eventbridge_custom_bus ? aws_cloudwatch_event_bus.custom_bus[0].name : "default"
}

# Lambda permission for EventBridge email rule
resource "aws_lambda_permission" "allow_eventbridge_email" {
  statement_id  = "AllowExecutionFromEventBridgeEmail"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.email_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.email_notification_rule.arn
}

# EventBridge rule for priority alerts
resource "aws_cloudwatch_event_rule" "priority_alert_rule" {
  name           = "${local.project_id}-priority-rule"
  description    = "Handle high priority alerts"
  event_bus_name = var.enable_eventbridge_custom_bus ? aws_cloudwatch_event_bus.custom_bus[0].name : "default"

  event_pattern = jsonencode({
    source      = ["custom.application"]
    detail-type = ["Priority Alert"]
    detail = {
      priority = ["high", "critical"]
    }
  })

  tags = local.common_tags
}

# EventBridge target for priority alerts
resource "aws_cloudwatch_event_target" "priority_alert_target" {
  rule           = aws_cloudwatch_event_rule.priority_alert_rule.name
  target_id      = "PriorityAlertTarget"
  arn            = aws_lambda_function.email_processor.arn
  event_bus_name = var.enable_eventbridge_custom_bus ? aws_cloudwatch_event_bus.custom_bus[0].name : "default"
}

# Lambda permission for EventBridge priority rule
resource "aws_lambda_permission" "allow_eventbridge_priority" {
  statement_id  = "AllowExecutionFromEventBridgePriority"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.email_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.priority_alert_rule.arn
}

# Scheduled EventBridge rule for daily reports
resource "aws_cloudwatch_event_rule" "daily_report_rule" {
  count               = var.enable_scheduled_emails ? 1 : 0
  name                = "${local.project_id}-daily-report"
  description         = "Send daily email reports"
  schedule_expression = var.scheduled_email_cron

  tags = local.common_tags
}

# EventBridge target for scheduled reports
resource "aws_cloudwatch_event_target" "daily_report_target" {
  count     = var.enable_scheduled_emails ? 1 : 0
  rule      = aws_cloudwatch_event_rule.daily_report_rule[0].name
  target_id = "DailyReportTarget"
  arn       = aws_lambda_function.email_processor.arn

  input = jsonencode({
    source      = "scheduled.reports"
    detail-type = "Daily Report"
    detail = {
      emailConfig = {
        recipient = var.recipient_email != "" ? var.recipient_email : "reports@example.com"
        subject   = "Daily Report - ${formatdate("YYYY-MM-DD", timestamp())}"
      }
      title   = "Daily System Report"
      message = "This is your scheduled daily report from the email automation system."
    }
  })
}

# Lambda permission for scheduled rule
resource "aws_lambda_permission" "allow_eventbridge_scheduled" {
  count         = var.enable_scheduled_emails ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridgeScheduled"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.email_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_report_rule[0].arn
}

# ============================================================================
# CloudWatch Monitoring and Alarms
# ============================================================================

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.project_id}-lambda-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.lambda_error_threshold
  alarm_description   = "This metric monitors Lambda function errors"

  dimensions = {
    FunctionName = aws_lambda_function.email_processor.function_name
  }

  tags = local.common_tags
}

# CloudWatch alarm for SES bounces
resource "aws_cloudwatch_metric_alarm" "ses_bounces" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.project_id}-ses-bounces"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "Bounce"
  namespace           = "AWS/SES"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.ses_bounce_threshold
  alarm_description   = "This metric monitors SES bounce rate"

  tags = local.common_tags
}

# Custom metric filter for Lambda logs
resource "aws_cloudwatch_log_metric_filter" "email_processing_errors" {
  name           = "EmailProcessingErrors"
  log_group_name = aws_cloudwatch_log_group.lambda_logs.name
  pattern        = "ERROR"

  metric_transformation {
    name      = "EmailProcessingErrors"
    namespace = "CustomMetrics"
    value     = "1"
  }
}

# CloudWatch alarm for custom error metric
resource "aws_cloudwatch_metric_alarm" "email_processing_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.project_id}-email-processing-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "EmailProcessingErrors"
  namespace           = "CustomMetrics"
  period              = "300"
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "This metric monitors email processing errors from Lambda logs"

  tags = local.common_tags
}