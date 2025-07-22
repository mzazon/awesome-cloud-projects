# Main Terraform configuration for AWS Cost Optimization Hub and Budgets
# This file creates a comprehensive cost optimization workflow with automated monitoring,
# budgets, anomaly detection, and Lambda-based automation

# Data sources for current AWS account and caller identity
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Generate random suffix for resource names to ensure uniqueness
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  name_prefix           = "cost-optimization"
  resource_suffix      = random_string.suffix.result
  account_id           = data.aws_caller_identity.current.account_id
  partition            = data.aws_partition.current.partition
  current_date         = formatdate("YYYY-MM-DD", timestamp())
  next_month           = formatdate("YYYY-MM-DD", timeadd(timestamp(), "720h"))
  
  # Common tags applied to all resources
  common_tags = {
    Environment = var.environment
    Project     = "cost-optimization-workflows"
    ManagedBy   = "terraform"
    Owner       = var.owner
    Resource    = "${local.name_prefix}-${local.resource_suffix}"
  }
}

#############################################
# Cost Optimization Hub Configuration
#############################################

# Enable Cost Optimization Hub with specified preferences
resource "aws_costoptimizationhub_preferences" "main" {
  count = var.cost_optimization_hub_enabled ? 1 : 0
  
  savings_estimation_mode              = var.savings_estimation_mode
  member_account_discount_visibility   = var.member_account_discount_visibility
}

#############################################
# SNS Topic for Notifications
#############################################

# SNS topic for cost optimization and budget alerts
resource "aws_sns_topic" "cost_alerts" {
  name         = "${local.name_prefix}-alerts-${local.resource_suffix}"
  display_name = "Cost Optimization Alerts"
  
  # Enable encryption for sensitive cost data
  kms_master_key_id = "alias/aws/sns"
  
  tags = merge(local.common_tags, {
    Description = "SNS topic for cost optimization and budget notifications"
  })
}

# SNS topic policy to allow AWS Budgets service to publish messages
resource "aws_sns_topic_policy" "cost_alerts" {
  arn = aws_sns_topic.cost_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action = "SNS:Publish"
        Resource = aws_sns_topic.cost_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "ce.amazonaws.com"
        }
        Action = "SNS:Publish"
        Resource = aws_sns_topic.cost_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# Email subscription to the SNS topic
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

#############################################
# AWS Budgets Configuration
#############################################

# Monthly cost budget with automated notifications
resource "aws_budgets_budget" "monthly_cost" {
  name         = "${local.name_prefix}-monthly-cost-${local.resource_suffix}"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_amount)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  time_period_start = "${substr(local.current_date, 0, 7)}-01_00:00"
  time_period_end   = "2087-06-15_00:00"
  
  # Include all cost types for comprehensive monitoring
  cost_types {
    include_credit             = true
    include_discount           = true
    include_other_subscription = true
    include_recurring          = true
    include_refund             = true
    include_subscription       = true
    include_support            = true
    include_tax                = true
    include_upfront            = true
    use_blended               = false
    use_amortized             = false
  }
  
  # Notification for actual spending threshold
  notification {
    comparison_operator         = "GREATER_THAN"
    threshold                  = var.monthly_budget_threshold
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }
  
  # Forecasted spending notification at 90%
  notification {
    comparison_operator         = "GREATER_THAN"
    threshold                  = 90
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }
  
  tags = merge(local.common_tags, {
    Description = "Monthly cost budget for comprehensive spend monitoring"
    BudgetType  = "Cost"
  })
}

# EC2 usage budget for monitoring compute hours
resource "aws_budgets_budget" "ec2_usage" {
  name         = "${local.name_prefix}-ec2-usage-${local.resource_suffix}"
  budget_type  = "USAGE"
  limit_amount = tostring(var.ec2_usage_budget_hours)
  limit_unit   = "HOURS"
  time_unit    = "MONTHLY"
  
  time_period_start = "${substr(local.current_date, 0, 7)}-01_00:00"
  time_period_end   = "2087-06-15_00:00"
  
  # Filter for EC2 compute services only
  cost_filter {
    name = "Service"
    values = ["Amazon Elastic Compute Cloud - Compute"]
  }
  
  # Forecasted usage notification at 90%
  notification {
    comparison_operator         = "GREATER_THAN"
    threshold                  = 90
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }
  
  tags = merge(local.common_tags, {
    Description = "EC2 usage budget for compute capacity monitoring"
    BudgetType  = "Usage"
    Service     = "EC2"
  })
}

# Reserved Instance utilization budget
resource "aws_budgets_budget" "ri_utilization" {
  name         = "${local.name_prefix}-ri-utilization-${local.resource_suffix}"
  budget_type  = "RI_UTILIZATION"
  limit_amount = "100"
  limit_unit   = "PERCENTAGE"
  time_unit    = "MONTHLY"
  
  time_period_start = "${substr(local.current_date, 0, 7)}-01_00:00"
  time_period_end   = "2087-06-15_00:00"
  
  # Cost types configuration required for RI budgets
  cost_types {
    include_credit             = false
    include_discount           = false
    include_other_subscription = false
    include_recurring          = false
    include_refund             = false
    include_subscription       = true
    include_support            = false
    include_tax                = false
    include_upfront            = false
    use_blended               = false
    use_amortized             = false
  }
  
  # Filter for EC2 services (required for RI utilization budgets)
  cost_filter {
    name = "Service"
    values = ["Amazon Elastic Compute Cloud - Compute"]
  }
  
  # Alert when RI utilization falls below threshold
  notification {
    comparison_operator         = "LESS_THAN"
    threshold                  = var.ri_utilization_threshold
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }
  
  tags = merge(local.common_tags, {
    Description = "Reserved Instance utilization monitoring"
    BudgetType  = "RI_Utilization"
  })
}

#############################################
# Budget Actions (Optional)
#############################################

# IAM role for budget actions
resource "aws_iam_role" "budget_actions" {
  count = var.enable_budget_actions ? 1 : 0
  
  name = "${local.name_prefix}-budget-actions-role-${local.resource_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Description = "IAM role for automated budget actions"
  })
}

# IAM policy for budget restriction actions
resource "aws_iam_policy" "budget_restriction" {
  count = var.enable_budget_actions ? 1 : 0
  
  name        = "${local.name_prefix}-budget-restriction-policy-${local.resource_suffix}"
  description = "Policy to restrict resource provisioning when budget thresholds are exceeded"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "ec2:StartInstances",
          "rds:CreateDBInstance",
          "rds:CreateDBCluster"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Description = "Policy for automated cost control actions"
  })
}

# Attach policy to budget actions role
resource "aws_iam_role_policy_attachment" "budget_actions" {
  count = var.enable_budget_actions ? 1 : 0
  
  role       = aws_iam_role.budget_actions[0].name
  policy_arn = aws_iam_policy.budget_restriction[0].arn
}

#############################################
# Cost Anomaly Detection
#############################################

# Cost anomaly detector for monitored services
resource "aws_ce_anomaly_monitor" "service_monitor" {
  name          = "${local.name_prefix}-service-monitor-${local.resource_suffix}"
  monitor_type  = "DIMENSIONAL"
  
  monitor_specification = jsonencode({
    Dimension = "SERVICE"
    Key       = "SERVICE"
    Values    = var.monitored_services
  })
  
  tags = merge(local.common_tags, {
    Description = "Cost anomaly monitor for key AWS services"
    MonitorType = "Service"
  })
}

# Cost anomaly subscription for notifications
resource "aws_ce_anomaly_subscription" "main" {
  name      = "${local.name_prefix}-anomaly-subscription-${local.resource_suffix}"
  frequency = "DAILY"
  
  monitor_arn_list = [
    aws_ce_anomaly_monitor.service_monitor.arn
  ]
  
  subscriber {
    type    = "SNS"
    address = aws_sns_topic.cost_alerts.arn
  }
  
  threshold_expression {
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        values        = [tostring(var.anomaly_detection_threshold)]
        match_options = ["GREATER_THAN_OR_EQUAL"]
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Description = "Cost anomaly subscription for automated alerts"
  })
}

#############################################
# Lambda Function for Cost Optimization Automation
#############################################

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role-${local.resource_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Description = "IAM role for cost optimization Lambda function"
  })
}

# IAM policy for Lambda function
resource "aws_iam_policy" "lambda_policy" {
  name        = "${local.name_prefix}-lambda-policy-${local.resource_suffix}"
  description = "Policy for cost optimization Lambda function"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${local.partition}:logs:${var.aws_region}:${local.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cost-optimization-hub:ListRecommendations",
          "cost-optimization-hub:GetRecommendation",
          "cost-optimization-hub:GetPreferences"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ce:GetAnomalies",
          "ce:GetUsageAndCosts",
          "ce:GetDimensionValues",
          "ce:GetReservationCoverage",
          "ce:GetReservationPurchaseRecommendation",
          "ce:GetReservationUtilization"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.cost_alerts.arn
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Description = "Lambda execution policy for cost optimization"
  })
}

# Attach policies to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_custom" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda function source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/cost_optimization_handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      sns_topic_arn = aws_sns_topic.cost_alerts.arn
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for cost optimization automation
resource "aws_lambda_function" "cost_optimization" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-handler-${local.resource_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.cost_alerts.arn
      ENVIRONMENT   = var.environment
    }
  }
  
  tags = merge(local.common_tags, {
    Description = "Lambda function for cost optimization automation"
  })
}

# Lambda permission for SNS to invoke the function
resource "aws_lambda_permission" "sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_optimization.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.cost_alerts.arn
}

# SNS topic subscription for Lambda function
resource "aws_sns_topic_subscription" "lambda_notification" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.cost_optimization.arn
}

#############################################
# CloudWatch Log Group for Lambda
#############################################

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.cost_optimization.function_name}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Description = "CloudWatch logs for cost optimization Lambda function"
  })
}