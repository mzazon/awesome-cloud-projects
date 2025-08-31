# Outputs for Website Uptime Monitoring Infrastructure

# ================================
# Primary Resource Identifiers
# ================================

output "health_check_id" {
  description = "ID of the Route53 health check"
  value       = aws_route53_health_check.website_health.id
}

output "health_check_arn" {
  description = "ARN of the Route53 health check"
  value       = aws_route53_health_check.website_health.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for uptime alerts"
  value       = aws_sns_topic.uptime_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.uptime_alerts.name
}

# ================================
# CloudWatch Resources
# ================================

output "downtime_alarm_name" {
  description = "Name of the CloudWatch alarm for website downtime"
  value       = aws_cloudwatch_metric_alarm.website_down.alarm_name
}

output "downtime_alarm_arn" {
  description = "ARN of the CloudWatch alarm for website downtime"
  value       = aws_cloudwatch_metric_alarm.website_down.arn
}

output "recovery_alarm_name" {
  description = "Name of the CloudWatch alarm for website recovery (if enabled)"
  value       = var.enable_recovery_notifications ? aws_cloudwatch_metric_alarm.website_recovery[0].alarm_name : null
}

output "recovery_alarm_arn" {
  description = "ARN of the CloudWatch alarm for website recovery (if enabled)"
  value       = var.enable_recovery_notifications ? aws_cloudwatch_metric_alarm.website_recovery[0].arn : null
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.uptime_monitoring.dashboard_name
}

output "dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.uptime_monitoring.dashboard_name}"
}

# ================================
# Configuration Details
# ================================

output "monitored_website_url" {
  description = "The website URL being monitored"
  value       = var.website_url
}

output "monitored_domain" {
  description = "The domain name extracted from the website URL"
  value       = local.clean_domain
}

output "health_check_protocol" {
  description = "Protocol used for health check (HTTP or HTTPS)"
  value       = local.protocol
}

output "health_check_port" {
  description = "Port used for health check"
  value       = local.port
}

output "admin_email" {
  description = "Email address receiving alerts (sensitive)"
  value       = var.admin_email
  sensitive   = true
}

# ================================
# Operational Information
# ================================

output "health_check_status_metric" {
  description = "CloudWatch metric name for health check status monitoring"
  value       = "AWS/Route53 HealthCheckStatus"
}

output "subscription_confirmation_required" {
  description = "Information about email subscription confirmation"
  value       = "IMPORTANT: Check ${var.admin_email} for a subscription confirmation email from AWS SNS and confirm to receive alerts."
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the monitoring resources (USD)"
  value       = {
    route53_health_check = "$0.50 per health check"
    cloudwatch_alarms    = "$0.10 per alarm per month"
    sns_notifications    = "$0.50 per 1M requests (typically under $0.01/month)"
    total_estimated      = "$0.60 - $1.20 per month"
  }
}

# ================================
# Useful AWS CLI Commands
# ================================

output "useful_commands" {
  description = "Useful AWS CLI commands for managing this monitoring setup"
  value = {
    check_health_status = "aws route53 get-health-check-status --health-check-id ${aws_route53_health_check.website_health.id}"
    view_alarm_history  = "aws cloudwatch describe-alarm-history --alarm-name ${aws_cloudwatch_metric_alarm.website_down.alarm_name}"
    list_subscriptions  = "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.uptime_alerts.arn}"
    test_notification   = "aws sns publish --topic-arn ${aws_sns_topic.uptime_alerts.arn} --message 'Test notification from uptime monitoring'"
  }
}

# ================================
# Next Steps
# ================================

output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Confirm email subscription by clicking the link sent to ${var.admin_email}",
    "2. Monitor the dashboard at: https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.uptime_monitoring.dashboard_name}",
    "3. Test the setup by temporarily blocking access to your website",
    "4. Consider adding additional notification channels (SMS, Slack) to the SNS topic",
    "5. Review and adjust failure thresholds based on your website's normal behavior"
  ]
}