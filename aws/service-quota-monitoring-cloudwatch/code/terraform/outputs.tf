# Outputs for AWS Service Quota Monitoring Infrastructure
# These outputs provide important information about the created resources

#------------------------------------------------------------------------------
# SNS Topic Information
#------------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of the SNS topic for quota alerts"
  value       = aws_sns_topic.quota_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for quota alerts"
  value       = aws_sns_topic.quota_alerts.name
}

output "primary_notification_email" {
  description = "Primary email address receiving quota notifications"
  value       = var.notification_email
  sensitive   = true
}

#------------------------------------------------------------------------------
# CloudWatch Alarm Information
#------------------------------------------------------------------------------

output "quota_alarm_names" {
  description = "Names of all created CloudWatch alarms for quota monitoring"
  value       = [for alarm in aws_cloudwatch_metric_alarm.service_quota_alarms : alarm.alarm_name]
}

output "quota_alarm_arns" {
  description = "ARNs of all created CloudWatch alarms for quota monitoring"
  value       = [for alarm in aws_cloudwatch_metric_alarm.service_quota_alarms : alarm.arn]
}

output "monitored_services_summary" {
  description = "Summary of monitored services and their configurations"
  value = {
    for service_key, service in var.monitored_services : service_key => {
      service_code    = service.service_code
      quota_code      = service.quota_code
      quota_name      = service.quota_name
      alarm_name      = service.alarm_name
      threshold       = "${var.quota_threshold_percentage}%"
      alarm_arn       = aws_cloudwatch_metric_alarm.service_quota_alarms[service_key].arn
    }
  }
}

#------------------------------------------------------------------------------
# CloudWatch Dashboard Information
#------------------------------------------------------------------------------

output "dashboard_url" {
  description = "URL to access the CloudWatch dashboard for quota monitoring"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.service_quotas.dashboard_name}"
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.service_quotas.dashboard_name
}

#------------------------------------------------------------------------------
# Test Resources (if enabled)
#------------------------------------------------------------------------------

output "test_alarm_name" {
  description = "Name of the test alarm (if enabled)"
  value       = var.enable_test_alarms ? aws_cloudwatch_metric_alarm.test_alarm[0].alarm_name : null
}

output "test_alarm_arn" {
  description = "ARN of the test alarm (if enabled)"
  value       = var.enable_test_alarms ? aws_cloudwatch_metric_alarm.test_alarm[0].arn : null
}

#------------------------------------------------------------------------------
# Configuration Information
#------------------------------------------------------------------------------

output "monitoring_configuration" {
  description = "Current monitoring configuration settings"
  value = {
    aws_region                = var.aws_region
    environment              = var.environment
    quota_threshold_percentage = var.quota_threshold_percentage
    alarm_evaluation_periods = var.alarm_evaluation_periods
    metric_period_seconds    = var.metric_period_seconds
    treat_missing_data       = var.treat_missing_data
    enable_alarm_actions     = var.enable_alarm_actions
    monitored_services_count = length(var.monitored_services)
  }
}

#------------------------------------------------------------------------------
# AWS Account and Region Information
#------------------------------------------------------------------------------

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = data.aws_region.current.name
}

#------------------------------------------------------------------------------
# Resource Tags
#------------------------------------------------------------------------------

output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
  sensitive   = true
}

#------------------------------------------------------------------------------
# IAM Role Information (for future enhancements)
#------------------------------------------------------------------------------

output "monitoring_role_arn" {
  description = "ARN of the IAM role for quota monitoring automation"
  value       = aws_iam_role.quota_monitoring_role.arn
}

output "monitoring_role_name" {
  description = "Name of the IAM role for quota monitoring automation"
  value       = aws_iam_role.quota_monitoring_role.name
}

#------------------------------------------------------------------------------
# Validation and Testing Information
#------------------------------------------------------------------------------

output "validation_commands" {
  description = "AWS CLI commands to validate the deployment"
  value = {
    check_sns_topic = "aws sns get-topic-attributes --topic-arn ${aws_sns_topic.quota_alerts.arn}"
    list_subscriptions = "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.quota_alerts.arn}"
    describe_alarms = "aws cloudwatch describe-alarms --alarm-names ${join(" ", [for alarm in aws_cloudwatch_metric_alarm.service_quota_alarms : alarm.alarm_name])}"
    view_dashboard = "aws cloudwatch get-dashboard --dashboard-name ${aws_cloudwatch_dashboard.service_quotas.dashboard_name}"
  }
}

output "test_alarm_command" {
  description = "Command to test alarm notifications (if test alarm is enabled)"
  value = var.enable_test_alarms ? "aws cloudwatch set-alarm-state --alarm-name ${aws_cloudwatch_metric_alarm.test_alarm[0].alarm_name} --state-value ALARM --state-reason 'Testing notification system'" : "Test alarm not enabled. Set enable_test_alarms = true to create test alarm."
}

#------------------------------------------------------------------------------
# Cost Optimization Information
#------------------------------------------------------------------------------

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the monitoring solution"
  value = {
    cloudwatch_alarms = "$${length(var.monitored_services) * 0.10} (${length(var.monitored_services)} alarms × $0.10)"
    sns_notifications = "$0.50-$2.00 (depends on notification volume)"
    cloudwatch_dashboard = "$3.00 (1 dashboard)"
    total_estimated = "$${(length(var.monitored_services) * 0.10) + 3.00 + 1.25} (approximate)"
    note = "Costs may vary based on actual usage and AWS pricing changes"
  }
}

#------------------------------------------------------------------------------
# Next Steps and Enhancement Suggestions
#------------------------------------------------------------------------------

output "next_steps" {
  description = "Suggested next steps and enhancements"
  value = {
    confirm_email_subscription = "Check your email (${var.notification_email}) and confirm the SNS subscription"
    test_notifications = var.enable_test_alarms ? "Use the test_alarm_command output to test notifications" : "Set enable_test_alarms = true and re-apply to enable testing"
    monitor_dashboard = "Access the CloudWatch dashboard using the dashboard_url output"
    add_more_quotas = "Review monitored_services variable to add additional service quotas"
    automation_enhancement = "Consider implementing automated quota increase requests using the created IAM role"
    multi_region = "Deploy to additional regions for comprehensive coverage"
  }
}