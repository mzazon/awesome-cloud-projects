# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the created AWS Resource Group"
  value       = aws_resourcegroups_group.main.name
}

output "resource_group_arn" {
  description = "ARN of the created AWS Resource Group"
  value       = aws_resourcegroups_group.main.arn
}

# SNS Topic Outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.resource_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = aws_sns_topic.resource_alerts.name
}

# IAM Role Outputs
output "automation_role_arn" {
  description = "ARN of the IAM role for Systems Manager automation"
  value       = aws_iam_role.automation_role.arn
}

output "automation_role_name" {
  description = "Name of the IAM role for Systems Manager automation"
  value       = aws_iam_role.automation_role.name
}

# Systems Manager Document Outputs
output "maintenance_document_name" {
  description = "Name of the Systems Manager maintenance document"
  value       = var.enable_automation_documents ? aws_ssm_document.resource_group_maintenance[0].name : "disabled"
}

output "tagging_document_name" {
  description = "Name of the Systems Manager automated tagging document"
  value       = var.enable_automation_documents ? aws_ssm_document.automated_resource_tagging[0].name : "disabled"
}

# CloudWatch Outputs
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.resource_monitoring.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.resource_monitoring.dashboard_name}"
}

output "cpu_alarm_name" {
  description = "Name of the CPU utilization CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu.alarm_name
}

output "health_check_alarm_name" {
  description = "Name of the health check CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.health_check.alarm_name
}

# Budget Outputs
output "budget_name" {
  description = "Name of the AWS Budget for cost tracking"
  value       = aws_budgets_budget.resource_group_budget.name
}

output "budget_limit" {
  description = "Monthly budget limit in USD"
  value       = "${var.monthly_budget_limit} USD"
}

# Cost Anomaly Detection Outputs
output "anomaly_detector_arn" {
  description = "ARN of the cost anomaly detector"
  value       = var.enable_cost_anomaly_detection ? aws_ce_anomaly_detector.resource_group_anomaly[0].arn : "disabled"
}

# EventBridge Outputs
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for automated tagging"
  value       = var.enable_eventbridge_tagging_rules ? aws_cloudwatch_event_rule.auto_tag_resources[0].name : "disabled"
}

output "eventbridge_role_arn" {
  description = "ARN of the EventBridge service role"
  value       = var.enable_eventbridge_tagging_rules ? aws_iam_role.eventbridge_role[0].arn : "disabled"
}

# Resource Information
output "aws_account_id" {
  description = "AWS Account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources were created"
  value       = data.aws_region.current.name
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Tag Information
output "resource_tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    resource_group = "aws resource-groups get-group --group-name ${aws_resourcegroups_group.main.name}"
    list_resources = "aws resource-groups list-group-resources --group-name ${aws_resourcegroups_group.main.name}"
    dashboard_url  = "aws cloudwatch get-dashboard --dashboard-name ${aws_cloudwatch_dashboard.resource_monitoring.dashboard_name}"
    alarm_status   = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.high_cpu.alarm_name}"
    budget_info    = "aws budgets describe-budget --account-id ${data.aws_caller_identity.current.account_id} --budget-name ${aws_budgets_budget.resource_group_budget.name}"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Confirm SNS email subscription by checking your email",
    "2. Tag existing resources with Environment=${var.environment} and Application=${var.application}",
    "3. View the CloudWatch dashboard at the provided URL",
    "4. Test automation by running: aws ssm start-automation-execution --document-name ${var.enable_automation_documents ? aws_ssm_document.resource_group_maintenance[0].name : "maintenance-document"} --parameters ResourceGroupName=${aws_resourcegroups_group.main.name}",
    "5. Monitor cost usage in the AWS Budgets console"
  ]
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown"
  value = {
    sns_topic          = "$0.50 (per 1M requests)"
    cloudwatch_alarms  = "$0.20 per alarm (${length([aws_cloudwatch_metric_alarm.high_cpu, aws_cloudwatch_metric_alarm.health_check])} alarms = $0.40)"
    dashboard          = "$3.00 per dashboard"
    log_group          = "$0.50 per GB ingested"
    budget             = "Free (first 2 budgets)"
    systems_manager    = "$0.00 (automation execution: $0.0025 per step)"
    total_estimated    = "~$4.00-6.00 per month (excluding data transfer and usage-based charges)"
  }
}