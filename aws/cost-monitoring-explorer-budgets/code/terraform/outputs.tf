# AWS Account ID where resources are deployed
output "aws_account_id" {
  description = "AWS Account ID where the budget monitoring resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# AWS Region where resources are deployed
output "aws_region" {
  description = "AWS Region where the budget monitoring resources are deployed"
  value       = data.aws_region.current.name
}

# Budget configuration details
output "budget_name" {
  description = "Name of the created AWS Budget"
  value       = aws_budgets_budget.monthly_cost_budget.name
}

output "budget_limit" {
  description = "Monthly budget limit in USD"
  value       = "$${aws_budgets_budget.monthly_cost_budget.limit_amount}"
}

output "budget_time_unit" {
  description = "Time unit for the budget (MONTHLY, QUARTERLY, ANNUALLY)"
  value       = aws_budgets_budget.monthly_cost_budget.time_unit
}

output "budget_type" {
  description = "Type of budget (COST, USAGE, SAVINGS_PLANS_UTILIZATION, etc.)"
  value       = aws_budgets_budget.monthly_cost_budget.budget_type
}

# Budget time period information
output "budget_start_date" {
  description = "Budget monitoring start date"
  value       = aws_budgets_budget.monthly_cost_budget.time_period_start
}

output "budget_end_date" {
  description = "Budget monitoring end date"
  value       = aws_budgets_budget.monthly_cost_budget.time_period_end
}

# SNS Topic details
output "sns_topic_name" {
  description = "Name of the SNS topic for budget alerts"
  value       = aws_sns_topic.budget_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for budget alerts"
  value       = aws_sns_topic.budget_alerts.arn
}

output "sns_topic_display_name" {
  description = "Display name of the SNS topic"
  value       = aws_sns_topic.budget_alerts.display_name
}

# Notification configuration
output "notification_email" {
  description = "Email address configured for budget notifications"
  value       = var.notification_email
  sensitive   = true
}

output "sns_subscription_arn" {
  description = "ARN of the SNS email subscription"
  value       = aws_sns_topic_subscription.budget_email_notification.arn
}

output "sns_subscription_status" {
  description = "Status of the SNS email subscription (PendingConfirmation, Confirmed, etc.)"
  value       = aws_sns_topic_subscription.budget_email_notification.confirmation_was_authenticated
}

# Alert threshold configuration
output "actual_alert_thresholds" {
  description = "Percentage thresholds configured for actual spending alerts"
  value       = var.actual_alert_thresholds
}

output "forecasted_alert_threshold" {
  description = "Percentage threshold configured for forecasted spending alert"
  value       = var.forecasted_alert_threshold
}

# Cost types configuration
output "budget_cost_types" {
  description = "Cost types included in budget calculations"
  value = {
    include_tax               = var.include_tax
    include_subscription      = var.include_subscription
    include_support          = var.include_support
    include_upfront          = var.include_upfront
    include_recurring        = var.include_recurring
    include_credit           = false
    include_discount         = true
    include_other_subscription = true
    include_refund           = false
    use_amortized            = false
    use_blended              = false
  }
}

# Resource identifiers for reference
output "random_suffix" {
  description = "Random suffix used in resource naming for uniqueness"
  value       = random_id.suffix.hex
}

# Cost Explorer information
output "cost_explorer_info" {
  description = "Information about AWS Cost Explorer integration"
  value = {
    console_url = "https://console.aws.amazon.com/cost-management/home?region=${data.aws_region.current.name}#/cost-explorer"
    description = "AWS Cost Explorer provides detailed cost and usage analysis with up to 13 months of historical data"
    api_cost    = "$0.01 per paginated request for Cost Explorer API usage"
  }
}

# Budget console URL for easy access
output "budget_console_url" {
  description = "AWS Console URL to view the created budget"
  value       = "https://console.aws.amazon.com/billing/home?region=${data.aws_region.current.name}#/budgets"
}

# Verification commands for manual testing
output "verification_commands" {
  description = "CLI commands to verify the budget and notifications are working"
  value = {
    describe_budget = "aws budgets describe-budget --account-id ${data.aws_caller_identity.current.account_id} --budget-name ${aws_budgets_budget.monthly_cost_budget.name}"
    list_notifications = "aws budgets describe-notifications-for-budget --account-id ${data.aws_caller_identity.current.account_id} --budget-name ${aws_budgets_budget.monthly_cost_budget.name}"
    check_sns_subscriptions = "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.budget_alerts.arn}"
    test_cost_explorer = "aws ce get-cost-and-usage --time-period Start=${local.first_of_month},End=${local.current_date} --granularity MONTHLY --metrics BlendedCost --group-by Type=DIMENSION,Key=SERVICE"
  }
}

# Important notes for users
output "important_notes" {
  description = "Important information about the deployed budget monitoring solution"
  value = {
    email_confirmation = "Check your email (${var.notification_email}) and confirm the SNS subscription to receive budget alerts"
    cost_explorer_note = "Cost Explorer is free through the console, but API requests cost $0.01 per paginated request"
    budget_updates = "Budget data is typically available within 24 hours of resource usage"
    forecasting_note = "Forecasted alerts use AWS machine learning to predict spending based on historical patterns"
    threshold_meaning = "Alert thresholds: 50% (early warning), 75% (concern), 90% (critical), 100% forecasted (predicted overage)"
  }
}