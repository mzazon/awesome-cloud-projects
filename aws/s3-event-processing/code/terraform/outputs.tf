# Output values for the event-driven data processing infrastructure

output "s3_bucket_name" {
  description = "Name of the S3 bucket for data processing"
  value       = aws_s3_bucket.data_processing_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for data processing"
  value       = aws_s3_bucket.data_processing_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.data_processing_bucket.bucket_domain_name
}

output "data_processor_function_name" {
  description = "Name of the data processing Lambda function"
  value       = aws_lambda_function.data_processor.function_name
}

output "data_processor_function_arn" {
  description = "ARN of the data processing Lambda function"
  value       = aws_lambda_function.data_processor.arn
}

output "error_handler_function_name" {
  description = "Name of the error handler Lambda function"
  value       = aws_lambda_function.error_handler.function_name
}

output "error_handler_function_arn" {
  description = "ARN of the error handler Lambda function"
  value       = aws_lambda_function.error_handler.arn
}

output "dead_letter_queue_name" {
  description = "Name of the Dead Letter Queue"
  value       = aws_sqs_queue.dead_letter_queue.name
}

output "dead_letter_queue_arn" {
  description = "ARN of the Dead Letter Queue"
  value       = aws_sqs_queue.dead_letter_queue.arn
}

output "dead_letter_queue_url" {
  description = "URL of the Dead Letter Queue"
  value       = aws_sqs_queue.dead_letter_queue.url
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.data_processing_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.data_processing_alerts.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "data_processor_log_group_name" {
  description = "Name of the CloudWatch log group for data processor"
  value       = aws_cloudwatch_log_group.data_processor_logs.name
}

output "error_handler_log_group_name" {
  description = "Name of the CloudWatch log group for error handler"
  value       = aws_cloudwatch_log_group.error_handler_logs.name
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarms created for monitoring"
  value = var.enable_monitoring ? {
    lambda_errors = aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name
    dlq_messages  = aws_cloudwatch_metric_alarm.dlq_messages[0].alarm_name
  } : {}
}

# Useful commands and URLs
output "upload_command_example" {
  description = "Example AWS CLI command to upload a test file"
  value       = "aws s3 cp your-file.csv s3://${aws_s3_bucket.data_processing_bucket.bucket}/${var.data_prefix}your-file.csv"
}

output "cloudwatch_logs_urls" {
  description = "URLs to CloudWatch logs for the Lambda functions"
  value = {
    data_processor = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.data_processor_logs.name, "/", "%2F")}"
    error_handler  = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.error_handler_logs.name, "/", "%2F")}"
  }
}

output "s3_console_url" {
  description = "URL to the S3 bucket in AWS console"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.data_processing_bucket.bucket}"
}

output "monitoring_dashboard_url" {
  description = "URL to create a CloudWatch dashboard for monitoring"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:"
}

# Configuration information
output "configuration_info" {
  description = "Configuration information for the deployed infrastructure"
  value = {
    supported_file_types = var.supported_file_types
    data_prefix         = var.data_prefix
    notification_email  = var.notification_email
    environment         = var.environment
    aws_region          = data.aws_region.current.name
    account_id          = data.aws_caller_identity.current.account_id
  }
}

# Resource summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    s3_bucket         = aws_s3_bucket.data_processing_bucket.bucket
    lambda_functions  = [aws_lambda_function.data_processor.function_name, aws_lambda_function.error_handler.function_name]
    sqs_queue         = aws_sqs_queue.dead_letter_queue.name
    sns_topic         = aws_sns_topic.data_processing_alerts.name
    iam_role          = aws_iam_role.lambda_execution_role.name
    cloudwatch_alarms = var.enable_monitoring ? 2 : 0
  }
}