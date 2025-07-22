# ==============================================================================
# Outputs for Website Uptime Monitoring with Route 53 Health Checks
# ==============================================================================
# This file defines outputs that provide important information about the
# created resources for verification, integration, and management.

# ==============================================================================
# Route 53 Health Check Outputs
# ==============================================================================

output "health_check_id" {
  description = "The ID of the Route 53 health check"
  value       = aws_route53_health_check.website_uptime.id
}

output "health_check_arn" {
  description = "The Amazon Resource Name (ARN) of the Route 53 health check"
  value       = aws_route53_health_check.website_uptime.arn
}

output "health_check_fqdn" {
  description = "The fully qualified domain name being monitored"
  value       = aws_route53_health_check.website_uptime.fqdn
}

output "health_check_type" {
  description = "The type of health check (HTTP/HTTPS)"
  value       = aws_route53_health_check.website_uptime.type
}

output "health_check_regions" {
  description = "List of regions from which the health check is performed"
  value       = aws_route53_health_check.website_uptime.regions
}

output "health_check_status" {
  description = "The current status of the health check"
  value       = aws_route53_health_check.website_uptime.id
}

# ==============================================================================
# CloudWatch Alarm Outputs
# ==============================================================================

output "website_down_alarm_arn" {
  description = "The ARN of the website down CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.website_down.arn
}

output "website_down_alarm_name" {
  description = "The name of the website down CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.website_down.alarm_name
}

output "health_percentage_alarm_arn" {
  description = "The ARN of the health percentage CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.health_check_percentage.arn
}

output "health_percentage_alarm_name" {
  description = "The name of the health percentage CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.health_check_percentage.alarm_name
}

# ==============================================================================
# SNS Topic and Notification Outputs
# ==============================================================================

output "sns_topic_arn" {
  description = "The ARN of the SNS topic for uptime alerts"
  value       = aws_sns_topic.uptime_alerts.arn
}

output "sns_topic_name" {
  description = "The name of the SNS topic for uptime alerts"
  value       = aws_sns_topic.uptime_alerts.name
}

output "email_subscription_arn" {
  description = "The ARN of the email subscription (if configured)"
  value       = var.notification_email != "" ? aws_sns_topic_subscription.email_alerts[0].arn : null
}

output "email_subscription_confirmed" {
  description = "Whether the email subscription is confirmed (requires manual confirmation)"
  value       = var.notification_email != "" ? aws_sns_topic_subscription.email_alerts[0].confirmation_was_authenticated : null
}

# ==============================================================================
# CloudWatch Dashboard Outputs
# ==============================================================================

output "dashboard_name" {
  description = "The name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.uptime_monitoring.dashboard_name
}

output "dashboard_arn" {
  description = "The ARN of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.uptime_monitoring.dashboard_arn
}

output "dashboard_url" {
  description = "Direct URL to view the CloudWatch dashboard in AWS Console"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.uptime_monitoring.dashboard_name}"
}

# ==============================================================================
# Monitoring Configuration Outputs
# ==============================================================================

output "monitoring_configuration" {
  description = "Summary of the monitoring configuration"
  value = {
    website_url           = var.website_url
    health_check_path     = var.health_check_path
    failure_threshold     = var.failure_threshold
    request_interval      = var.request_interval
    alarm_evaluation_periods = var.alarm_evaluation_periods
    health_percentage_threshold = var.health_percentage_threshold
    monitoring_regions    = length(var.health_check_regions)
    notification_email    = var.notification_email != "" ? var.notification_email : "Not configured"
  }
}

# ==============================================================================
# Resource Summary Outputs
# ==============================================================================

output "monitoring_resources" {
  description = "Summary of all created monitoring resources"
  value = {
    health_checks = {
      primary_health_check_id = aws_route53_health_check.website_uptime.id
      health_check_arn       = aws_route53_health_check.website_uptime.arn
    }
    alarms = {
      website_down_alarm      = aws_cloudwatch_metric_alarm.website_down.arn
      health_percentage_alarm = aws_cloudwatch_metric_alarm.health_check_percentage.arn
    }
    notifications = {
      sns_topic_arn        = aws_sns_topic.uptime_alerts.arn
      email_subscription   = var.notification_email != "" ? aws_sns_topic_subscription.email_alerts[0].arn : "Not configured"
    }
    dashboard = {
      dashboard_name = aws_cloudwatch_dashboard.uptime_monitoring.dashboard_name
      dashboard_arn  = aws_cloudwatch_dashboard.uptime_monitoring.dashboard_arn
    }
  }
}

# ==============================================================================
# AWS Account and Region Information
# ==============================================================================

output "aws_account_id" {
  description = "The AWS account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "The AWS region where resources were created"
  value       = data.aws_region.current.name
}

# ==============================================================================
# Cost and Usage Information
# ==============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the monitoring setup (USD)"
  value = {
    route53_health_check = "$0.50 per health check"
    cloudwatch_alarms   = "$0.10 per alarm (2 alarms = $0.20)"
    sns_notifications   = "$0.50 per 1M email notifications"
    cloudwatch_dashboard = "$3.00 per dashboard"
    total_base_cost     = "~$4.20 per month (excluding notification volume)"
  }
}

# ==============================================================================
# Validation and Testing Outputs
# ==============================================================================

output "validation_commands" {
  description = "AWS CLI commands to validate the monitoring setup"
  value = {
    check_health_status = "aws route53 get-health-check --health-check-id ${aws_route53_health_check.website_uptime.id}"
    view_alarm_state    = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.website_down.alarm_name}"
    test_notification   = "aws cloudwatch set-alarm-state --alarm-name ${aws_cloudwatch_metric_alarm.website_down.alarm_name} --state-value ALARM --state-reason 'Testing notifications'"
    view_dashboard      = "aws cloudwatch get-dashboard --dashboard-name ${aws_cloudwatch_dashboard.uptime_monitoring.dashboard_name}"
  }
}

# ==============================================================================
# Integration Information
# ==============================================================================

output "integration_endpoints" {
  description = "Endpoints and identifiers for integration with other systems"
  value = {
    health_check_metric_filter = "AWS/Route53 HealthCheckStatus HealthCheckId=${aws_route53_health_check.website_uptime.id}"
    sns_topic_for_webhooks    = aws_sns_topic.uptime_alerts.arn
    cloudwatch_log_group      = "/aws/route53/healthchecks/${aws_route53_health_check.website_uptime.id}"
  }
}

# ==============================================================================
# Security and Compliance Information
# ==============================================================================

output "security_configuration" {
  description = "Security configuration details for compliance and audit"
  value = {
    sns_encryption_enabled    = "SNS topic encrypted with AWS managed KMS key"
    health_check_regions     = "Health checks performed from ${length(var.health_check_regions)} AWS regions"
    alarm_actions_restricted = "CloudWatch alarms can only publish to SNS topics in same account"
    tags_applied            = "All resources tagged for cost allocation and management"
  }
}