# Lambda Function Outputs
output "lambda_function_arns" {
  description = "ARNs of all Lambda functions"
  value = {
    triage       = aws_lambda_function.triage.arn
    remediation  = aws_lambda_function.remediation.arn
    notification = aws_lambda_function.notification.arn
    error_handler = aws_lambda_function.error_handler.arn
  }
}

output "lambda_function_names" {
  description = "Names of all Lambda functions"
  value = {
    triage       = aws_lambda_function.triage.function_name
    remediation  = aws_lambda_function.remediation.function_name
    notification = aws_lambda_function.notification.function_name
    error_handler = aws_lambda_function.error_handler.function_name
  }
}

# IAM Role Outputs
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# EventBridge Outputs
output "eventbridge_rule_arns" {
  description = "ARNs of EventBridge rules"
  value = {
    security_hub_findings = aws_cloudwatch_event_rule.security_hub_findings.arn
    remediation_actions   = aws_cloudwatch_event_rule.remediation_actions.arn
    custom_actions       = aws_cloudwatch_event_rule.custom_actions.arn
    error_handling       = aws_cloudwatch_event_rule.error_handling.arn
  }
}

output "eventbridge_rule_names" {
  description = "Names of EventBridge rules"
  value = {
    security_hub_findings = aws_cloudwatch_event_rule.security_hub_findings.name
    remediation_actions   = aws_cloudwatch_event_rule.remediation_actions.name
    custom_actions       = aws_cloudwatch_event_rule.custom_actions.name
    error_handling       = aws_cloudwatch_event_rule.error_handling.name
  }
}

# SNS Topic Outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.security_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.security_notifications.name
}

# SQS Queue Outputs
output "dlq_url" {
  description = "URL of the dead letter queue"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "ARN of the dead letter queue"
  value       = aws_sqs_queue.dlq.arn
}

# Security Hub Outputs
output "security_hub_automation_rule_arns" {
  description = "ARNs of Security Hub automation rules"
  value = var.enable_automation_rules ? {
    high_severity     = aws_securityhub_automation_rule.high_severity[0].rule_arn
    critical_severity = aws_securityhub_automation_rule.critical_severity[0].rule_arn
  } : {}
}

output "security_hub_custom_action_arns" {
  description = "ARNs of custom Security Hub actions"
  value = var.enable_custom_actions ? {
    trigger_remediation = aws_securityhub_action_target.trigger_remediation[0].arn
    escalate_soc       = aws_securityhub_action_target.escalate_soc[0].arn
  } : {}
}

# Systems Manager Outputs
output "ssm_automation_document_name" {
  description = "Name of the Systems Manager automation document"
  value       = var.enable_ssm_automation ? aws_ssm_document.isolate_instance[0].name : null
}

# CloudWatch Outputs
output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value = var.enable_cloudwatch_monitoring ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.security_automation[0].dashboard_name}" : null
}

output "cloudwatch_alarm_names" {
  description = "Names of CloudWatch alarms"
  value = var.enable_cloudwatch_monitoring ? {
    lambda_errors      = aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name
    eventbridge_failures = aws_cloudwatch_metric_alarm.eventbridge_failures[0].alarm_name
  } : {}
}

# Resource Name Outputs
output "resource_prefix" {
  description = "Resource prefix used for all resources"
  value       = local.resource_prefix
}

output "random_suffix" {
  description = "Random suffix used for resource names"
  value       = random_string.suffix.result
}

# Security Information
output "security_automation_setup_complete" {
  description = "Confirmation that security automation setup is complete"
  value       = "Security automation infrastructure deployed successfully"
}

output "next_steps" {
  description = "Next steps for completing the setup"
  value = [
    "1. Subscribe to the SNS topic for notifications: ${aws_sns_topic.security_notifications.arn}",
    "2. Verify Security Hub is enabled and generating findings",
    "3. Test the automation with a sample security finding",
    "4. Review CloudWatch logs for Lambda function execution",
    "5. Configure additional notification endpoints as needed"
  ]
}