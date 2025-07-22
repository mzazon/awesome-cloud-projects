# Outputs for Infrastructure Management Automation
# These outputs provide essential information about the deployed resources

# ==============================================================================
# RESOURCE IDENTIFIERS
# ==============================================================================

output "automation_role_arn" {
  description = "ARN of the IAM role used for automation"
  value       = aws_iam_role.automation_role.arn
}

output "automation_role_name" {
  description = "Name of the IAM role used for automation"
  value       = aws_iam_role.automation_role.name
}

output "lambda_function_name" {
  description = "Name of the Lambda function for automation orchestration"
  value       = aws_lambda_function.automation_lambda.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for automation orchestration"
  value       = aws_lambda_function.automation_lambda.arn
}

output "automation_document_name" {
  description = "Name of the Systems Manager automation document"
  value       = aws_ssm_document.automation_document.name
}

output "automation_document_arn" {
  description = "ARN of the Systems Manager automation document"
  value       = aws_ssm_document.automation_document.arn
}

# ==============================================================================
# MONITORING AND LOGGING
# ==============================================================================

output "log_group_name" {
  description = "Name of the CloudWatch log group for automation logs"
  value       = aws_cloudwatch_log_group.automation_logs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group for automation logs"
  value       = aws_cloudwatch_log_group.automation_logs.arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard (if enabled)"
  value       = var.enable_dashboard ? aws_cloudwatch_dashboard.automation_dashboard[0].dashboard_name : null
}

output "dashboard_url" {
  description = "URL to access the CloudWatch dashboard (if enabled)"
  value       = var.enable_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.automation_dashboard[0].dashboard_name}" : null
}

# ==============================================================================
# SCHEDULING AND EVENTS
# ==============================================================================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scheduling"
  value       = aws_cloudwatch_event_rule.automation_schedule.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for scheduling"
  value       = aws_cloudwatch_event_rule.automation_schedule.arn
}

output "schedule_expression" {
  description = "The schedule expression used for automation"
  value       = aws_cloudwatch_event_rule.automation_schedule.schedule_expression
}

# ==============================================================================
# NOTIFICATIONS
# ==============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications (if enabled)"
  value       = var.notification_email != "" ? aws_sns_topic.automation_alerts[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications (if enabled)"
  value       = var.notification_email != "" ? aws_sns_topic.automation_alerts[0].name : null
}

# ==============================================================================
# ALARMS
# ==============================================================================

output "automation_error_alarm_name" {
  description = "Name of the CloudWatch alarm for automation errors (if enabled)"
  value       = var.enable_alarms ? aws_cloudwatch_metric_alarm.automation_errors[0].alarm_name : null
}

output "lambda_error_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda errors (if enabled)"
  value       = var.enable_alarms ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : null
}

# ==============================================================================
# USAGE INSTRUCTIONS
# ==============================================================================

output "getting_started_commands" {
  description = "Commands to get started with the automation"
  value = {
    test_automation = "aws ssm start-automation-execution --document-name ${aws_ssm_document.automation_document.name} --parameters 'Region=${data.aws_region.current.name}'"
    test_lambda = "aws lambda invoke --function-name ${aws_lambda_function.automation_lambda.function_name} --payload '{}' response.json"
    view_logs = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.automation_logs.name} --order-by LastEventTime --descending --max-items 5"
    view_executions = "aws ssm describe-automation-executions --filters 'Key=DocumentNamePrefix,Values=${aws_ssm_document.automation_document.name}'"
  }
}

output "cloudshell_setup_script" {
  description = "PowerShell script content for CloudShell setup"
  value = <<-EOF
# PowerShell script to run in AWS CloudShell
# Save this as infrastructure-health-check.ps1 and execute from CloudShell

${local.powershell_script}
EOF
}

# ==============================================================================
# RESOURCE SUMMARY
# ==============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    aws_region = data.aws_region.current.name
    aws_account_id = data.aws_caller_identity.current.account_id
    project_name = var.project_name
    environment = var.environment
    resource_suffix = local.resource_suffix
    lambda_function = aws_lambda_function.automation_lambda.function_name
    automation_document = aws_ssm_document.automation_document.name
    log_group = aws_cloudwatch_log_group.automation_logs.name
    schedule_expression = var.schedule_expression
    monitoring_enabled = var.enable_dashboard
    alarms_enabled = var.enable_alarms
    notifications_enabled = var.notification_email != ""
  }
}

# ==============================================================================
# NEXT STEPS
# ==============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test the automation by running: aws ssm start-automation-execution --document-name ${aws_ssm_document.automation_document.name}",
    "2. Check CloudWatch logs at: ${aws_cloudwatch_log_group.automation_logs.name}",
    "3. View the automation dashboard at: https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${var.enable_dashboard ? local.dashboard_name : "dashboard-not-enabled"}",
    "4. Open CloudShell and create the PowerShell script using the content in the 'cloudshell_setup_script' output",
    "5. Verify the scheduled execution works by waiting for the next trigger time",
    var.notification_email != "" ? "6. Check your email for SNS subscription confirmation" : "6. Configure email notifications by setting the 'notification_email' variable and re-deploying"
  ]
}

# ==============================================================================
# TROUBLESHOOTING INFORMATION
# ==============================================================================

output "troubleshooting_info" {
  description = "Information for troubleshooting common issues"
  value = {
    common_commands = {
      check_automation_status = "aws ssm describe-automation-executions --filters 'Key=DocumentNamePrefix,Values=${aws_ssm_document.automation_document.name}'"
      view_lambda_logs = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name}"
      test_lambda_manually = "aws lambda invoke --function-name ${aws_lambda_function.automation_lambda.function_name} --payload '{}' response.json && cat response.json"
      check_eventbridge_rules = "aws events list-rules --name-prefix ${aws_cloudwatch_event_rule.automation_schedule.name}"
    }
    resource_arns = {
      automation_role = aws_iam_role.automation_role.arn
      lambda_function = aws_lambda_function.automation_lambda.arn
      automation_document = aws_ssm_document.automation_document.arn
      eventbridge_rule = aws_cloudwatch_event_rule.automation_schedule.arn
    }
    important_notes = [
      "Ensure you have appropriate IAM permissions to view EC2 instances and S3 buckets",
      "PowerShell scripts require AWS Tools for PowerShell modules to be available in CloudShell",
      "Check CloudWatch logs if automation executions fail",
      "Verify EventBridge rule is enabled and has the correct schedule expression"
    ]
  }
}