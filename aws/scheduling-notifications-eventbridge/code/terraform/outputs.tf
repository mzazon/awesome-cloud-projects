# =====================================================
# Outputs for Simple Business Notifications Infrastructure
# =====================================================
# This file defines outputs that provide important information
# about the deployed notification infrastructure resources.

# =====================================================
# SNS Topic Outputs
# =====================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for business notifications"
  value       = aws_sns_topic.business_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for business notifications"
  value       = aws_sns_topic.business_notifications.name
}

output "sns_topic_display_name" {
  description = "Display name of the SNS topic"
  value       = aws_sns_topic.business_notifications.display_name
}

output "sns_topic_id" {
  description = "ID of the SNS topic"
  value       = aws_sns_topic.business_notifications.id
}

# =====================================================
# SNS Subscription Outputs
# =====================================================

output "email_subscription_arns" {
  description = "ARNs of email subscriptions to the SNS topic"
  value       = length(aws_sns_topic_subscription.email_notification) > 0 ? aws_sns_topic_subscription.email_notification[*].arn : []
}

output "sms_subscription_arns" {
  description = "ARNs of SMS subscriptions to the SNS topic"
  value       = length(aws_sns_topic_subscription.sms_notification) > 0 ? aws_sns_topic_subscription.sms_notification[*].arn : []
}

output "email_subscription_count" {
  description = "Number of email subscriptions created"
  value       = length(aws_sns_topic_subscription.email_notification)
}

output "sms_subscription_count" {
  description = "Number of SMS subscriptions created"
  value       = length(aws_sns_topic_subscription.sms_notification)
}

# =====================================================
# SQS Queue Outputs (if enabled)
# =====================================================

output "sqs_queue_arn" {
  description = "ARN of the SQS queue for notification processing"
  value       = var.enable_sqs_integration && length(aws_sqs_queue.notification_queue) > 0 ? aws_sqs_queue.notification_queue[0].arn : null
}

output "sqs_queue_url" {
  description = "URL of the SQS queue for notification processing"
  value       = var.enable_sqs_integration && length(aws_sqs_queue.notification_queue) > 0 ? aws_sqs_queue.notification_queue[0].url : null
}

output "sqs_dlq_arn" {
  description = "ARN of the SQS dead letter queue"
  value       = var.enable_sqs_integration && length(aws_sqs_queue.notification_dlq) > 0 ? aws_sqs_queue.notification_dlq[0].arn : null
}

output "sqs_dlq_url" {
  description = "URL of the SQS dead letter queue"
  value       = var.enable_sqs_integration && length(aws_sqs_queue.notification_dlq) > 0 ? aws_sqs_queue.notification_dlq[0].url : null
}

# =====================================================
# IAM Role and Policy Outputs
# =====================================================

output "scheduler_execution_role_arn" {
  description = "ARN of the IAM role used by EventBridge Scheduler"
  value       = aws_iam_role.scheduler_execution_role.arn
}

output "scheduler_execution_role_name" {
  description = "Name of the IAM role used by EventBridge Scheduler"
  value       = aws_iam_role.scheduler_execution_role.name
}

output "sns_publish_policy_arn" {
  description = "ARN of the IAM policy for SNS publishing"
  value       = aws_iam_policy.sns_publish_policy.arn
}

output "sns_publish_policy_name" {
  description = "Name of the IAM policy for SNS publishing"
  value       = aws_iam_policy.sns_publish_policy.name
}

# =====================================================
# EventBridge Scheduler Outputs
# =====================================================

output "schedule_group_name" {
  description = "Name of the EventBridge Scheduler schedule group"
  value       = aws_scheduler_schedule_group.business_schedules.name
}

output "schedule_group_arn" {
  description = "ARN of the EventBridge Scheduler schedule group"
  value       = aws_scheduler_schedule_group.business_schedules.arn
}

output "daily_schedule_arn" {
  description = "ARN of the daily business report schedule"
  value       = aws_scheduler_schedule.daily_business_report.arn
}

output "weekly_schedule_arn" {
  description = "ARN of the weekly summary schedule"
  value       = aws_scheduler_schedule.weekly_summary.arn
}

output "monthly_schedule_arn" {
  description = "ARN of the monthly reminder schedule"
  value       = aws_scheduler_schedule.monthly_reminder.arn
}

output "daily_schedule_name" {
  description = "Name of the daily business report schedule"
  value       = aws_scheduler_schedule.daily_business_report.name
}

output "weekly_schedule_name" {
  description = "Name of the weekly summary schedule"
  value       = aws_scheduler_schedule.weekly_summary.name
}

output "monthly_schedule_name" {
  description = "Name of the monthly reminder schedule"
  value       = aws_scheduler_schedule.monthly_reminder.name
}

# =====================================================
# Schedule Configuration Outputs
# =====================================================

output "schedule_expressions" {
  description = "Schedule expressions for all created schedules"
  value = {
    daily   = aws_scheduler_schedule.daily_business_report.schedule_expression
    weekly  = aws_scheduler_schedule.weekly_summary.schedule_expression
    monthly = aws_scheduler_schedule.monthly_reminder.schedule_expression
  }
}

output "schedule_timezones" {
  description = "Timezone settings for all schedules"
  value = {
    daily   = aws_scheduler_schedule.daily_business_report.schedule_expression_timezone
    weekly  = aws_scheduler_schedule.weekly_summary.schedule_expression_timezone
    monthly = aws_scheduler_schedule.monthly_reminder.schedule_expression_timezone
  }
}

output "schedule_states" {
  description = "Current state (ENABLED/DISABLED) of all schedules"
  value = {
    daily   = aws_scheduler_schedule.daily_business_report.state
    weekly  = aws_scheduler_schedule.weekly_summary.state
    monthly = aws_scheduler_schedule.monthly_reminder.state
  }
}

# =====================================================
# CloudWatch Logging Outputs
# =====================================================

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for scheduler logs"
  value       = var.enable_cloudwatch_logs && length(aws_cloudwatch_log_group.scheduler_logs) > 0 ? aws_cloudwatch_log_group.scheduler_logs[0].arn : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for scheduler logs"
  value       = var.enable_cloudwatch_logs && length(aws_cloudwatch_log_group.scheduler_logs) > 0 ? aws_cloudwatch_log_group.scheduler_logs[0].name : null
}

# =====================================================
# Resource Identifiers and Configuration
# =====================================================

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# =====================================================
# Cost and Resource Summary
# =====================================================

output "deployment_summary" {
  description = "Summary of deployed resources and estimated costs"
  value = {
    sns_topic_count           = 1
    email_subscriptions       = length(aws_sns_topic_subscription.email_notification)
    sms_subscriptions        = length(aws_sns_topic_subscription.sms_notification)
    sqs_queues               = var.enable_sqs_integration ? 2 : 0  # Main queue + DLQ
    scheduler_schedules      = 3  # Daily, weekly, monthly
    iam_roles               = 1
    iam_policies            = 1
    cloudwatch_log_groups   = var.enable_cloudwatch_logs ? 1 : 0
    estimated_monthly_cost  = "< $0.50 for typical business notification volumes"
  }
}

# =====================================================
# Notification Configuration Summary
# =====================================================

output "notification_configuration" {
  description = "Summary of notification configuration"
  value = {
    daily_notifications = {
      subject       = var.daily_notification_subject
      schedule      = var.daily_schedule_expression
      timezone      = var.schedule_timezone
      flexible_window = "${var.daily_flexible_window_minutes} minutes"
    }
    weekly_notifications = {
      subject       = var.weekly_notification_subject
      schedule      = var.weekly_schedule_expression
      timezone      = var.schedule_timezone
      flexible_window = "${var.weekly_flexible_window_minutes} minutes"
    }
    monthly_notifications = {
      subject       = var.monthly_notification_subject
      schedule      = var.monthly_schedule_expression
      timezone      = var.schedule_timezone
      flexible_window = "Fixed timing (no window)"
    }
  }
  sensitive = false
}

# =====================================================
# Validation and Testing Information
# =====================================================

output "testing_commands" {
  description = "AWS CLI commands for testing the notification system"
  value = {
    test_sns_publish = "aws sns publish --topic-arn ${aws_sns_topic.business_notifications.arn} --subject 'Test Notification' --message 'This is a test message to verify the notification system.'"
    list_subscriptions = "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.business_notifications.arn}"
    check_schedules = "aws scheduler list-schedules --group-name ${aws_scheduler_schedule_group.business_schedules.name}"
    verify_role = "aws iam get-role --role-name ${aws_iam_role.scheduler_execution_role.name}"
  }
}

# =====================================================
# Next Steps and Configuration Guidance
# =====================================================

output "next_steps" {
  description = "Next steps for configuring and using the notification system"
  value = [
    "1. Confirm email subscriptions by checking your inbox and clicking confirmation links",
    "2. Test the system by running: aws sns publish --topic-arn ${aws_sns_topic.business_notifications.arn} --subject 'Test' --message 'Test message'",
    "3. Monitor schedule executions in the AWS Console under EventBridge > Schedules",
    "4. Review CloudWatch logs for execution details and troubleshooting",
    "5. Customize notification content by updating the message variables",
    "6. Add additional subscribers using the AWS Console or Terraform variables"
  ]
}