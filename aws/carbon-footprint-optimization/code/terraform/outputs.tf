# Project identification outputs
output "project_id" {
  description = "Unique project identifier with random suffix"
  value       = local.project_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# S3 bucket outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for carbon footprint data storage"
  value       = aws_s3_bucket.carbon_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for carbon footprint data storage"
  value       = aws_s3_bucket.carbon_data.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.carbon_data.bucket_domain_name
}

# Lambda function outputs
output "lambda_function_name" {
  description = "Name of the carbon footprint analyzer Lambda function"
  value       = aws_lambda_function.carbon_analyzer.function_name
}

output "lambda_function_arn" {
  description = "ARN of the carbon footprint analyzer Lambda function"
  value       = aws_lambda_function.carbon_analyzer.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the carbon footprint analyzer Lambda function"
  value       = aws_lambda_function.carbon_analyzer.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# DynamoDB outputs
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing carbon footprint metrics"
  value       = aws_dynamodb_table.carbon_metrics.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table storing carbon footprint metrics"
  value       = aws_dynamodb_table.carbon_metrics.arn
}

output "dynamodb_table_stream_arn" {
  description = "ARN of the DynamoDB table stream (if enabled)"
  value       = aws_dynamodb_table.carbon_metrics.stream_arn
}

# SNS topic outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for carbon optimization notifications"
  value       = aws_sns_topic.carbon_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for carbon optimization notifications"
  value       = aws_sns_topic.carbon_notifications.name
}

# EventBridge Scheduler outputs
output "monthly_schedule_arn" {
  description = "ARN of the monthly carbon footprint analysis schedule"
  value       = aws_scheduler_schedule.monthly_analysis.arn
}

output "weekly_schedule_arn" {
  description = "ARN of the weekly carbon footprint trend analysis schedule"
  value       = aws_scheduler_schedule.weekly_trends.arn
}

# Cost and Usage Report outputs (conditional)
output "cur_report_name" {
  description = "Name of the Cost and Usage Report (if enabled)"
  value       = var.enable_cur_integration ? aws_cur_report_definition.carbon_optimization[0].report_name : null
}

output "cur_s3_prefix" {
  description = "S3 prefix for Cost and Usage Report data (if enabled)"
  value       = var.enable_cur_integration ? aws_cur_report_definition.carbon_optimization[0].s3_prefix : null
}

# CloudWatch Dashboard output
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for carbon footprint monitoring"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.carbon_footprint.dashboard_name}"
}

# Systems Manager parameter outputs
output "scanner_config_parameter" {
  description = "Name of the Systems Manager parameter storing scanner configuration"
  value       = var.enable_sustainability_scanner ? aws_ssm_parameter.scanner_config[0].name : null
}

# Notification configuration
output "notification_email_configured" {
  description = "Whether email notifications are configured"
  value       = var.notification_email != ""
}

# Testing and validation outputs
output "test_lambda_command" {
  description = "AWS CLI command to test the Lambda function"
  value       = "aws lambda invoke --function-name ${aws_lambda_function.carbon_analyzer.function_name} --payload '{}' response.json"
}

output "query_metrics_command" {
  description = "AWS CLI command to query stored carbon footprint metrics"
  value       = "aws dynamodb scan --table-name ${aws_dynamodb_table.carbon_metrics.name} --max-items 5"
}

output "view_dashboard_command" {
  description = "AWS CLI command to get dashboard information"
  value       = "aws cloudwatch get-dashboard --dashboard-name ${aws_cloudwatch_dashboard.carbon_footprint.dashboard_name}"
}

# Resource costs estimation
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD for the deployed resources"
  value = {
    lambda_requests     = "~$1-5 (based on execution frequency)"
    dynamodb_capacity   = "~$2-8 (based on ${var.dynamodb_read_capacity}/${var.dynamodb_write_capacity} RCU/WCU)"
    s3_storage         = "~$1-3 (based on data volume)"
    cloudwatch_logs    = "~$1-2 (based on log volume)"
    eventbridge        = "~$0.10 (scheduled executions)"
    sns_notifications  = "~$0.10 (notification volume)"
    total_estimated    = "~$5-20 per month"
  }
}

# Important URLs and resources
output "useful_links" {
  description = "Useful links for managing and monitoring the carbon footprint optimization system"
  value = {
    lambda_console     = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.carbon_analyzer.function_name}"
    dynamodb_console   = "https://${data.aws_region.current.name}.console.aws.amazon.com/dynamodbv2/home?region=${data.aws_region.current.name}#table?name=${aws_dynamodb_table.carbon_metrics.name}"
    s3_console         = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.carbon_data.bucket}"
    cost_explorer      = "https://console.aws.amazon.com/cost-management/home#/cost-explorer"
    sustainability_hub = "https://console.aws.amazon.com/sustainability/home"
  }
}

# Configuration summary
output "deployment_summary" {
  description = "Summary of the deployed carbon footprint optimization system"
  value = {
    project_name              = var.project_name
    environment              = var.environment
    lambda_function          = aws_lambda_function.carbon_analyzer.function_name
    storage_bucket          = aws_s3_bucket.carbon_data.bucket
    metrics_table           = aws_dynamodb_table.carbon_metrics.name
    notification_topic      = aws_sns_topic.carbon_notifications.name
    monthly_analysis        = var.monthly_analysis_schedule
    weekly_analysis         = var.weekly_analysis_schedule
    cur_integration_enabled = var.enable_cur_integration
    scanner_enabled         = var.enable_sustainability_scanner
    email_notifications     = var.notification_email != "" ? "configured" : "not_configured"
  }
}