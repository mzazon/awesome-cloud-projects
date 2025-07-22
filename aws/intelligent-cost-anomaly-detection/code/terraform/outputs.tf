# ==========================================
# Output Values for Cost Anomaly Detection
# ==========================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for cost anomaly notifications"
  value       = aws_sns_topic.cost_anomaly_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for cost anomaly notifications"
  value       = aws_sns_topic.cost_anomaly_alerts.name
}

output "lambda_function_name" {
  description = "Name of the Lambda function for cost anomaly processing"
  value       = aws_lambda_function.cost_anomaly_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for cost anomaly processing"
  value       = aws_lambda_function.cost_anomaly_processor.arn
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "cost_anomaly_monitor_arn" {
  description = "ARN of the Cost Anomaly Detection monitor"
  value       = aws_ce_anomaly_monitor.cost_monitor.arn
}

output "cost_anomaly_detector_arn" {
  description = "ARN of the Cost Anomaly Detection detector"
  value       = aws_ce_anomaly_detector.cost_detector.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for cost anomaly events"
  value       = aws_cloudwatch_event_rule.cost_anomaly_rule.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for cost anomaly events"
  value       = aws_cloudwatch_event_rule.cost_anomaly_rule.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for cost anomaly monitoring"
  value = var.enable_cloudwatch_dashboard ? (
    "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.cost_anomaly_dashboard[0].dashboard_name}"
  ) : "Dashboard not created (disabled in configuration)"
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "email_subscription_arn" {
  description = "ARN of the email subscription to the SNS topic"
  value       = aws_sns_topic_subscription.email_notification.arn
}

output "additional_subscription_arns" {
  description = "ARNs of additional SNS subscriptions"
  value       = aws_sns_topic_subscription.additional_notifications[*].arn
}

output "cost_explorer_console_url" {
  description = "URL to AWS Cost Explorer console"
  value       = "https://console.aws.amazon.com/billing/home#/costexplorer"
}

output "cost_anomaly_detection_console_url" {
  description = "URL to AWS Cost Anomaly Detection console"
  value       = "https://console.aws.amazon.com/billing/home#/anomaly-detection"
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    project_name           = var.project_name
    environment           = var.environment
    anomaly_threshold     = var.anomaly_threshold
    detection_frequency   = var.detection_frequency
    monitor_dimension     = var.monitor_dimension
    monitored_services    = var.monitored_services
    dashboard_enabled     = var.enable_cloudwatch_dashboard
    notification_email    = var.email_address
    additional_endpoints  = length(var.additional_sns_endpoints)
    aws_region           = data.aws_region.current.name
    aws_account_id       = data.aws_caller_identity.current.account_id
  }
}

# ==========================================
# Sensitive Outputs (marked as sensitive)
# ==========================================

output "lambda_environment_variables" {
  description = "Environment variables configured for the Lambda function"
  value = {
    SNS_TOPIC_ARN = aws_sns_topic.cost_anomaly_alerts.arn
  }
  sensitive = false
}

output "iam_policy_arn" {
  description = "ARN of the custom IAM policy for cost operations"
  value       = aws_iam_policy.cost_anomaly_policy.arn
}

output "setup_verification_commands" {
  description = "Commands to verify the deployment"
  value = [
    "aws ce get-anomaly-monitors --query 'AnomalyMonitors[?MonitorName==`${aws_ce_anomaly_monitor.cost_monitor.name}`]' --output table",
    "aws ce get-anomaly-detectors --query 'AnomalyDetectors[?DetectorName==`${aws_ce_anomaly_detector.cost_detector.name}`]' --output table",
    "aws lambda invoke --function-name ${aws_lambda_function.cost_anomaly_processor.function_name} --payload '{}' /tmp/test-response.json && cat /tmp/test-response.json",
    "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.cost_anomaly_alerts.arn} --output table"
  ]
}