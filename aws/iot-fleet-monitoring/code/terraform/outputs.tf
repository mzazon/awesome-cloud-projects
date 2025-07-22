# Outputs for IoT Device Fleet Monitoring Infrastructure

# ==========================================
# GENERAL OUTPUTS
# ==========================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_prefix" {
  description = "Resource prefix used for naming"
  value       = local.resource_prefix
}

output "fleet_name" {
  description = "Name of the IoT device fleet"
  value       = var.fleet_name
}

# ==========================================
# IOT DEVICE DEFENDER OUTPUTS
# ==========================================

output "device_defender_role_arn" {
  description = "ARN of the Device Defender IAM role"
  value       = aws_iam_role.device_defender_role.arn
}

output "security_profile_name" {
  description = "Name of the Device Defender security profile"
  value       = aws_iot_security_profile.fleet_security_profile.name
}

output "security_profile_arn" {
  description = "ARN of the Device Defender security profile"
  value       = aws_iot_security_profile.fleet_security_profile.arn
}

output "scheduled_audit_name" {
  description = "Name of the scheduled audit (if enabled)"
  value       = var.enable_scheduled_audit ? aws_iot_scheduled_audit.daily_fleet_audit[0].scheduled_audit_name : null
}

output "audit_configuration_enabled" {
  description = "Whether Device Defender audit configuration is enabled"
  value       = aws_iot_account_audit_configuration.fleet_audit.account_id != null
}

# ==========================================
# IOT THING GROUP AND DEVICES OUTPUTS
# ==========================================

output "thing_group_name" {
  description = "Name of the IoT thing group"
  value       = aws_iot_thing_group.fleet_group.name
}

output "thing_group_arn" {
  description = "ARN of the IoT thing group"
  value       = aws_iot_thing_group.fleet_group.arn
}

output "device_names" {
  description = "Names of the created test IoT devices"
  value       = aws_iot_thing.test_devices[*].name
}

output "device_count" {
  description = "Number of IoT devices created"
  value       = length(aws_iot_thing.test_devices)
}

output "device_arns" {
  description = "ARNs of the created test IoT devices"
  value       = aws_iot_thing.test_devices[*].arn
}

# ==========================================
# SNS AND NOTIFICATIONS OUTPUTS
# ==========================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for fleet alerts"
  value       = aws_sns_topic.fleet_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for fleet alerts"
  value       = aws_sns_topic.fleet_alerts.name
}

output "notification_email" {
  description = "Email address configured for notifications"
  value       = var.notification_email
}

# ==========================================
# LAMBDA FUNCTION OUTPUTS
# ==========================================

output "lambda_function_name" {
  description = "Name of the Lambda remediation function"
  value       = aws_lambda_function.remediation_function.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda remediation function"
  value       = aws_lambda_function.remediation_function.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_remediation_role.arn
}

output "lambda_log_group_name" {
  description = "Name of the Lambda function log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ==========================================
# IOT RULES OUTPUTS
# ==========================================

output "iot_rules_role_arn" {
  description = "ARN of the IoT Rules execution role"
  value       = aws_iam_role.iot_rules_role.arn
}

output "device_connection_rule_name" {
  description = "Name of the device connection monitoring IoT rule"
  value       = aws_iot_topic_rule.device_connection_monitoring.name
}

output "message_volume_rule_name" {
  description = "Name of the message volume monitoring IoT rule"
  value       = aws_iot_topic_rule.message_volume_monitoring.name
}

# ==========================================
# CLOUDWATCH OUTPUTS
# ==========================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.fleet_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.fleet_dashboard.dashboard_name}"
}

output "cloudwatch_alarm_names" {
  description = "Names of the CloudWatch alarms"
  value = [
    aws_cloudwatch_metric_alarm.high_security_violations.alarm_name,
    aws_cloudwatch_metric_alarm.low_connectivity.alarm_name,
    aws_cloudwatch_metric_alarm.message_processing_errors.alarm_name
  ]
}

output "log_group_names" {
  description = "Names of the CloudWatch log groups"
  value = [
    aws_cloudwatch_log_group.lambda_logs.name,
    aws_cloudwatch_log_group.iot_fleet_logs.name
  ]
}

# ==========================================
# MONITORING CONFIGURATION OUTPUTS
# ==========================================

output "security_behaviors" {
  description = "Security behaviors configured in the security profile"
  value = {
    authorization_failures_threshold = var.security_profile_behaviors.authorization_failures_threshold
    message_byte_size_threshold     = var.security_profile_behaviors.message_byte_size_threshold
    messages_received_threshold     = var.security_profile_behaviors.messages_received_threshold
    messages_sent_threshold         = var.security_profile_behaviors.messages_sent_threshold
    connection_attempts_threshold   = var.security_profile_behaviors.connection_attempts_threshold
    duration_seconds               = var.security_profile_behaviors.duration_seconds
  }
}

output "alarm_thresholds" {
  description = "CloudWatch alarm thresholds configured"
  value = {
    security_violations_threshold = var.cloudwatch_alarm_thresholds.security_violations_threshold
    low_connectivity_threshold   = var.cloudwatch_alarm_thresholds.low_connectivity_threshold
    processing_errors_threshold  = var.cloudwatch_alarm_thresholds.processing_errors_threshold
  }
}

output "dashboard_widgets_enabled" {
  description = "Dashboard widgets that are enabled"
  value = {
    device_overview     = var.dashboard_widgets.enable_device_overview
    security_violations = var.dashboard_widgets.enable_security_violations
    message_processing  = var.dashboard_widgets.enable_message_processing
    violation_logs      = var.dashboard_widgets.enable_violation_logs
  }
}

# ==========================================
# TESTING AND VALIDATION OUTPUTS
# ==========================================

output "test_commands" {
  description = "Commands to test the monitoring system"
  value = {
    check_security_profile = "aws iot describe-security-profile --security-profile-name ${aws_iot_security_profile.fleet_security_profile.name}"
    check_thing_group      = "aws iot describe-thing-group --thing-group-name ${aws_iot_thing_group.fleet_group.name}"
    check_devices          = "aws iot list-things-in-thing-group --thing-group-name ${aws_iot_thing_group.fleet_group.name}"
    check_alarms           = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.high_security_violations.alarm_name}"
    test_lambda            = "aws lambda invoke --function-name ${aws_lambda_function.remediation_function.function_name} --payload '{}' response.json"
  }
}

output "validation_checklist" {
  description = "Validation checklist for the deployed infrastructure"
  value = {
    device_defender_enabled = "Check if Device Defender audit configuration is active"
    security_profile_attached = "Verify security profile is attached to the thing group"
    devices_in_group = "Confirm all ${var.device_count} devices are in the thing group"
    lambda_permissions = "Verify Lambda function has proper IAM permissions"
    sns_subscriptions = "Check SNS topic has email and Lambda subscriptions"
    cloudwatch_alarms = "Ensure all CloudWatch alarms are in OK state"
    dashboard_accessible = "Access the CloudWatch dashboard at the provided URL"
  }
}

# ==========================================
# COST OPTIMIZATION OUTPUTS
# ==========================================

output "cost_optimization_settings" {
  description = "Cost optimization settings applied"
  value = {
    log_retention_days = var.log_retention_days
    lambda_memory_size = var.lambda_function_config.memory_size
    lambda_timeout     = var.lambda_function_config.timeout
    scheduled_audit    = var.enable_scheduled_audit ? "enabled" : "disabled"
  }
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (approximate)"
  value = {
    lambda_executions = "~$1-5 (based on violations)"
    cloudwatch_logs   = "~$1-3 (based on log volume)"
    cloudwatch_alarms = "~$1 (3 alarms)"
    iot_device_defender = "~$2-5 (based on device count)"
    sns_notifications = "~$1 (based on alerts)"
    total_estimated   = "~$6-17 per month"
    note             = "Costs vary based on usage patterns and region"
  }
}

# ==========================================
# SECURITY OUTPUTS
# ==========================================

output "security_configuration" {
  description = "Security configuration summary"
  value = {
    iam_roles_created = [
      aws_iam_role.device_defender_role.name,
      aws_iam_role.lambda_remediation_role.name,
      aws_iam_role.iot_rules_role.name
    ]
    security_profile_behaviors = length(local.security_behaviors)
    audit_checks_enabled       = length(aws_iot_account_audit_configuration.fleet_audit.audit_check_configurations)
    encryption_at_rest        = "CloudWatch Logs encrypted by default"
    least_privilege_iam       = "IAM roles follow least privilege principle"
  }
}

output "compliance_features" {
  description = "Compliance and audit features enabled"
  value = {
    scheduled_audits     = var.enable_scheduled_audit
    audit_frequency      = var.audit_frequency
    log_retention        = "${var.log_retention_days} days"
    security_monitoring  = "Real-time behavioral analysis"
    automated_remediation = "Lambda-based incident response"
    audit_trail          = "CloudWatch Logs and CloudTrail integration"
  }
}