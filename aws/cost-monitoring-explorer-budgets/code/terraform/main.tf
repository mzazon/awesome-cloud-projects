# Data source to get current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed names and configurations
locals {
  # Generate unique names with random suffix
  budget_name    = "${var.budget_name_prefix}-${random_id.suffix.hex}"
  sns_topic_name = "${var.sns_topic_prefix}-${random_id.suffix.hex}"
  
  # Get current date information for budget time period
  current_date    = formatdate("YYYY-MM-DD", timestamp())
  first_of_month  = formatdate("YYYY-MM-01", timestamp())
  
  # Budget end date (set far in future for ongoing monitoring)
  budget_end_date = "2087-06-15"
  
  # Combine default and additional tags
  common_tags = merge(
    {
      BudgetName    = local.budget_name
      SNSTopicName  = local.sns_topic_name
      CreatedDate   = local.current_date
    },
    var.additional_tags
  )
}

# SNS Topic for budget notifications
resource "aws_sns_topic" "budget_alerts" {
  name         = local.sns_topic_name
  display_name = "Budget Alert Notifications"
  
  tags = merge(
    local.common_tags,
    {
      Name        = local.sns_topic_name
      Description = "SNS topic for AWS budget alert notifications"
    }
  )
}

# SNS Topic Policy to allow AWS Budgets service to publish messages
resource "aws_sns_topic_policy" "budget_alerts_policy" {
  arn = aws_sns_topic.budget_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "budget-sns-policy"
    Statement = [
      {
        Sid    = "AllowBudgetsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action = [
          "SNS:Publish"
        ]
        Resource = aws_sns_topic.budget_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# SNS Topic Subscription for email notifications
resource "aws_sns_topic_subscription" "budget_email_notification" {
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
  
  depends_on = [aws_sns_topic_policy.budget_alerts_policy]
}

# AWS Budget for monthly cost monitoring
resource "aws_budgets_budget" "monthly_cost_budget" {
  name         = local.budget_name
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  # Time period configuration
  time_period_start = "${local.first_of_month}T00:00:00Z"
  time_period_end   = "${local.budget_end_date}T00:00:00Z"
  
  # Cost filters (empty object means all costs)
  cost_filters = {}
  
  # Cost types configuration - what costs to include in budget calculations
  cost_types {
    include_credit             = false  # Exclude credits to show actual spending
    include_discount           = true   # Include discounts for accurate cost tracking
    include_other_subscription = true   # Include other subscription costs
    include_recurring          = var.include_recurring
    include_refund            = false   # Exclude refunds to show net spending
    include_subscription      = var.include_subscription
    include_support           = var.include_support
    include_tax               = var.include_tax
    include_upfront           = var.include_upfront
    use_amortized             = false   # Use blended costs
    use_blended               = false   # Use unblended costs for accuracy
  }
  
  # Dynamic notification blocks for actual spending thresholds
  dynamic "notification" {
    for_each = var.actual_alert_thresholds
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                 = notification.value
      threshold_type            = "PERCENTAGE"
      notification_type         = "ACTUAL"
      subscriber_email_addresses = []  # Email handled by SNS subscription
      subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
    }
  }
  
  # Forecasted spending notification
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.forecasted_alert_threshold
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = []  # Email handled by SNS subscription
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }
  
  # Ensure SNS topic and policy are created before budget
  depends_on = [
    aws_sns_topic.budget_alerts,
    aws_sns_topic_policy.budget_alerts_policy
  ]
  
  tags = merge(
    local.common_tags,
    {
      Name        = local.budget_name
      Description = "Monthly cost monitoring budget with graduated alerts"
      BudgetLimit = "$${var.budget_limit}"
    }
  )
}