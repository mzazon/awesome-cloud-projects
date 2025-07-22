# ============================================================================
# KINESIS FIREHOSE OUTPUTS
# ============================================================================

output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.log_processing.name
}

output "firehose_delivery_stream_arn" {
  description = "ARN of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.log_processing.arn
}

output "firehose_delivery_stream_endpoint" {
  description = "Endpoint for sending data to the Kinesis Data Firehose delivery stream"
  value       = "https://firehose.${data.aws_region.current.name}.amazonaws.com"
}

# ============================================================================
# LAMBDA OUTPUTS
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda transformation function"
  value       = aws_lambda_function.transform.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda transformation function"
  value       = aws_lambda_function.transform.arn
}

output "lambda_function_version" {
  description = "Version of the Lambda transformation function"
  value       = aws_lambda_function.transform.version
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "raw_data_bucket_name" {
  description = "Name of the S3 bucket for raw data backup"
  value       = aws_s3_bucket.raw_data.bucket
}

output "raw_data_bucket_arn" {
  description = "ARN of the S3 bucket for raw data backup"
  value       = aws_s3_bucket.raw_data.arn
}

output "processed_data_bucket_name" {
  description = "Name of the S3 bucket for processed data"
  value       = aws_s3_bucket.processed_data.bucket
}

output "processed_data_bucket_arn" {
  description = "ARN of the S3 bucket for processed data"
  value       = aws_s3_bucket.processed_data.arn
}

output "error_data_bucket_name" {
  description = "Name of the S3 bucket for error data (dead letter queue)"
  value       = aws_s3_bucket.error_data.bucket
}

output "error_data_bucket_arn" {
  description = "ARN of the S3 bucket for error data (dead letter queue)"
  value       = aws_s3_bucket.error_data.arn
}

# ============================================================================
# IAM ROLE OUTPUTS
# ============================================================================

output "lambda_execution_role_name" {
  description = "Name of the IAM role for Lambda execution"
  value       = aws_iam_role.lambda_execution.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda execution"
  value       = aws_iam_role.lambda_execution.arn
}

output "firehose_delivery_role_name" {
  description = "Name of the IAM role for Kinesis Firehose delivery"
  value       = aws_iam_role.firehose_delivery.name
}

output "firehose_delivery_role_arn" {
  description = "ARN of the IAM role for Kinesis Firehose delivery"
  value       = aws_iam_role.firehose_delivery.arn
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "sns_topic_name" {
  description = "Name of the SNS topic for alarm notifications"
  value       = var.enable_monitoring ? aws_sns_topic.firehose_alarms[0].name : null
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarm notifications"
  value       = var.enable_monitoring ? aws_sns_topic.firehose_alarms[0].arn : null
}

output "cloudwatch_log_group_firehose" {
  description = "Name of the CloudWatch log group for Kinesis Firehose"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.firehose_logs[0].name : null
}

output "cloudwatch_alarms" {
  description = "List of CloudWatch alarm names created for monitoring"
  value = var.enable_monitoring ? [
    aws_cloudwatch_metric_alarm.delivery_failure[0].alarm_name,
    aws_cloudwatch_metric_alarm.transformation_errors[0].alarm_name,
    aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name,
    aws_cloudwatch_metric_alarm.lambda_duration[0].alarm_name
  ] : []
}

# ============================================================================
# TESTING AND VALIDATION OUTPUTS
# ============================================================================

output "test_data_sample" {
  description = "Sample JSON data for testing the pipeline"
  value = jsonencode({
    timestamp = "2025-01-12T10:30:00Z"
    level     = "INFO"
    service   = "user-service"
    message   = "User login successful"
    userId    = "user123"
  })
}

output "aws_cli_put_record_command" {
  description = "AWS CLI command to send a test record to the Firehose delivery stream"
  value = "aws firehose put-record --delivery-stream-name ${aws_kinesis_firehose_delivery_stream.log_processing.name} --record Data=\"$(echo '${jsonencode({
    timestamp = "2025-01-12T10:30:00Z"
    level     = "INFO"
    service   = "test-service"
    message   = "Test log message"
    userId    = "test-user"
  })}' | base64)\""
}

output "s3_processed_data_path" {
  description = "S3 path pattern for processed data files"
  value       = "s3://${aws_s3_bucket.processed_data.bucket}/logs/year=YYYY/month=MM/day=DD/"
}

output "s3_raw_data_path" {
  description = "S3 path pattern for raw data backup files"
  value       = "s3://${aws_s3_bucket.raw_data.bucket}/raw/year=YYYY/month=MM/day=DD/"
}

output "s3_error_data_path" {
  description = "S3 path pattern for error data files"
  value       = "s3://${aws_s3_bucket.error_data.bucket}/errors/year=YYYY/month=MM/day=DD/"
}

# ============================================================================
# CONFIGURATION SUMMARY
# ============================================================================

output "configuration_summary" {
  description = "Summary of the pipeline configuration"
  value = {
    environment                = var.environment
    project_name              = var.project_name
    aws_region                = var.aws_region
    firehose_buffer_size      = var.firehose_buffer_size
    firehose_buffer_interval  = var.firehose_buffer_interval
    lambda_timeout            = var.lambda_timeout
    lambda_memory_size        = var.lambda_memory_size
    min_log_level             = var.min_log_level
    s3_compression_format     = var.s3_compression_format
    monitoring_enabled        = var.enable_monitoring
    cloudwatch_logs_enabled   = var.enable_cloudwatch_logs
    s3_encryption_enabled     = var.enable_s3_encryption
    notification_email        = var.notification_email
    data_freshness_threshold  = var.data_freshness_threshold
  }
}

# ============================================================================
# RESOURCE COSTS INFORMATION
# ============================================================================

output "estimated_costs" {
  description = "Estimated monthly costs for the pipeline components"
  value = {
    firehose_per_gb         = "$0.035 per GB ingested"
    lambda_requests         = "$0.20 per 1M requests"
    lambda_duration         = "$0.0000166667 per GB-second"
    s3_standard_storage     = "$0.023 per GB/month"
    s3_requests_put         = "$0.005 per 1,000 PUT requests"
    cloudwatch_logs         = "$0.50 per GB ingested"
    cloudwatch_alarms       = "$0.10 per alarm per month"
    sns_notifications       = "$0.50 per 1M notifications"
    note = "Actual costs depend on data volume and usage patterns"
  }
}

# ============================================================================
# NEXT STEPS
# ============================================================================

output "next_steps" {
  description = "Next steps for using the deployed pipeline"
  value = {
    "1_send_test_data" = "Use the AWS CLI command provided in 'aws_cli_put_record_command' output to send test data"
    "2_monitor_logs" = "Check CloudWatch logs for Lambda function: ${aws_cloudwatch_log_group.lambda_logs.name}"
    "3_verify_s3_data" = "Check S3 buckets for processed data after ~2-3 minutes"
    "4_setup_monitoring" = var.notification_email != null ? "Email notifications are configured" : "Add email to SNS topic for alarm notifications"
    "5_integrate_applications" = "Configure your applications to send log data to the Firehose delivery stream"
  }
}