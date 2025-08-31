# Output values for budget monitoring infrastructure
# These outputs provide important information about created resources

output "budget_name" {
  description = "Name of the created AWS Budget"
  value       = aws_budgets_budget.monthly_cost_budget.name
}

output "budget_id" {
  description = "ID of the created AWS Budget"
  value       = aws_budgets_budget.monthly_cost_budget.id
}

output "budget_limit" {
  description = "Budget limit amount and currency"
  value = {
    amount = aws_budgets_budget.monthly_cost_budget.limit_amount
    unit   = aws_budgets_budget.monthly_cost_budget.limit_unit
  }
}

output "budget_time_unit" {
  description = "Time unit for the budget period"
  value       = aws_budgets_budget.monthly_cost_budget.time_unit
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for budget notifications"
  value       = aws_sns_topic.budget_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for budget notifications"
  value       = aws_sns_topic.budget_alerts.name
}

output "notification_email" {
  description = "Email address configured for budget notifications"
  value       = var.notification_email
  sensitive   = true
}

output "notification_thresholds" {
  description = "Configured notification thresholds"
  value = {
    actual_80_percent    = var.actual_threshold_80
    actual_100_percent   = var.actual_threshold_100
    forecast_80_percent  = var.forecast_threshold_80
  }
}

output "aws_account_id" {
  description = "AWS Account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources were created"
  value       = var.aws_region
}

output "budget_arn" {
  description = "ARN of the created budget"
  value       = "arn:aws:budgets::${data.aws_caller_identity.current.account_id}:budget/${aws_budgets_budget.monthly_cost_budget.name}"
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for budget events"
  value       = aws_cloudwatch_log_group.budget_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for budget events"
  value       = aws_cloudwatch_log_group.budget_logs.arn
}

output "kms_key_id" {
  description = "ID of the KMS key used for logs encryption"
  value       = aws_kms_key.budget_logs_key.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for logs encryption"
  value       = aws_kms_key.budget_logs_key.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for logs encryption"
  value       = aws_kms_alias.budget_logs_key_alias.name
}

output "sns_subscription_arn" {
  description = "ARN of the email subscription to SNS topic"
  value       = aws_sns_topic_subscription.email_notification.arn
}

output "deployment_info" {
  description = "Information about the deployment"
  value = {
    environment    = var.environment
    deployed_at    = timestamp()
    terraform_version = "terraform >= 1.0"
    aws_provider_version = "~> 5.0"
    random_suffix = random_id.suffix.hex
  }
}

output "cost_tracking_configuration" {
  description = "Configuration details for cost tracking"
  value = {
    include_credits   = var.include_credits
    include_discounts = var.include_discounts
    include_support   = var.include_support_costs
    include_taxes     = var.include_taxes
    time_unit        = var.budget_time_unit
  }
}

output "next_steps" {
  description = "Important next steps after deployment"
  value = {
    email_confirmation = "Check your email (${var.notification_email}) and confirm the SNS subscription"
    budget_console_url = "https://console.aws.amazon.com/billing/home#/budgets"
    sns_console_url    = "https://console.aws.amazon.com/sns/v3/home?region=${var.aws_region}#/topics"
    test_command       = "aws sns publish --topic-arn ${aws_sns_topic.budget_alerts.arn} --message 'Test notification from budget monitoring system' --subject 'Budget Alert Test'"
  }
}