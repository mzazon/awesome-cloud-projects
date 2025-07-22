# Output values for the CodeCommit Git workflows infrastructure

# Repository information
output "repository_name" {
  description = "Name of the created CodeCommit repository"
  value       = aws_codecommit_repository.main.repository_name
}

output "repository_arn" {
  description = "ARN of the created CodeCommit repository"
  value       = aws_codecommit_repository.main.arn
}

output "repository_clone_url_http" {
  description = "HTTP clone URL for the repository"
  value       = aws_codecommit_repository.main.clone_url_http
}

output "repository_clone_url_ssh" {
  description = "SSH clone URL for the repository"
  value       = aws_codecommit_repository.main.clone_url_ssh
}

# SNS Topic ARNs
output "sns_topic_pull_requests" {
  description = "ARN of the SNS topic for pull request notifications"
  value       = aws_sns_topic.pull_requests.arn
}

output "sns_topic_merges" {
  description = "ARN of the SNS topic for merge notifications"
  value       = aws_sns_topic.merges.arn
}

output "sns_topic_quality_gates" {
  description = "ARN of the SNS topic for quality gate notifications"
  value       = aws_sns_topic.quality_gates.arn
}

output "sns_topic_security_alerts" {
  description = "ARN of the SNS topic for security alert notifications"
  value       = aws_sns_topic.security_alerts.arn
}

# Lambda Function information
output "lambda_pull_request_function_name" {
  description = "Name of the pull request automation Lambda function"
  value       = aws_lambda_function.pull_request_automation.function_name
}

output "lambda_pull_request_function_arn" {
  description = "ARN of the pull request automation Lambda function"
  value       = aws_lambda_function.pull_request_automation.arn
}

output "lambda_quality_gate_function_name" {
  description = "Name of the quality gate automation Lambda function"
  value       = aws_lambda_function.quality_gate_automation.function_name
}

output "lambda_quality_gate_function_arn" {
  description = "ARN of the quality gate automation Lambda function"
  value       = aws_lambda_function.quality_gate_automation.arn
}

output "lambda_branch_protection_function_name" {
  description = "Name of the branch protection automation Lambda function"
  value       = aws_lambda_function.branch_protection_automation.function_name
}

output "lambda_branch_protection_function_arn" {
  description = "ARN of the branch protection automation Lambda function"
  value       = aws_lambda_function.branch_protection_automation.arn
}

# IAM Role information
output "lambda_execution_role_name" {
  description = "Name of the IAM role for Lambda function execution"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda function execution"
  value       = aws_iam_role.lambda_role.arn
}

# EventBridge Rule information
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for pull request events"
  value       = aws_cloudwatch_event_rule.pull_request_events.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for pull request events"
  value       = aws_cloudwatch_event_rule.pull_request_events.arn
}

# Approval Rule Template information (conditional)
output "approval_rule_template_name" {
  description = "Name of the approval rule template (if created)"
  value       = length(aws_codecommit_approval_rule_template.enterprise_template) > 0 ? aws_codecommit_approval_rule_template.enterprise_template[0].name : null
}

output "approval_rule_template_id" {
  description = "ID of the approval rule template (if created)"
  value       = length(aws_codecommit_approval_rule_template.enterprise_template) > 0 ? aws_codecommit_approval_rule_template.enterprise_template[0].approval_rule_template_id : null
}

# CloudWatch Dashboard information (conditional)
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard (if created)"
  value       = var.enable_dashboard ? aws_cloudwatch_dashboard.git_workflow[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard (if created)"
  value = var.enable_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.git_workflow[0].dashboard_name}" : null
}

# CloudWatch Log Groups
output "log_group_pull_request" {
  description = "CloudWatch log group for pull request Lambda function"
  value       = aws_cloudwatch_log_group.pull_request_lambda_logs.name
}

output "log_group_quality_gate" {
  description = "CloudWatch log group for quality gate Lambda function"
  value       = aws_cloudwatch_log_group.quality_gate_lambda_logs.name
}

output "log_group_branch_protection" {
  description = "CloudWatch log group for branch protection Lambda function"
  value       = aws_cloudwatch_log_group.branch_protection_lambda_logs.name
}

# Configuration summary
output "protected_branches" {
  description = "List of protected branches configured"
  value       = var.protected_branches
}

output "required_approvals" {
  description = "Number of required approvals for pull requests"
  value       = var.required_approvals
}

output "approval_pool_size" {
  description = "Number of users in the approval pool"
  value       = length(local.approval_pool_members)
}

# Resource naming information
output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = local.resource_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource names"
  value       = random_string.suffix.result
}

# Email subscription information (conditional)
output "email_subscriptions_created" {
  description = "Whether email subscriptions were created for SNS topics"
  value       = var.enable_email_notifications
}

output "notification_email_count" {
  description = "Number of email addresses configured for notifications"
  value       = length(var.notification_emails)
}

# Usage instructions
output "next_steps" {
  description = "Next steps to complete the setup"
  value = <<-EOT
    # Clone the repository:
    git clone ${aws_codecommit_repository.main.clone_url_http}
    
    # Set up Git credentials for CodeCommit:
    aws codecommit create-repository --repository-name ${aws_codecommit_repository.main.repository_name}
    
    # Configure email notifications (if not already done):
    %{if !var.enable_email_notifications~}
    aws sns subscribe --topic-arn ${aws_sns_topic.pull_requests.arn} --protocol email --notification-endpoint your-email@example.com
    aws sns subscribe --topic-arn ${aws_sns_topic.merges.arn} --protocol email --notification-endpoint your-email@example.com
    aws sns subscribe --topic-arn ${aws_sns_topic.quality_gates.arn} --protocol email --notification-endpoint your-email@example.com
    aws sns subscribe --topic-arn ${aws_sns_topic.security_alerts.arn} --protocol email --notification-endpoint your-email@example.com
    %{endif~}
    
    # View the monitoring dashboard:
    %{if var.enable_dashboard~}
    ${try(aws_cloudwatch_dashboard.git_workflow[0].dashboard_name, "Dashboard not created")}
    %{else~}
    Dashboard not enabled. Set enable_dashboard = true to create monitoring dashboard.
    %{endif~}
  EOT
}