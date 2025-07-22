# Core resource identifiers
output "security_profile_name" {
  description = "Name of the primary IoT security profile"
  value       = aws_iot_security_profile.iot_security_profile.name
}

output "security_profile_arn" {
  description = "ARN of the primary IoT security profile"
  value       = aws_iot_security_profile.iot_security_profile.arn
}

output "ml_security_profile_name" {
  description = "Name of the ML-based IoT security profile (if enabled)"
  value       = var.enable_ml_detection ? aws_iot_security_profile.iot_ml_security_profile[0].name : null
}

output "ml_security_profile_arn" {
  description = "ARN of the ML-based IoT security profile (if enabled)"
  value       = var.enable_ml_detection ? aws_iot_security_profile.iot_ml_security_profile[0].arn : null
}

# SNS and notification resources
output "sns_topic_arn" {
  description = "ARN of the SNS topic for security alerts"
  value       = aws_sns_topic.iot_security_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for security alerts"
  value       = aws_sns_topic.iot_security_alerts.name
}

output "notification_email" {
  description = "Email address configured for security notifications"
  value       = var.notification_email
  sensitive   = true
}

# IAM resources
output "device_defender_role_arn" {
  description = "ARN of the IAM role used by Device Defender"
  value       = aws_iam_role.device_defender_role.arn
}

output "device_defender_role_name" {
  description = "Name of the IAM role used by Device Defender"
  value       = aws_iam_role.device_defender_role.name
}

# Audit configuration
output "scheduled_audit_name" {
  description = "Name of the scheduled audit task"
  value       = aws_iot_scheduled_audit.weekly_security_audit.scheduled_audit_name
}

output "scheduled_audit_frequency" {
  description = "Frequency of the scheduled audit task"
  value       = aws_iot_scheduled_audit.weekly_security_audit.frequency
}

output "audit_day_of_week" {
  description = "Day of week for scheduled audit execution"
  value       = aws_iot_scheduled_audit.weekly_security_audit.day_of_week
}

# CloudWatch monitoring
output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm for security violations"
  value       = aws_cloudwatch_metric_alarm.iot_security_violations.alarm_name
}

output "cloudwatch_alarm_arn" {
  description = "ARN of the CloudWatch alarm for security violations"
  value       = aws_cloudwatch_metric_alarm.iot_security_violations.arn
}

# Security configuration details
output "security_profile_target_arn" {
  description = "ARN of the target scope for security profile application"
  value       = local.security_profile_target_arn
}

output "security_thresholds" {
  description = "Configured security threshold values"
  value = {
    max_messages_per_5min          = var.security_thresholds.max_messages_per_5min
    max_authorization_failures     = var.security_thresholds.max_authorization_failures
    max_message_size_bytes        = var.security_thresholds.max_message_size_bytes
    max_connection_attempts_per_5min = var.security_thresholds.max_connection_attempts_per_5min
  }
}

# AWS account and region information
output "aws_account_id" {
  description = "AWS account ID where resources are created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

# Deployment metadata
output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.random_suffix
}

output "ml_detection_enabled" {
  description = "Whether ML-based threat detection is enabled"
  value       = var.enable_ml_detection
}

# Audit check configuration
output "enabled_audit_checks" {
  description = "List of enabled Device Defender audit checks"
  value = [
    for check, enabled in var.audit_checks : check if enabled
  ]
}

# Validation commands for post-deployment verification
output "validation_commands" {
  description = "CLI commands to validate the deployment"
  value = {
    list_security_profiles = "aws iot list-security-profiles"
    describe_security_profile = "aws iot describe-security-profile --security-profile-name ${aws_iot_security_profile.iot_security_profile.name}"
    list_audit_tasks = "aws iot list-audit-tasks --start-time $(date -d '1 day ago' --iso-8601) --end-time $(date --iso-8601)"
    check_cloudwatch_alarms = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.iot_security_violations.alarm_name}"
    get_sns_subscriptions = "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.iot_security_alerts.arn}"
  }
}

# Quick start guide
output "quick_start_guide" {
  description = "Quick start commands for testing the security setup"
  value = {
    run_on_demand_audit = "aws iot start-on-demand-audit-task --target-check-names CA_CERTIFICATE_EXPIRING_CHECK DEVICE_CERTIFICATE_EXPIRING_CHECK"
    check_security_profile_targets = "aws iot list-targets-for-security-profile --security-profile-name ${aws_iot_security_profile.iot_security_profile.name}"
    view_cloudwatch_metrics = "aws cloudwatch get-metric-statistics --namespace AWS/IoT/DeviceDefender --metric-name Violations --start-time $(date -d '1 hour ago' --iso-8601) --end-time $(date --iso-8601) --period 300 --statistics Sum"
  }
}