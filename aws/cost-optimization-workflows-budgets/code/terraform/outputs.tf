# Outputs for AWS Cost Optimization Hub and Budgets Infrastructure
# This file defines output values that provide important information about the created resources

#############################################
# Cost Optimization Hub Outputs
#############################################

output "cost_optimization_hub_enabled" {
  description = "Whether Cost Optimization Hub is enabled"
  value       = var.cost_optimization_hub_enabled
}

output "savings_estimation_mode" {
  description = "Cost Optimization Hub savings estimation mode"
  value       = var.cost_optimization_hub_enabled ? var.savings_estimation_mode : null
}

#############################################
# SNS Topic Outputs
#############################################

output "sns_topic_arn" {
  description = "ARN of the SNS topic for cost optimization alerts"
  value       = aws_sns_topic.cost_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for cost optimization alerts"
  value       = aws_sns_topic.cost_alerts.name
}

output "notification_email" {
  description = "Email address configured for notifications"
  value       = var.notification_email
  sensitive   = true
}

#############################################
# Budget Outputs
#############################################

output "monthly_cost_budget_name" {
  description = "Name of the monthly cost budget"
  value       = aws_budgets_budget.monthly_cost.name
}

output "monthly_cost_budget_amount" {
  description = "Monthly cost budget amount in USD"
  value       = var.monthly_budget_amount
}

output "monthly_cost_budget_threshold" {
  description = "Monthly cost budget alert threshold percentage"
  value       = var.monthly_budget_threshold
}

output "ec2_usage_budget_name" {
  description = "Name of the EC2 usage budget"
  value       = aws_budgets_budget.ec2_usage.name
}

output "ec2_usage_budget_hours" {
  description = "EC2 usage budget in hours"
  value       = var.ec2_usage_budget_hours
}

output "ri_utilization_budget_name" {
  description = "Name of the Reserved Instance utilization budget"
  value       = aws_budgets_budget.ri_utilization.name
}

output "ri_utilization_threshold" {
  description = "Reserved Instance utilization threshold percentage"
  value       = var.ri_utilization_threshold
}

#############################################
# Budget Actions Outputs
#############################################

output "budget_actions_enabled" {
  description = "Whether automated budget actions are enabled"
  value       = var.enable_budget_actions
}

output "budget_actions_role_arn" {
  description = "ARN of the IAM role for budget actions"
  value       = var.enable_budget_actions ? aws_iam_role.budget_actions[0].arn : null
}

output "budget_restriction_policy_arn" {
  description = "ARN of the budget restriction policy"
  value       = var.enable_budget_actions ? aws_iam_policy.budget_restriction[0].arn : null
}

#############################################
# Cost Anomaly Detection Outputs
#############################################

output "anomaly_monitor_arn" {
  description = "ARN of the cost anomaly monitor"
  value       = aws_ce_anomaly_monitor.service_monitor.arn
}

output "anomaly_monitor_name" {
  description = "Name of the cost anomaly monitor"
  value       = aws_ce_anomaly_monitor.service_monitor.name
}

output "anomaly_subscription_arn" {
  description = "ARN of the cost anomaly subscription"
  value       = aws_ce_anomaly_subscription.main.arn
}

output "anomaly_detection_threshold" {
  description = "Cost anomaly detection threshold in USD"
  value       = var.anomaly_detection_threshold
}

output "monitored_services" {
  description = "List of AWS services monitored for cost anomalies"
  value       = var.monitored_services
}

#############################################
# Lambda Function Outputs
#############################################

output "lambda_function_arn" {
  description = "ARN of the cost optimization Lambda function"
  value       = aws_lambda_function.cost_optimization.arn
}

output "lambda_function_name" {
  description = "Name of the cost optimization Lambda function"
  value       = aws_lambda_function.cost_optimization.function_name
}

output "lambda_function_role_arn" {
  description = "ARN of the Lambda function's IAM role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_log_group_name" {
  description = "Name of the Lambda function's CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

#############################################
# Infrastructure Information
#############################################

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = local.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

#############################################
# Cost Management URLs
#############################################

output "cost_optimization_hub_url" {
  description = "URL to access Cost Optimization Hub in the AWS Console"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cost-optimization-hub/home?region=${var.aws_region}#/dashboard"
}

output "budgets_console_url" {
  description = "URL to access AWS Budgets in the AWS Console"
  value       = "https://console.aws.amazon.com/billing/home#/budgets"
}

output "cost_explorer_url" {
  description = "URL to access AWS Cost Explorer in the AWS Console"
  value       = "https://console.aws.amazon.com/cost-management/home#/cost-explorer"
}

output "anomaly_detection_console_url" {
  description = "URL to access Cost Anomaly Detection in the AWS Console"
  value       = "https://console.aws.amazon.com/cost-management/home#/anomaly-detection"
}

#############################################
# Resource Tags
#############################################

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

#############################################
# Quick Reference Information
#############################################

output "deployment_summary" {
  description = "Summary of deployed resources and configuration"
  value = {
    cost_optimization_hub_enabled = var.cost_optimization_hub_enabled
    budgets_created = {
      monthly_cost_budget = {
        name      = aws_budgets_budget.monthly_cost.name
        amount    = "${var.monthly_budget_amount} USD"
        threshold = "${var.monthly_budget_threshold}%"
      }
      ec2_usage_budget = {
        name   = aws_budgets_budget.ec2_usage.name
        amount = "${var.ec2_usage_budget_hours} HOURS"
      }
      ri_utilization_budget = {
        name      = aws_budgets_budget.ri_utilization.name
        threshold = "${var.ri_utilization_threshold}%"
      }
    }
    notifications = {
      sns_topic    = aws_sns_topic.cost_alerts.name
      email        = var.notification_email
      lambda_function = aws_lambda_function.cost_optimization.function_name
    }
    anomaly_detection = {
      monitor_name         = aws_ce_anomaly_monitor.service_monitor.name
      threshold_usd       = var.anomaly_detection_threshold
      monitored_services  = var.monitored_services
    }
    automation = {
      budget_actions_enabled = var.enable_budget_actions
      lambda_function       = aws_lambda_function.cost_optimization.function_name
    }
  }
}

#############################################
# Next Steps Guidance
#############################################

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Confirm email subscription to SNS topic for notifications",
    "2. Review Cost Optimization Hub recommendations in the AWS Console",
    "3. Monitor budget alerts and adjust thresholds as needed",
    "4. Review Lambda function logs in CloudWatch for automated processing",
    "5. Consider enabling budget actions if you want automated cost controls",
    "6. Set up additional cost allocation tags for more granular monitoring",
    "7. Review and customize Lambda function logic for your specific requirements"
  ]
}