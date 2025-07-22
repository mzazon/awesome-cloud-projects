# ==============================================================================
# SNS OUTPUTS
# ==============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for cost anomaly notifications"
  value       = aws_sns_topic.cost_anomaly_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for cost anomaly notifications"
  value       = aws_sns_topic.cost_anomaly_alerts.name
}

output "email_subscription_arn" {
  description = "ARN of the email subscription to the SNS topic"
  value       = aws_sns_topic_subscription.email_notification.arn
}

# ==============================================================================
# COST ANOMALY DETECTION OUTPUTS
# ==============================================================================

output "aws_services_monitor_arn" {
  description = "ARN of the AWS Services cost anomaly monitor"
  value       = aws_ce_anomaly_monitor.aws_services_monitor.arn
}

output "account_based_monitor_arn" {
  description = "ARN of the Account-Based cost anomaly monitor"
  value       = aws_ce_anomaly_monitor.account_based_monitor.arn
}

output "environment_tag_monitor_arn" {
  description = "ARN of the Environment Tag-Based cost anomaly monitor"
  value       = aws_ce_anomaly_monitor.environment_tag_monitor.arn
}

output "daily_summary_subscription_arn" {
  description = "ARN of the daily summary anomaly subscription"
  value       = aws_ce_anomaly_subscription.daily_summary.arn
}

output "individual_alerts_subscription_arn" {
  description = "ARN of the individual alerts anomaly subscription"
  value       = aws_ce_anomaly_subscription.individual_alerts.arn
}

# ==============================================================================
# LAMBDA FUNCTION OUTPUTS
# ==============================================================================

output "lambda_function_arn" {
  description = "ARN of the cost anomaly processor Lambda function"
  value       = aws_lambda_function.cost_anomaly_processor.arn
}

output "lambda_function_name" {
  description = "Name of the cost anomaly processor Lambda function"
  value       = aws_lambda_function.cost_anomaly_processor.function_name
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the cost anomaly processor Lambda function"
  value       = aws_lambda_function.cost_anomaly_processor.invoke_arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for the Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ==============================================================================
# EVENTBRIDGE OUTPUTS
# ==============================================================================

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for cost anomaly events"
  value       = aws_cloudwatch_event_rule.cost_anomaly_events.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for cost anomaly events"
  value       = aws_cloudwatch_event_rule.cost_anomaly_events.name
}

# ==============================================================================
# CLOUDWATCH DASHBOARD OUTPUTS
# ==============================================================================

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard for cost anomaly monitoring"
  value = var.create_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.cost_anomaly_dashboard[0].dashboard_name}" : null
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard (if created)"
  value       = var.create_dashboard ? aws_cloudwatch_dashboard.cost_anomaly_dashboard[0].dashboard_name : null
}

# ==============================================================================
# MONITORING AND VALIDATION OUTPUTS
# ==============================================================================

output "cost_anomaly_console_url" {
  description = "URL to the AWS Cost Anomaly Detection console"
  value       = "https://console.aws.amazon.com/cost-management/home?region=${data.aws_region.current.name}#/anomaly-detection"
}

output "cost_explorer_console_url" {
  description = "URL to the AWS Cost Explorer console"
  value       = "https://console.aws.amazon.com/cost-management/home?region=${data.aws_region.current.name}#/cost-explorer"
}

output "deployment_summary" {
  description = "Summary of deployed resources for cost anomaly detection"
  value = {
    monitors = {
      aws_services_monitor      = aws_ce_anomaly_monitor.aws_services_monitor.arn
      account_based_monitor     = aws_ce_anomaly_monitor.account_based_monitor.arn
      environment_tag_monitor   = aws_ce_anomaly_monitor.environment_tag_monitor.arn
    }
    subscriptions = {
      daily_summary     = aws_ce_anomaly_subscription.daily_summary.arn
      individual_alerts = aws_ce_anomaly_subscription.individual_alerts.arn
    }
    automation = {
      sns_topic           = aws_sns_topic.cost_anomaly_alerts.arn
      lambda_function     = aws_lambda_function.cost_anomaly_processor.arn
      eventbridge_rule    = aws_cloudwatch_event_rule.cost_anomaly_events.arn
    }
    monitoring = {
      log_group     = aws_cloudwatch_log_group.lambda_logs.name
      dashboard     = var.create_dashboard ? aws_cloudwatch_dashboard.cost_anomaly_dashboard[0].dashboard_name : "not_created"
    }
  }
}

# ==============================================================================
# RESOURCE CONFIGURATION OUTPUTS
# ==============================================================================

output "configuration_summary" {
  description = "Configuration summary for the cost anomaly detection setup"
  value = {
    thresholds = {
      daily_summary_threshold     = var.daily_summary_threshold
      individual_alert_threshold  = var.individual_alert_threshold
    }
    notification_settings = {
      email_address = var.notification_email
      sns_topic     = aws_sns_topic.cost_anomaly_alerts.name
    }
    monitoring_scope = {
      environment_tags = var.environment_tags
      environment     = var.environment
    }
    lambda_configuration = {
      runtime = var.lambda_runtime
      timeout = var.lambda_timeout
    }
  }
}

# ==============================================================================
# NEXT STEPS OUTPUT
# ==============================================================================

output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT
    1. Confirm email subscription:
       - Check your email (${var.notification_email}) for SNS subscription confirmation
       - Click the confirmation link to activate email notifications
    
    2. Monitor cost anomaly detection:
       - Visit the Cost Anomaly Detection console: ${local.cost_anomaly_console_url}
       - Monitor the CloudWatch dashboard: ${var.create_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.cost_anomaly_dashboard[0].dashboard_name}" : "Dashboard not created"}
    
    3. Validate setup:
       - Cost anomaly detection requires 10+ days of historical data
       - Test notifications by publishing to SNS topic: ${aws_sns_topic.cost_anomaly_alerts.arn}
       - Monitor Lambda logs: ${aws_cloudwatch_log_group.lambda_logs.name}
    
    4. Customize as needed:
       - Adjust thresholds in variables
       - Modify environment tags being monitored
       - Extend Lambda function for custom automation
  EOT
}

# ==============================================================================
# LOCAL VALUES FOR COMPUTED OUTPUTS
# ==============================================================================

locals {
  cost_anomaly_console_url = "https://console.aws.amazon.com/cost-management/home?region=${data.aws_region.current.name}#/anomaly-detection"
}