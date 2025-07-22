# Outputs for CloudFront Cache Invalidation Strategies
# This file defines all output values that will be displayed after deployment

# CloudFront Distribution Outputs
output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.arn
}

output "cloudfront_distribution_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_hosted_zone_id" {
  description = "Hosted zone ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "cloudfront_distribution_status" {
  description = "Current status of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.status
}

output "cloudfront_origin_access_control_id" {
  description = "ID of the CloudFront Origin Access Control"
  value       = aws_cloudfront_origin_access_control.main.id
}

# S3 Bucket Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket used as CloudFront origin"
  value       = aws_s3_bucket.content.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket used as CloudFront origin"
  value       = aws_s3_bucket.content.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.content.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.content.bucket_regional_domain_name
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the Lambda invalidation function"
  value       = aws_lambda_function.invalidation_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda invalidation function"
  value       = aws_lambda_function.invalidation_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda invalidation function"
  value       = aws_lambda_function.invalidation_processor.invoke_arn
}

output "lambda_function_role_arn" {
  description = "ARN of the Lambda function's IAM role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_function_log_group_name" {
  description = "Name of the Lambda function's CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# EventBridge Outputs
output "eventbridge_custom_bus_name" {
  description = "Name of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.invalidation_bus.name
}

output "eventbridge_custom_bus_arn" {
  description = "ARN of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.invalidation_bus.arn
}

output "eventbridge_s3_rule_name" {
  description = "Name of the S3 EventBridge rule"
  value       = aws_cloudwatch_event_rule.s3_events.name
}

output "eventbridge_s3_rule_arn" {
  description = "ARN of the S3 EventBridge rule"
  value       = aws_cloudwatch_event_rule.s3_events.arn
}

output "eventbridge_deployment_rule_name" {
  description = "Name of the deployment EventBridge rule"
  value       = aws_cloudwatch_event_rule.deployment_events.name
}

output "eventbridge_deployment_rule_arn" {
  description = "ARN of the deployment EventBridge rule"
  value       = aws_cloudwatch_event_rule.deployment_events.arn
}

# SQS Queue Outputs
output "sqs_batch_queue_url" {
  description = "URL of the SQS batch processing queue"
  value       = aws_sqs_queue.batch_queue.url
}

output "sqs_batch_queue_arn" {
  description = "ARN of the SQS batch processing queue"
  value       = aws_sqs_queue.batch_queue.arn
}

output "sqs_dead_letter_queue_url" {
  description = "URL of the SQS dead letter queue"
  value       = aws_sqs_queue.dead_letter_queue.url
}

output "sqs_dead_letter_queue_arn" {
  description = "ARN of the SQS dead letter queue"
  value       = aws_sqs_queue.dead_letter_queue.arn
}

# DynamoDB Table Outputs
output "dynamodb_table_name" {
  description = "Name of the DynamoDB invalidation log table"
  value       = aws_dynamodb_table.invalidation_log.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB invalidation log table"
  value       = aws_dynamodb_table.invalidation_log.arn
}

output "dynamodb_table_stream_arn" {
  description = "ARN of the DynamoDB table stream"
  value       = aws_dynamodb_table.invalidation_log.stream_arn
}

# CloudWatch Dashboard Outputs
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch monitoring dashboard"
  value       = var.enable_monitoring_dashboard ? aws_cloudwatch_dashboard.monitoring[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch monitoring dashboard"
  value = var.enable_monitoring_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.monitoring[0].dashboard_name}" : null
}

# SNS Topic Outputs
output "sns_topic_arn" {
  description = "ARN of the SNS notification topic"
  value       = var.sns_notification_email != "" ? aws_sns_topic.notifications[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS notification topic"
  value       = var.sns_notification_email != "" ? aws_sns_topic.notifications[0].name : null
}

# Testing and Access Information
output "test_urls" {
  description = "URLs for testing the CloudFront distribution"
  value = {
    home_page     = "https://${aws_cloudfront_distribution.main.domain_name}/"
    css_file      = "https://${aws_cloudfront_distribution.main.domain_name}/css/style.css"
    js_file       = "https://${aws_cloudfront_distribution.main.domain_name}/js/app.js"
    api_status    = "https://${aws_cloudfront_distribution.main.domain_name}/api/status.json"
  }
}

output "aws_cli_commands" {
  description = "Useful AWS CLI commands for testing and monitoring"
  value = {
    test_invalidation = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.main.id} --paths '/*'"
    check_distribution = "aws cloudfront get-distribution --id ${aws_cloudfront_distribution.main.id}"
    list_invalidations = "aws cloudfront list-invalidations --distribution-id ${aws_cloudfront_distribution.main.id}"
    view_lambda_logs = "aws logs tail /aws/lambda/${aws_lambda_function.invalidation_processor.function_name} --follow"
    check_sqs_messages = "aws sqs receive-message --queue-url ${aws_sqs_queue.batch_queue.url}"
    scan_dynamodb = "aws dynamodb scan --table-name ${aws_dynamodb_table.invalidation_log.name} --limit 10"
  }
}

# Environment Information
output "deployment_info" {
  description = "Information about the deployment"
  value = {
    project_name          = var.project_name
    environment          = var.environment
    aws_region           = var.aws_region
    deployment_timestamp = timestamp()
    terraform_version    = "~> 1.0"
    aws_provider_version = "~> 5.0"
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = {
    cloudfront_invalidation_cost = "First 1,000 invalidation paths per month are free, then $0.005 per path"
    lambda_cost_optimization = "Monitor Lambda duration and memory usage in CloudWatch to optimize costs"
    s3_cost_optimization = "Consider using S3 Intelligent-Tiering for cost optimization"
    dynamodb_cost_optimization = "Monitor DynamoDB usage and consider switching to provisioned capacity for predictable workloads"
    sqs_cost_optimization = "SQS has no minimum fees - you pay only for what you use"
  }
}

# Security Information
output "security_considerations" {
  description = "Security considerations and best practices"
  value = {
    s3_bucket_security = "Bucket is private with CloudFront Origin Access Control"
    lambda_security = "Lambda function uses least privilege IAM role"
    eventbridge_security = "EventBridge rules use specific event patterns for security"
    dynamodb_security = "DynamoDB table uses encryption at rest"
    cloudfront_security = "CloudFront distribution enforces HTTPS and uses modern TLS versions"
  }
}

# Monitoring Information
output "monitoring_resources" {
  description = "Information about monitoring resources"
  value = {
    cloudwatch_dashboard_created = var.enable_monitoring_dashboard
    lambda_log_group = aws_cloudwatch_log_group.lambda_logs.name
    log_retention_days = var.log_retention_in_days
    xray_tracing_enabled = var.enable_xray_tracing
    sns_notifications_enabled = var.sns_notification_email != ""
  }
}