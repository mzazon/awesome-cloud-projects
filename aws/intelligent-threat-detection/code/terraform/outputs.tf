# ==============================================================================
# Outputs for GuardDuty Threat Detection Infrastructure
# ==============================================================================

# ==============================================================================
# GuardDuty Outputs
# ==============================================================================

output "guardduty_detector_id" {
  description = "The ID of the GuardDuty detector"
  value       = aws_guardduty_detector.main.id
}

output "guardduty_detector_arn" {
  description = "The ARN of the GuardDuty detector"
  value       = aws_guardduty_detector.main.arn
}

output "guardduty_account_id" {
  description = "The AWS account ID where GuardDuty is enabled"
  value       = aws_guardduty_detector.main.account_id
}

output "guardduty_service_role_arn" {
  description = "The service-linked role ARN used by GuardDuty"
  value       = aws_guardduty_detector.main.service_role
}

output "guardduty_finding_publishing_frequency" {
  description = "The frequency for publishing findings to CloudWatch Events"
  value       = aws_guardduty_detector.main.finding_publishing_frequency
}

# ==============================================================================
# S3 Bucket Outputs
# ==============================================================================

output "s3_findings_bucket_name" {
  description = "Name of the S3 bucket storing GuardDuty findings"
  value       = aws_s3_bucket.guardduty_findings.id
}

output "s3_findings_bucket_arn" {
  description = "ARN of the S3 bucket storing GuardDuty findings"
  value       = aws_s3_bucket.guardduty_findings.arn
}

output "s3_findings_bucket_domain_name" {
  description = "Domain name of the S3 bucket storing GuardDuty findings"
  value       = aws_s3_bucket.guardduty_findings.bucket_domain_name
}

output "s3_findings_bucket_region" {
  description = "Region where the S3 findings bucket is located"
  value       = aws_s3_bucket.guardduty_findings.region
}

output "guardduty_publishing_destination_arn" {
  description = "ARN of the GuardDuty publishing destination to S3"
  value       = var.enable_s3_export ? aws_guardduty_publishing_destination.s3[0].arn : null
}

# ==============================================================================
# SNS Topic Outputs
# ==============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for GuardDuty alerts"
  value       = aws_sns_topic.guardduty_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for GuardDuty alerts"
  value       = aws_sns_topic.guardduty_alerts.name
}

output "sns_subscription_arn" {
  description = "ARN of the email subscription to the SNS topic"
  value       = var.notification_email != "" ? aws_sns_topic_subscription.email[0].arn : null
}

output "sns_kms_key_id" {
  description = "ID of the KMS key used for SNS topic encryption"
  value       = var.enable_sns_encryption ? aws_kms_key.sns[0].id : null
}

output "sns_kms_key_arn" {
  description = "ARN of the KMS key used for SNS topic encryption"
  value       = var.enable_sns_encryption ? aws_kms_key.sns[0].arn : null
}

# ==============================================================================
# EventBridge Outputs
# ==============================================================================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for GuardDuty findings"
  value       = aws_cloudwatch_event_rule.guardduty_findings.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for GuardDuty findings"
  value       = aws_cloudwatch_event_rule.guardduty_findings.arn
}

output "eventbridge_target_id" {
  description = "ID of the EventBridge target routing to SNS"
  value       = aws_cloudwatch_event_target.sns.target_id
}

# ==============================================================================
# CloudWatch Outputs
# ==============================================================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for security monitoring"
  value       = aws_cloudwatch_dashboard.guardduty_monitoring.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.guardduty_monitoring.dashboard_name}"
}

output "cloudwatch_alarm_arn" {
  description = "ARN of the CloudWatch alarm for high findings"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.high_findings[0].arn : null
}

output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm for high findings"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.high_findings[0].alarm_name : null
}

# ==============================================================================
# Console URLs and Access Information
# ==============================================================================

output "guardduty_console_url" {
  description = "URL to access the GuardDuty console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/guardduty/home?region=${data.aws_region.current.name}#/findings"
}

output "sns_console_url" {
  description = "URL to access the SNS topic in the console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/sns/v3/home?region=${data.aws_region.current.name}#/topic/${aws_sns_topic.guardduty_alerts.arn}"
}

output "s3_console_url" {
  description = "URL to access the S3 bucket in the console"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.guardduty_findings.id}?region=${data.aws_region.current.name}"
}

output "eventbridge_console_url" {
  description = "URL to access the EventBridge rule in the console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/events/home?region=${data.aws_region.current.name}#/eventbus/default/rules/${aws_cloudwatch_event_rule.guardduty_findings.name}"
}

# ==============================================================================
# Threat Intelligence and IP Set Outputs
# ==============================================================================

output "custom_threat_intel_set_id" {
  description = "ID of the custom threat intelligence set"
  value       = var.enable_custom_threat_intel && var.threat_intel_set_location != "" ? aws_guardduty_threatintelset.custom[0].id : null
}

output "custom_threat_intel_set_arn" {
  description = "ARN of the custom threat intelligence set"
  value       = var.enable_custom_threat_intel && var.threat_intel_set_location != "" ? aws_guardduty_threatintelset.custom[0].arn : null
}

output "trusted_ip_set_id" {
  description = "ID of the trusted IP set"
  value       = var.enable_trusted_ip_set && var.trusted_ip_set_location != "" ? aws_guardduty_ipset.trusted[0].id : null
}

output "trusted_ip_set_arn" {
  description = "ARN of the trusted IP set"
  value       = var.enable_trusted_ip_set && var.trusted_ip_set_location != "" ? aws_guardduty_ipset.trusted[0].arn : null
}

# ==============================================================================
# Security and Compliance Information
# ==============================================================================

output "security_configuration" {
  description = "Summary of security configurations applied"
  value = {
    guardduty_enabled           = aws_guardduty_detector.main.enable
    s3_protection_enabled       = var.enable_s3_protection
    kubernetes_protection_enabled = var.enable_kubernetes_protection
    malware_protection_enabled  = var.enable_malware_protection
    sns_encryption_enabled      = var.enable_sns_encryption
    s3_public_access_blocked    = true
    s3_versioning_enabled       = true
    s3_encryption_enabled       = true
    findings_lifecycle_enabled  = var.enable_findings_lifecycle
    cloudwatch_alarms_enabled   = var.enable_cloudwatch_alarms
  }
}

output "compliance_information" {
  description = "Compliance-related configuration details"
  value = {
    findings_retention_days     = var.findings_retention_days
    audit_trail_enabled         = true
    encryption_in_transit       = var.enable_sns_encryption
    encryption_at_rest          = true
    access_logging_enabled      = true
    monitoring_enabled          = true
    automated_alerting_enabled  = true
  }
}

# ==============================================================================
# Cost Monitoring Information
# ==============================================================================

output "cost_monitoring_info" {
  description = "Information for monitoring GuardDuty costs"
  value = {
    detector_id                = aws_guardduty_detector.main.id
    finding_publishing_frequency = aws_guardduty_detector.main.finding_publishing_frequency
    data_sources_monitored     = {
      cloudtrail_events = true
      vpc_flow_logs     = true
      dns_logs          = true
      s3_data_events    = var.enable_s3_protection
      kubernetes_logs   = var.enable_kubernetes_protection
      malware_protection = var.enable_malware_protection
    }
    cost_optimization_notes = "GuardDuty pricing is based on data volume processed. Monitor usage in AWS Cost Explorer using the GuardDuty service filter."
  }
}

# ==============================================================================
# Deployment Summary
# ==============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources for verification"
  value = {
    guardduty_detector_id       = aws_guardduty_detector.main.id
    s3_bucket_name             = aws_s3_bucket.guardduty_findings.id
    sns_topic_name             = aws_sns_topic.guardduty_alerts.name
    eventbridge_rule_name      = aws_cloudwatch_event_rule.guardduty_findings.name
    dashboard_name             = aws_cloudwatch_dashboard.guardduty_monitoring.dashboard_name
    email_subscription_configured = var.notification_email != ""
    s3_export_enabled          = var.enable_s3_export
    cloudwatch_alarms_enabled  = var.enable_cloudwatch_alarms
    custom_threat_intel_enabled = var.enable_custom_threat_intel && var.threat_intel_set_location != ""
    trusted_ip_set_enabled     = var.enable_trusted_ip_set && var.trusted_ip_set_location != ""
    deployment_region          = data.aws_region.current.name
    deployment_account         = data.aws_caller_identity.current.account_id
  }
}

# ==============================================================================
# Next Steps and Recommendations
# ==============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Confirm email subscription to SNS topic if email was provided",
    "2. Review GuardDuty findings in the console: ${aws_cloudwatch_dashboard.guardduty_monitoring.dashboard_name}",
    "3. Test the alerting system using GuardDuty sample findings",
    "4. Configure additional notification endpoints if needed",
    "5. Set up custom threat intelligence feeds if required",
    "6. Review and adjust finding severity thresholds based on your environment",
    "7. Consider enabling GuardDuty for other AWS regions if needed",
    "8. Monitor costs in AWS Cost Explorer under GuardDuty service"
  ]
}

output "testing_commands" {
  description = "Commands to test the GuardDuty deployment"
  value = {
    check_detector_status = "aws guardduty get-detector --detector-id ${aws_guardduty_detector.main.id}"
    list_findings = "aws guardduty list-findings --detector-id ${aws_guardduty_detector.main.id}"
    generate_sample_findings = "aws guardduty create-sample-findings --detector-id ${aws_guardduty_detector.main.id} --finding-types CryptoCurrency:EC2/BitcoinTool.B!DNS"
    check_sns_subscriptions = "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.guardduty_alerts.arn}"
    view_dashboard = "echo 'Open: ${aws_cloudwatch_dashboard.guardduty_monitoring.dashboard_name}'"
  }
}