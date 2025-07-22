# =====================================================
# Simple Business Notifications with EventBridge Scheduler and SNS
# =====================================================
# This Terraform configuration creates a serverless business notification
# system using EventBridge Scheduler and SNS for automated, reliable
# message delivery on predefined schedules.

# =====================================================
# Data Sources
# =====================================================

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate unique suffix for resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# =====================================================
# SNS Topic and Subscriptions
# =====================================================

# Create SNS topic for business notifications
resource "aws_sns_topic" "business_notifications" {
  name         = "${var.topic_name_prefix}-${random_id.suffix.hex}"
  display_name = var.sns_display_name

  # Enable server-side encryption
  kms_master_key_id = "alias/aws/sns"

  # Delivery policy for reliable message delivery
  delivery_policy = jsonencode({
    http = {
      defaultHealthyRetryPolicy = {
        minDelayTarget     = 20
        maxDelayTarget     = 20
        numRetries         = 3
        numMaxDelayRetries = 0
        numMinDelayRetries = 0
        numNoDelayRetries  = 0
        backoffFunction    = "linear"
      }
      disableSubscriptionOverrides = false
      defaultThrottlePolicy = {
        maxReceivesPerSecond = 1
      }
    }
  })

  tags = merge(var.common_tags, {
    Name        = "${var.topic_name_prefix}-${random_id.suffix.hex}"
    Purpose     = "BusinessNotifications"
    Environment = var.environment
  })
}

# Create email subscription for notifications
resource "aws_sns_topic_subscription" "email_notification" {
  count                = length(var.notification_emails) > 0 ? length(var.notification_emails) : 0
  topic_arn            = aws_sns_topic.business_notifications.arn
  protocol             = "email"
  endpoint             = var.notification_emails[count.index]
  confirmation_timeout_in_minutes = 5

  # Optional: Filter policy to receive only specific message attributes
  filter_policy = var.email_filter_policy != null ? jsonencode(var.email_filter_policy) : null
}

# Create SMS subscription for urgent notifications (optional)
resource "aws_sns_topic_subscription" "sms_notification" {
  count     = length(var.notification_phone_numbers) > 0 ? length(var.notification_phone_numbers) : 0
  topic_arn = aws_sns_topic.business_notifications.arn
  protocol  = "sms"
  endpoint  = var.notification_phone_numbers[count.index]

  # Filter policy for SMS to receive only urgent notifications
  filter_policy = jsonencode({
    priority = ["urgent", "high"]
  })
}

# Create SQS queue subscription for system integration (optional)
resource "aws_sqs_queue" "notification_queue" {
  count                     = var.enable_sqs_integration ? 1 : 0
  name                      = "${var.topic_name_prefix}-queue-${random_id.suffix.hex}"
  message_retention_seconds = 1209600 # 14 days

  # Dead letter queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notification_dlq[0].arn
    maxReceiveCount     = 3
  })

  tags = merge(var.common_tags, {
    Name = "${var.topic_name_prefix}-queue-${random_id.suffix.hex}"
  })
}

# Dead letter queue for failed message processing
resource "aws_sqs_queue" "notification_dlq" {
  count                     = var.enable_sqs_integration ? 1 : 0
  name                      = "${var.topic_name_prefix}-dlq-${random_id.suffix.hex}"
  message_retention_seconds = 1209600 # 14 days

  tags = merge(var.common_tags, {
    Name = "${var.topic_name_prefix}-dlq-${random_id.suffix.hex}"
  })
}

# SQS subscription to SNS topic
resource "aws_sns_topic_subscription" "sqs_notification" {
  count     = var.enable_sqs_integration ? 1 : 0
  topic_arn = aws_sns_topic.business_notifications.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.notification_queue[0].arn
}

# SQS queue policy to allow SNS to send messages
resource "aws_sqs_queue_policy" "notification_queue_policy" {
  count     = var.enable_sqs_integration ? 1 : 0
  queue_url = aws_sqs_queue.notification_queue[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "sqspolicy"
    Statement = [
      {
        Sid    = "AllowSNSPublish"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.notification_queue[0].arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.business_notifications.arn
          }
        }
      }
    ]
  })
}

# =====================================================
# IAM Role and Policies for EventBridge Scheduler
# =====================================================

# IAM trust policy document for EventBridge Scheduler
data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# IAM role for EventBridge Scheduler execution
resource "aws_iam_role" "scheduler_execution_role" {
  name               = "${var.scheduler_role_prefix}-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json
  description        = "Execution role for EventBridge Scheduler to publish SNS messages"

  tags = merge(var.common_tags, {
    Name = "${var.scheduler_role_prefix}-${random_id.suffix.hex}"
  })
}

# IAM policy document for SNS publishing permissions
data "aws_iam_policy_document" "sns_publish_policy" {
  statement {
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [aws_sns_topic.business_notifications.arn]
  }
}

# IAM policy for SNS publishing
resource "aws_iam_policy" "sns_publish_policy" {
  name        = "${var.scheduler_role_prefix}-sns-policy-${random_id.suffix.hex}"
  description = "Policy allowing EventBridge Scheduler to publish messages to SNS topic"
  policy      = data.aws_iam_policy_document.sns_publish_policy.json

  tags = var.common_tags
}

# Attach SNS publishing policy to the scheduler role
resource "aws_iam_role_policy_attachment" "scheduler_sns_policy" {
  role       = aws_iam_role.scheduler_execution_role.name
  policy_arn = aws_iam_policy.sns_publish_policy.arn
}

# =====================================================
# EventBridge Scheduler Resources
# =====================================================

# Create schedule group for organizing business notifications
resource "aws_scheduler_schedule_group" "business_schedules" {
  name        = "${var.schedule_group_prefix}-${random_id.suffix.hex}"
  description = "Schedule group for automated business notifications"

  tags = merge(var.common_tags, {
    Name    = "${var.schedule_group_prefix}-${random_id.suffix.hex}"
    Purpose = "BusinessNotifications"
  })
}

# Daily business report schedule (9 AM on weekdays)
resource "aws_scheduler_schedule" "daily_business_report" {
  name                         = "daily-business-report"
  group_name                   = aws_scheduler_schedule_group.business_schedules.name
  description                  = "Daily business report notification sent on weekdays at 9 AM"
  schedule_expression          = var.daily_schedule_expression
  schedule_expression_timezone = var.schedule_timezone
  state                        = var.schedules_enabled ? "ENABLED" : "DISABLED"

  # Flexible time window for delivery optimization
  flexible_time_window {
    mode                      = "FLEXIBLE"
    maximum_window_in_minutes = var.daily_flexible_window_minutes
  }

  # SNS target configuration
  target {
    arn      = aws_sns_topic.business_notifications.arn
    role_arn = aws_iam_role.scheduler_execution_role.arn

    sns_parameters {
      subject = var.daily_notification_subject
      message = var.daily_notification_message
    }

    # Retry configuration for reliability
    retry_policy {
      maximum_retry_attempts       = 3
      maximum_event_age_in_seconds = 3600
    }

    # Dead letter queue for failed deliveries (optional)
    dead_letter_config {
      arn = var.enable_dlq ? aws_sqs_queue.notification_dlq[0].arn : null
    }
  }
}

# Weekly summary schedule (Monday 8 AM)
resource "aws_scheduler_schedule" "weekly_summary" {
  name                         = "weekly-summary"
  group_name                   = aws_scheduler_schedule_group.business_schedules.name
  description                  = "Weekly business summary notification sent every Monday at 8 AM"
  schedule_expression          = var.weekly_schedule_expression
  schedule_expression_timezone = var.schedule_timezone
  state                        = var.schedules_enabled ? "ENABLED" : "DISABLED"

  # Flexible time window for delivery optimization
  flexible_time_window {
    mode                      = "FLEXIBLE"
    maximum_window_in_minutes = var.weekly_flexible_window_minutes
  }

  # SNS target configuration
  target {
    arn      = aws_sns_topic.business_notifications.arn
    role_arn = aws_iam_role.scheduler_execution_role.arn

    sns_parameters {
      subject = var.weekly_notification_subject
      message = var.weekly_notification_message
    }

    # Retry configuration for reliability
    retry_policy {
      maximum_retry_attempts       = 3
      maximum_event_age_in_seconds = 3600
    }

    # Dead letter queue for failed deliveries (optional)
    dead_letter_config {
      arn = var.enable_dlq ? aws_sqs_queue.notification_dlq[0].arn : null
    }
  }
}

# Monthly reminder schedule (1st of each month at 10 AM)
resource "aws_scheduler_schedule" "monthly_reminder" {
  name                         = "monthly-reminder"
  group_name                   = aws_scheduler_schedule_group.business_schedules.name
  description                  = "Monthly business reminder notification sent on the 1st of each month at 10 AM"
  schedule_expression          = var.monthly_schedule_expression
  schedule_expression_timezone = var.schedule_timezone
  state                        = var.schedules_enabled ? "ENABLED" : "DISABLED"

  # No flexible time window for precise monthly timing
  flexible_time_window {
    mode = "OFF"
  }

  # SNS target configuration
  target {
    arn      = aws_sns_topic.business_notifications.arn
    role_arn = aws_iam_role.scheduler_execution_role.arn

    sns_parameters {
      subject = var.monthly_notification_subject
      message = var.monthly_notification_message
    }

    # Retry configuration for reliability
    retry_policy {
      maximum_retry_attempts       = 3
      maximum_event_age_in_seconds = 3600
    }

    # Dead letter queue for failed deliveries (optional)
    dead_letter_config {
      arn = var.enable_dlq ? aws_sqs_queue.notification_dlq[0].arn : null
    }
  }
}

# =====================================================
# CloudWatch Log Groups for Monitoring (Optional)
# =====================================================

# Log group for EventBridge Scheduler execution logs
resource "aws_cloudwatch_log_group" "scheduler_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/events/scheduler/${aws_scheduler_schedule_group.business_schedules.name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "scheduler-logs-${random_id.suffix.hex}"
  })
}

# CloudWatch Log Stream for each schedule
resource "aws_cloudwatch_log_stream" "daily_schedule_logs" {
  count          = var.enable_cloudwatch_logs ? 1 : 0
  name           = "daily-business-report"
  log_group_name = aws_cloudwatch_log_group.scheduler_logs[0].name
}

resource "aws_cloudwatch_log_stream" "weekly_schedule_logs" {
  count          = var.enable_cloudwatch_logs ? 1 : 0
  name           = "weekly-summary"
  log_group_name = aws_cloudwatch_log_group.scheduler_logs[0].name
}

resource "aws_cloudwatch_log_stream" "monthly_schedule_logs" {
  count          = var.enable_cloudwatch_logs ? 1 : 0
  name           = "monthly-reminder"
  log_group_name = aws_cloudwatch_log_group.scheduler_logs[0].name
}