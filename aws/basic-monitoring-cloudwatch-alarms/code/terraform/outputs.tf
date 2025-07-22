# =============================================================================
# Outputs for AWS CloudWatch Monitoring Infrastructure
# =============================================================================

# =============================================================================
# SNS Topic Information
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarm notifications"
  value       = aws_sns_topic.monitoring_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alarm notifications"
  value       = aws_sns_topic.monitoring_alerts.name
}

output "sns_topic_id" {
  description = "ID of the SNS topic for alarm notifications"
  value       = aws_sns_topic.monitoring_alerts.id
}

# =============================================================================
# SNS Subscription Information
# =============================================================================

output "email_subscription_arn" {
  description = "ARN of the email subscription to the SNS topic"
  value       = aws_sns_topic_subscription.email_alerts.arn
}

output "email_subscription_status" {
  description = "Status of the email subscription (PendingConfirmation until confirmed)"
  value       = aws_sns_topic_subscription.email_alerts.confirmation_was_authenticated
}

output "notification_email" {
  description = "Email address configured for alarm notifications"
  value       = var.notification_email
}

# =============================================================================
# CloudWatch Alarm Information
# =============================================================================

output "cpu_alarm_arn" {
  description = "ARN of the CPU utilization alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu_utilization.arn
}

output "cpu_alarm_name" {
  description = "Name of the CPU utilization alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu_utilization.alarm_name
}

output "response_time_alarm_arn" {
  description = "ARN of the response time alarm"
  value       = aws_cloudwatch_metric_alarm.high_response_time.arn
}

output "response_time_alarm_name" {
  description = "Name of the response time alarm"
  value       = aws_cloudwatch_metric_alarm.high_response_time.alarm_name
}

output "db_connections_alarm_arn" {
  description = "ARN of the database connections alarm"
  value       = aws_cloudwatch_metric_alarm.high_db_connections.arn
}

output "db_connections_alarm_name" {
  description = "Name of the database connections alarm"
  value       = aws_cloudwatch_metric_alarm.high_db_connections.alarm_name
}

# =============================================================================
# Alarm Configuration Summary
# =============================================================================

output "alarm_summary" {
  description = "Summary of all created alarms and their configurations"
  value = {
    cpu_utilization = {
      name               = aws_cloudwatch_metric_alarm.high_cpu_utilization.alarm_name
      threshold          = var.cpu_threshold
      evaluation_periods = var.cpu_alarm_evaluation_periods
      period             = var.alarm_period
    }
    response_time = {
      name               = aws_cloudwatch_metric_alarm.high_response_time.alarm_name
      threshold          = var.response_time_threshold
      evaluation_periods = var.response_time_alarm_evaluation_periods
      period             = var.alarm_period
    }
    database_connections = {
      name               = aws_cloudwatch_metric_alarm.high_db_connections.alarm_name
      threshold          = var.db_connections_threshold
      evaluation_periods = var.db_connections_alarm_evaluation_periods
      period             = var.alarm_period
    }
  }
}

# =============================================================================
# CloudWatch Dashboard Information
# =============================================================================

output "dashboard_url" {
  description = "URL to access the CloudWatch dashboard (if created)"
  value = var.create_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.monitoring_dashboard[0].dashboard_name}" : "Dashboard not created (create_dashboard = false)"
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard (if created)"
  value       = var.create_dashboard ? aws_cloudwatch_dashboard.monitoring_dashboard[0].dashboard_name : null
}

# =============================================================================
# AWS Account and Region Information
# =============================================================================

output "aws_account_id" {
  description = "AWS Account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources were created"
  value       = data.aws_region.current.name
}

# =============================================================================
# Resource Tags
# =============================================================================

output "resource_tags" {
  description = "Tags applied to all resources"
  value       = var.tags
}

# =============================================================================
# Cost Estimation Information
# =============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the monitoring infrastructure"
  value = {
    cloudwatch_alarms = {
      count = 3
      cost  = "$0.30 (3 alarms × $0.10 per alarm)"
    }
    sns_notifications = {
      first_1000_emails = "Free"
      additional_emails = "$2.00 per 100,000 emails"
    }
    dashboard = {
      count = var.create_dashboard ? 1 : 0
      cost  = var.create_dashboard ? "Free (up to 3 dashboards)" : "$0.00"
    }
    total_base_cost = "$0.30 per month (plus SNS overages if applicable)"
  }
}

# =============================================================================
# Validation Commands
# =============================================================================

output "validation_commands" {
  description = "CLI commands to validate the monitoring setup"
  value = {
    list_topics = "aws sns list-topics --query 'Topics[?contains(TopicArn, `${aws_sns_topic.monitoring_alerts.name}`)]'"
    list_subscriptions = "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.monitoring_alerts.arn}"
    list_alarms = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.high_cpu_utilization.alarm_name} ${aws_cloudwatch_metric_alarm.high_response_time.alarm_name} ${aws_cloudwatch_metric_alarm.high_db_connections.alarm_name}"
    test_alarm = "aws cloudwatch set-alarm-state --alarm-name ${aws_cloudwatch_metric_alarm.high_cpu_utilization.alarm_name} --state-value ALARM --state-reason 'Testing alarm notification'"
  }
}

# =============================================================================
# Cleanup Commands
# =============================================================================

output "cleanup_commands" {
  description = "CLI commands to clean up resources (alternative to terraform destroy)"
  value = {
    delete_alarms = "aws cloudwatch delete-alarms --alarm-names ${aws_cloudwatch_metric_alarm.high_cpu_utilization.alarm_name} ${aws_cloudwatch_metric_alarm.high_response_time.alarm_name} ${aws_cloudwatch_metric_alarm.high_db_connections.alarm_name}"
    delete_dashboard = var.create_dashboard ? "aws cloudwatch delete-dashboards --dashboard-names ${aws_cloudwatch_dashboard.monitoring_dashboard[0].dashboard_name}" : "No dashboard to delete"
    delete_topic = "aws sns delete-topic --topic-arn ${aws_sns_topic.monitoring_alerts.arn}"
  }
}

# =============================================================================
# Next Steps
# =============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Check your email (${var.notification_email}) and confirm the SNS subscription",
    "2. Test the alarm notification by running: ${local.test_alarm_command}",
    "3. Access the CloudWatch dashboard at: ${var.create_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.monitoring_dashboard[0].dashboard_name}" : "Dashboard not created"}",
    "4. Consider setting up additional alarms for Lambda functions, API Gateway, or other services",
    "5. Review and adjust alarm thresholds based on your application's normal behavior patterns"
  ]
}

# =============================================================================
# Local Values for Output Calculations
# =============================================================================

locals {
  test_alarm_command = "aws cloudwatch set-alarm-state --alarm-name ${aws_cloudwatch_metric_alarm.high_cpu_utilization.alarm_name} --state-value ALARM --state-reason 'Testing alarm notification'"
}