# Output Values for Security Incident Response with AWS Security Hub
# These outputs provide essential information about the deployed infrastructure

# ===================================
# Core Infrastructure Outputs
# ===================================

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = local.account_id
}

output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = local.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

# ===================================
# Security Hub Outputs
# ===================================

output "security_hub_account_id" {
  description = "Security Hub account identifier"
  value       = aws_securityhub_account.main.id
}

output "security_hub_custom_action_arn" {
  description = "ARN of the Security Hub custom action for manual escalation"
  value       = var.create_custom_action ? aws_securityhub_action_target.escalate_to_soc[0].arn : null
}

output "security_hub_custom_action_id" {
  description = "ID of the Security Hub custom action"
  value       = var.create_custom_action ? aws_securityhub_action_target.escalate_to_soc[0].identifier : null
}

# ===================================
# IAM Role Outputs
# ===================================

output "security_hub_role_arn" {
  description = "ARN of the Security Hub service role"
  value       = aws_iam_role.security_hub_role.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_policy_arn" {
  description = "ARN of the custom Lambda policy for Security Hub access"
  value       = aws_iam_policy.security_hub_lambda_policy.arn
}

# ===================================
# Lambda Function Outputs
# ===================================

output "incident_processor_function_name" {
  description = "Name of the incident processing Lambda function"
  value       = aws_lambda_function.incident_processor.function_name
}

output "incident_processor_function_arn" {
  description = "ARN of the incident processing Lambda function"
  value       = aws_lambda_function.incident_processor.arn
}

output "threat_intelligence_function_name" {
  description = "Name of the threat intelligence Lambda function"
  value       = var.enable_threat_intelligence ? aws_lambda_function.threat_intelligence[0].function_name : null
}

output "threat_intelligence_function_arn" {
  description = "ARN of the threat intelligence Lambda function"
  value       = var.enable_threat_intelligence ? aws_lambda_function.threat_intelligence[0].arn : null
}

# ===================================
# SNS and SQS Outputs
# ===================================

output "sns_topic_name" {
  description = "Name of the SNS topic for security incident notifications"
  value       = aws_sns_topic.security_incidents.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for security incident notifications"
  value       = aws_sns_topic.security_incidents.arn
}

output "sqs_queue_name" {
  description = "Name of the SQS queue for incident buffering"
  value       = aws_sqs_queue.incident_queue.name
}

output "sqs_queue_url" {
  description = "URL of the SQS queue for incident buffering"
  value       = aws_sqs_queue.incident_queue.id
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue for incident buffering"
  value       = aws_sqs_queue.incident_queue.arn
}

# ===================================
# EventBridge Outputs
# ===================================

output "eventbridge_high_severity_rule_name" {
  description = "Name of the EventBridge rule for high severity findings"
  value       = aws_cloudwatch_event_rule.security_hub_high_severity.name
}

output "eventbridge_high_severity_rule_arn" {
  description = "ARN of the EventBridge rule for high severity findings"
  value       = aws_cloudwatch_event_rule.security_hub_high_severity.arn
}

output "eventbridge_custom_escalation_rule_name" {
  description = "Name of the EventBridge rule for custom escalation"
  value       = var.create_custom_action ? aws_cloudwatch_event_rule.security_hub_custom_escalation[0].name : null
}

output "eventbridge_custom_escalation_rule_arn" {
  description = "ARN of the EventBridge rule for custom escalation"
  value       = var.create_custom_action ? aws_cloudwatch_event_rule.security_hub_custom_escalation[0].arn : null
}

# ===================================
# CloudWatch Outputs
# ===================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for monitoring"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.security_hub_incident_response[0].dashboard_name : null
}

output "cloudwatch_log_group_incident_processor" {
  description = "CloudWatch log group for incident processor Lambda"
  value       = aws_cloudwatch_log_group.incident_processor_logs.name
}

output "cloudwatch_log_group_threat_intelligence" {
  description = "CloudWatch log group for threat intelligence Lambda"
  value       = var.enable_threat_intelligence ? aws_cloudwatch_log_group.threat_intelligence_logs[0].name : null
}

output "cloudwatch_alarm_lambda_errors" {
  description = "CloudWatch alarm for Lambda function errors"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : null
}

output "cloudwatch_alarm_sns_failures" {
  description = "CloudWatch alarm for SNS notification failures"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.sns_failures[0].alarm_name : null
}

# ===================================
# Configuration Outputs
# ===================================

output "enabled_features" {
  description = "List of enabled features in the deployment"
  value = {
    security_standards       = var.enable_security_standards
    cis_benchmark           = var.enable_cis_benchmark
    threat_intelligence     = var.enable_threat_intelligence
    custom_action          = var.create_custom_action
    automation_rules       = var.automation_rules_enabled
    cloudwatch_dashboard   = var.enable_cloudwatch_dashboard
    cloudwatch_alarms      = var.enable_cloudwatch_alarms
    email_notifications    = var.notification_email != ""
  }
}

output "severity_filter" {
  description = "Configured severity levels for automated processing"
  value       = var.severity_filter
}

# ===================================
# Integration Information
# ===================================

output "sns_email_subscription_confirmation" {
  description = "Information about email subscription confirmation"
  value = var.notification_email != "" ? {
    email_address = var.notification_email
    status       = "Check your email and confirm the SNS subscription to receive notifications"
  } : null
}

output "security_hub_console_url" {
  description = "URL to access Security Hub console"
  value       = "https://${local.region}.console.aws.amazon.com/securityhub/home?region=${local.region}#/findings"
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = var.enable_cloudwatch_dashboard ? "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards:name=SecurityHubIncidentResponse" : null
}

# ===================================
# Next Steps Information
# ===================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Confirm SNS email subscription if email notifications are enabled",
    "2. Test the incident response system by creating a test finding",
    "3. Review CloudWatch dashboard for monitoring metrics",
    "4. Configure external system integrations using SQS queue",
    "5. Customize Lambda function logic for organization-specific requirements",
    "6. Review and adjust automation rules based on operational needs"
  ]
}

output "testing_commands" {
  description = "Commands to test the incident response system"
  value = {
    create_test_finding = "aws securityhub batch-import-findings --findings file://test-finding.json"
    check_lambda_logs   = "aws logs describe-log-streams --log-group-name /aws/lambda/${local.lambda_function_name}"
    check_sqs_messages  = "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.incident_queue.id} --attribute-names ApproximateNumberOfMessages"
    view_sns_topic      = "aws sns get-topic-attributes --topic-arn ${aws_sns_topic.security_incidents.arn}"
  }
}