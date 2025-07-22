# Budget outputs
output "budget_name" {
  description = "Name of the created AWS Budget"
  value       = aws_budgets_budget.cost_budget.name
}

output "budget_arn" {
  description = "ARN of the created AWS Budget"
  value       = aws_budgets_budget.cost_budget.arn
}

output "budget_amount" {
  description = "Budget limit amount in USD"
  value       = aws_budgets_budget.cost_budget.limit_amount
}

output "budget_time_unit" {
  description = "Time unit for the budget"
  value       = aws_budgets_budget.cost_budget.time_unit
}

# SNS outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for budget alerts"
  value       = aws_sns_topic.budget_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for budget alerts"
  value       = aws_sns_topic.budget_alerts.name
}

# Lambda outputs
output "lambda_function_name" {
  description = "Name of the Lambda function for budget actions"
  value       = aws_lambda_function.budget_action.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for budget actions"
  value       = aws_lambda_function.budget_action.arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# IAM Role outputs
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "budget_action_role_arn" {
  description = "ARN of the budget action role"
  value       = aws_iam_role.budget_action_role.arn
}

# Policy outputs
output "lambda_policy_arn" {
  description = "ARN of the Lambda execution policy"
  value       = aws_iam_policy.lambda_policy.arn
}

output "budget_restriction_policy_arn" {
  description = "ARN of the budget restriction policy"
  value       = aws_iam_policy.budget_restriction_policy.arn
}

# Account information
output "aws_account_id" {
  description = "AWS Account ID where resources are created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are created"
  value       = data.aws_region.current.name
}

# Notification configuration
output "notification_email" {
  description = "Email address configured for budget notifications"
  value       = var.notification_email
  sensitive   = true
}

output "notification_thresholds" {
  description = "Configured notification thresholds"
  value = [
    for threshold in var.notification_thresholds : {
      threshold           = threshold.threshold
      threshold_type      = threshold.threshold_type
      notification_type   = threshold.notification_type
      comparison_operator = threshold.comparison_operator
    }
  ]
}

# Resource naming outputs
output "resource_name_prefix" {
  description = "Common prefix used for resource naming"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.random_suffix
}

# Instructions and next steps
output "deployment_instructions" {
  description = "Instructions for completing the budget alerts setup"
  value = <<-EOT
    Budget Alerts Infrastructure Deployed Successfully!
    
    Next Steps:
    1. Check your email (${var.notification_email}) and confirm the SNS subscription
    2. Test the setup by creating EC2 instances with 'Environment=Development' tags
    3. Monitor your budget in the AWS Console: https://console.aws.amazon.com/billing/home#/budgets
    4. View Lambda logs: https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logStream:group=/aws/lambda/${aws_lambda_function.budget_action.function_name}
    
    Budget Configuration:
    - Budget Name: ${aws_budgets_budget.cost_budget.name}
    - Amount: $${aws_budgets_budget.cost_budget.limit_amount} ${aws_budgets_budget.cost_budget.time_unit}
    - Notifications at: ${join(", ", [for t in var.notification_thresholds : "${t.threshold}% (${t.notification_type})"])}
    
    Automated Actions:
    - Development EC2 instances will be stopped when budget thresholds are exceeded
    - Notifications sent to: ${var.notification_email}
    - Lambda function: ${aws_lambda_function.budget_action.function_name}
  EOT
}

# Terraform state information
output "terraform_workspace" {
  description = "Terraform workspace used for this deployment"
  value       = terraform.workspace
}