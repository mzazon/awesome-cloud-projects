# Budget Monitoring Infrastructure with AWS Budgets and SNS
# This Terraform configuration creates comprehensive budget monitoring with automated notifications

# Get current AWS account ID and caller identity
data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Calculate budget start time (first day of current month)
  budget_start_time = formatdate("YYYY-MM-01", timestamp())
  
  # Resource names with random suffix
  budget_name    = "${var.budget_name_prefix}-${random_id.suffix.hex}"
  sns_topic_name = "${var.sns_topic_name_prefix}-${random_id.suffix.hex}"
  
  # Common tags for all resources
  common_tags = {
    BudgetName = local.budget_name
    CreatedBy  = "terraform"
    Purpose    = "cost-monitoring"
  }
}

# SNS Topic for Budget Notifications
# Amazon SNS provides reliable, scalable messaging service for budget alerts
resource "aws_sns_topic" "budget_alerts" {
  name         = local.sns_topic_name
  display_name = "Budget Alerts - ${var.environment}"
  
  # Enable server-side encryption for security
  kms_master_key_id = "alias/aws/sns"
  
  # Delivery policy for message retry configuration
  delivery_policy = jsonencode({
    "http" = {
      "defaultHealthyRetryPolicy" = {
        "minDelayTarget"     = 20
        "maxDelayTarget"     = 20
        "numRetries"         = 3
        "numMaxDelayRetries" = 0
        "numMinDelayRetries" = 0
        "numNoDelayRetries"  = 0
        "backoffFunction"    = "linear"
      }
      "disableSubscriptionOverrides" = false
    }
  })

  tags = merge(local.common_tags, {
    Name = local.sns_topic_name
    Type = "notification"
  })
}

# SNS Topic Policy for AWS Budgets Service
# This policy allows AWS Budgets service to publish messages to the SNS topic
resource "aws_sns_topic_policy" "budget_alerts_policy" {
  arn = aws_sns_topic.budget_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "budget-alerts-topic-policy"
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

# Email Subscription to SNS Topic
# This creates an email subscription that requires manual confirmation
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email

  # Optional: Set delivery policy for email subscriptions
  delivery_policy = jsonencode({
    "healthyRetryPolicy" = {
      "minDelayTarget"     = 20
      "maxDelayTarget"     = 20
      "numRetries"         = 3
      "numMaxDelayRetries" = 0
      "numMinDelayRetries" = 0
      "numNoDelayRetries"  = 0
      "backoffFunction"    = "linear"
    }
  })
}

# AWS Budget with Comprehensive Cost Tracking
# This budget tracks all AWS costs with multiple notification thresholds
resource "aws_budgets_budget" "monthly_cost_budget" {
  name       = local.budget_name
  budget_type = "COST"
  limit_amount = var.budget_limit_amount
  limit_unit   = "USD"
  time_unit    = var.budget_time_unit
  
  # Budget period configuration
  time_period_start = local.budget_start_time
  time_period_end   = "2087-06-15_00:00"  # Far future end date
  
  # Comprehensive cost tracking configuration
  cost_filters = {}  # Empty means include all services
  
  # Cost types configuration for comprehensive tracking
  cost_filter {
    name   = "LinkedAccount"
    values = [data.aws_caller_identity.current.account_id]
  }

  # Notification for 80% of actual spending
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.actual_threshold_80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = []
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  # Notification for 100% of actual spending (budget exceeded)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.actual_threshold_100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = []
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  # Notification for 80% of forecasted spending
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.forecast_threshold_80
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = []
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  # Depends on SNS topic policy to ensure proper permissions
  depends_on = [
    aws_sns_topic_policy.budget_alerts_policy
  ]

  tags = merge(local.common_tags, {
    Name        = local.budget_name
    Type        = "budget"
    BudgetLimit = "${var.budget_limit_amount} USD"
    TimeUnit    = var.budget_time_unit
  })
}

# CloudWatch Log Group for Budget Events (Optional Enhancement)
# This can be used for centralized logging of budget events
resource "aws_cloudwatch_log_group" "budget_logs" {
  name              = "/aws/budgets/${local.budget_name}"
  retention_in_days = 30
  
  # Enable encryption for log data
  kms_key_id = aws_kms_key.budget_logs_key.arn

  tags = merge(local.common_tags, {
    Name = "budget-logs-${random_id.suffix.hex}"
    Type = "logging"
  })
}

# KMS Key for CloudWatch Logs Encryption
# Provides encryption for budget-related log data
resource "aws_kms_key" "budget_logs_key" {
  description             = "KMS key for budget monitoring logs encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/budgets/${local.budget_name}"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "budget-logs-key-${random_id.suffix.hex}"
    Type = "encryption"
  })
}

# KMS Key Alias for easier identification
resource "aws_kms_alias" "budget_logs_key_alias" {
  name          = "alias/budget-logs-${random_id.suffix.hex}"
  target_key_id = aws_kms_key.budget_logs_key.key_id
}