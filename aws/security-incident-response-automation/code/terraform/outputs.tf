# Outputs for automated security incident response with AWS Security Hub
#
# This file defines all output values that provide important information
# about the deployed infrastructure for verification and integration purposes.

# ===================================
# Security Hub Outputs
# ===================================

output "security_hub_account_id" {
  description = "AWS account ID where Security Hub is enabled"
  value       = aws_securityhub_account.main.id
}

output "security_hub_arn" {
  description = "ARN of the Security Hub account"
  value       = "arn:aws:securityhub:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:hub/default"
}

output "security_standards_arns" {
  description = "List of enabled security standards ARNs"
  value       = aws_securityhub_standards_subscription.standards[*].standards_arn
}

# ===================================
# Lambda Function Outputs
# ===================================

output "classification_function_arn" {
  description = "ARN of the security finding classification Lambda function"
  value       = aws_lambda_function.classification.arn
}

output "classification_function_name" {
  description = "Name of the security finding classification Lambda function"
  value       = aws_lambda_function.classification.function_name
}

output "remediation_function_arn" {
  description = "ARN of the security remediation Lambda function"
  value       = aws_lambda_function.remediation.arn
}

output "remediation_function_name" {
  description = "Name of the security remediation Lambda function"
  value       = aws_lambda_function.remediation.function_name
}

output "notification_function_arn" {
  description = "ARN of the security notification Lambda function"
  value       = aws_lambda_function.notification.arn
}

output "notification_function_name" {
  description = "Name of the security notification Lambda function"
  value       = aws_lambda_function.notification.function_name
}

# ===================================
# SNS Topic Outputs
# ===================================

output "sns_topic_arn" {
  description = "ARN of the security incidents SNS topic"
  value       = aws_sns_topic.security_incidents.arn
}

output "sns_topic_name" {
  description = "Name of the security incidents SNS topic"
  value       = aws_sns_topic.security_incidents.name
}

# ===================================
# EventBridge Rule Outputs
# ===================================

output "critical_findings_rule_arn" {
  description = "ARN of the EventBridge rule for critical findings"
  value       = aws_cloudwatch_event_rule.critical_findings.arn
}

output "critical_findings_rule_name" {
  description = "Name of the EventBridge rule for critical findings"
  value       = aws_cloudwatch_event_rule.critical_findings.name
}

output "medium_findings_rule_arn" {
  description = "ARN of the EventBridge rule for medium findings"
  value       = var.process_medium_findings ? aws_cloudwatch_event_rule.medium_findings[0].arn : null
}

output "medium_findings_rule_name" {
  description = "Name of the EventBridge rule for medium findings"
  value       = var.process_medium_findings ? aws_cloudwatch_event_rule.medium_findings[0].name : null
}

output "manual_escalation_rule_arn" {
  description = "ARN of the EventBridge rule for manual escalation"
  value       = aws_cloudwatch_event_rule.manual_escalation.arn
}

output "manual_escalation_rule_name" {
  description = "Name of the EventBridge rule for manual escalation"
  value       = aws_cloudwatch_event_rule.manual_escalation.name
}

# ===================================
# IAM Role Outputs
# ===================================

output "incident_response_role_arn" {
  description = "ARN of the incident response IAM role"
  value       = aws_iam_role.incident_response.arn
}

output "incident_response_role_name" {
  description = "Name of the incident response IAM role"
  value       = aws_iam_role.incident_response.name
}

# ===================================
# Security Hub Insights Outputs
# ===================================

output "critical_incidents_insight_arn" {
  description = "ARN of the critical incidents Security Hub insight"
  value       = aws_securityhub_insight.critical_incidents.arn
}

output "unresolved_findings_insight_arn" {
  description = "ARN of the unresolved findings Security Hub insight"
  value       = aws_securityhub_insight.unresolved_findings.arn
}

# ===================================
# Security Hub Custom Actions Outputs
# ===================================

output "escalation_action_arn" {
  description = "ARN of the Security Hub custom escalation action"
  value       = aws_securityhub_action_target.escalate.arn
}

# ===================================
# CloudWatch Log Groups Outputs
# ===================================

output "classification_log_group_name" {
  description = "Name of the classification function CloudWatch log group"
  value       = aws_cloudwatch_log_group.classification_function.name
}

output "remediation_log_group_name" {
  description = "Name of the remediation function CloudWatch log group"
  value       = aws_cloudwatch_log_group.remediation_function.name
}

output "notification_log_group_name" {
  description = "Name of the notification function CloudWatch log group"
  value       = aws_cloudwatch_log_group.notification_function.name
}

# ===================================
# KMS Key Outputs
# ===================================

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.security_response[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_alias.security_response[0].name : null
}

# ===================================
# Configuration Summary Outputs
# ===================================

output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    environment                       = var.environment
    project_name                     = var.project_name
    aws_region                       = data.aws_region.current.name
    aws_account_id                   = data.aws_caller_identity.current.account_id
    auto_remediation_enabled         = var.auto_remediation_enabled
    auto_remediation_severity_threshold = var.auto_remediation_severity_threshold
    processed_severity_levels        = local.severity_levels
    kms_encryption_enabled           = var.enable_kms_encryption
    email_notifications_enabled     = var.enable_email_notifications
    slack_notifications_enabled     = var.enable_slack_notifications
    notification_email              = var.enable_email_notifications ? var.notification_email : "disabled"
  }
}

# ===================================
# Security Hub Console URLs
# ===================================

output "security_hub_console_url" {
  description = "URL to access Security Hub in the AWS Console"
  value       = "https://console.aws.amazon.com/securityhub/home?region=${data.aws_region.current.name}#/summary"
}

output "security_hub_findings_url" {
  description = "URL to view Security Hub findings in the AWS Console"
  value       = "https://console.aws.amazon.com/securityhub/home?region=${data.aws_region.current.name}#/findings"
}

output "security_hub_insights_url" {
  description = "URL to view Security Hub insights in the AWS Console"
  value       = "https://console.aws.amazon.com/securityhub/home?region=${data.aws_region.current.name}#/insights"
}

# ===================================
# CloudWatch Console URLs
# ===================================

output "cloudwatch_logs_urls" {
  description = "URLs to view Lambda function logs in CloudWatch Console"
  value = {
    classification = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.classification_function.name, "/", "%252F")}"
    remediation    = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.remediation_function.name, "/", "%252F")}"
    notification   = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.notification_function.name, "/", "%252F")}"
  }
}

# ===================================
# Testing and Validation Outputs
# ===================================

output "test_finding_command" {
  description = "AWS CLI command to create a test security finding"
  value = "aws securityhub batch-import-findings --findings '[{\"SchemaVersion\":\"2018-10-08\",\"Id\":\"test-finding-$(date +%s)\",\"ProductArn\":\"arn:aws:securityhub:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:product/${data.aws_caller_identity.current.account_id}/default\",\"GeneratorId\":\"TestGenerator\",\"AwsAccountId\":\"${data.aws_caller_identity.current.account_id}\",\"Types\":[\"Software and Configuration Checks/Vulnerabilities\"],\"FirstObservedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",\"LastObservedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",\"CreatedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",\"UpdatedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",\"Severity\":{\"Label\":\"HIGH\",\"Normalized\":70},\"Title\":\"Test Security Finding\",\"Description\":\"Test finding to validate automated incident response\",\"Resources\":[{\"Type\":\"AwsAccount\",\"Id\":\"AWS::::Account:${data.aws_caller_identity.current.account_id}\",\"Partition\":\"aws\",\"Region\":\"${data.aws_region.current.name}\"}],\"WorkflowState\":\"NEW\",\"RecordState\":\"ACTIVE\"}]'"
}

output "verification_commands" {
  description = "AWS CLI commands to verify the deployment"
  value = {
    security_hub_status = "aws securityhub describe-hub"
    lambda_functions    = "aws lambda list-functions --query 'Functions[?contains(FunctionName, \\`security\\`) || contains(FunctionName, \\`incident\\`)].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified}'"
    eventbridge_rules   = "aws events list-rules --name-prefix '${local.name_prefix}security'"
    sns_subscriptions   = "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.security_incidents.arn}"
    security_findings   = "aws securityhub get-findings --max-results 5 --query 'Findings[*].{Id:Id,Severity:Severity.Label,Title:Title}'"
  }
}

# ===================================
# Cost Estimation Outputs
# ===================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    description = "Estimated monthly costs (USD) based on typical usage patterns"
    security_hub = "$3.00 per month for findings ingestion and compliance checks"
    lambda_functions = "$0.20-$2.00 per month based on number of security findings processed"
    cloudwatch_logs = "$0.50-$5.00 per month based on log volume"
    sns_notifications = "$0.50-$2.00 per month based on number of messages"
    eventbridge = "$1.00-$3.00 per month based on number of events processed"
    kms = var.enable_kms_encryption ? "$1.00 per month for key usage" : "Not applicable"
    total_estimated = "$6.20-$16.00 per month"
    note = "Actual costs may vary based on usage patterns, finding volume, and regional pricing"
  }
}

# ===================================
# Next Steps Outputs
# ===================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Confirm email subscription by checking your inbox for SNS confirmation email",
    "2. Enable additional AWS security services (GuardDuty, Config, Inspector, Macie) to generate findings",
    "3. Test the system by creating a test finding using the provided CLI command",
    "4. Review and customize Lambda function logic based on your security requirements",
    "5. Configure additional notification channels (Slack, PagerDuty) if needed",
    "6. Review Security Hub insights regularly to monitor security posture",
    "7. Consider setting up custom Security Hub rules for organization-specific compliance requirements"
  ]
}