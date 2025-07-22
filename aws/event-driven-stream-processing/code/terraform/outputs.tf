# Outputs for Real-Time Data Processing with Kinesis and Lambda
# This file defines all outputs that provide important information about the deployed infrastructure.

# Kinesis Data Stream Outputs
output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.retail_events_stream.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.retail_events_stream.arn
}

output "kinesis_stream_id" {
  description = "Kinesis Data Stream ID"
  value       = aws_kinesis_stream.retail_events_stream.id
}

output "kinesis_shard_count" {
  description = "Number of shards in the Kinesis Data Stream"
  value       = aws_kinesis_stream.retail_events_stream.shard_count
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.retail_event_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.retail_event_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.retail_event_processor.invoke_arn
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the Lambda function"
  value       = aws_lambda_function.retail_event_processor.qualified_arn
}

output "lambda_function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.retail_event_processor.version
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# Event Source Mapping Outputs
output "lambda_event_source_mapping_uuid" {
  description = "UUID of the Lambda event source mapping"
  value       = aws_lambda_event_source_mapping.kinesis_trigger.uuid
}

output "lambda_event_source_mapping_state" {
  description = "State of the Lambda event source mapping"
  value       = aws_lambda_event_source_mapping.kinesis_trigger.state
}

# DynamoDB Table Outputs
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.retail_events_data.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.retail_events_data.arn
}

output "dynamodb_table_id" {
  description = "ID of the DynamoDB table"
  value       = aws_dynamodb_table.retail_events_data.id
}

output "dynamodb_table_stream_arn" {
  description = "ARN of the DynamoDB table stream (if enabled)"
  value       = aws_dynamodb_table.retail_events_data.stream_arn
}

# SQS Dead Letter Queue Outputs
output "sqs_dlq_url" {
  description = "URL of the SQS dead letter queue"
  value       = aws_sqs_queue.failed_events_dlq.url
}

output "sqs_dlq_arn" {
  description = "ARN of the SQS dead letter queue"
  value       = aws_sqs_queue.failed_events_dlq.arn
}

output "sqs_dlq_name" {
  description = "Name of the SQS dead letter queue"
  value       = aws_sqs_queue.failed_events_dlq.name
}

# CloudWatch Alarm Outputs
output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm for monitoring errors"
  value       = aws_cloudwatch_metric_alarm.stream_processing_errors.alarm_name
}

output "cloudwatch_alarm_arn" {
  description = "ARN of the CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.stream_processing_errors.arn
}

output "cloudwatch_alarm_id" {
  description = "ID of the CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.stream_processing_errors.id
}

# SNS Topic Outputs (if email notification is configured)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications (if configured)"
  value       = var.sns_email_endpoint != "" ? aws_sns_topic.alert_topic[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications (if configured)"
  value       = var.sns_email_endpoint != "" ? aws_sns_topic.alert_topic[0].name : null
}

output "sns_subscription_arn" {
  description = "ARN of the SNS email subscription (if configured)"
  value       = var.sns_email_endpoint != "" ? aws_sns_topic_subscription.email_alert[0].arn : null
}

# CloudWatch Log Groups
output "lambda_log_group_name" {
  description = "Name of the Lambda function's CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the Lambda function's CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# Test Producer Script Information
output "test_data_producer_instructions" {
  description = "Instructions for testing the data pipeline"
  value = {
    generate_test_data_command = "python3 ${path.module}/test_data_producer.py ${aws_kinesis_stream.retail_events_stream.name} 50 0.2"
    verify_processing_command  = "aws dynamodb scan --table-name ${aws_dynamodb_table.retail_events_data.name} --limit 5"
    view_logs_command         = "aws logs tail /aws/lambda/${aws_lambda_function.retail_event_processor.function_name} --follow"
    check_dlq_command         = "aws sqs receive-message --queue-url ${aws_sqs_queue.failed_events_dlq.url} --max-number-of-messages 5"
  }
}

# Cost Estimation Outputs
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the infrastructure (USD)"
  value = {
    kinesis_stream = "~$15-30 (based on 1 shard and moderate throughput)"
    lambda         = "~$5-20 (based on execution frequency and duration)"
    dynamodb       = "~$5-15 (PAY_PER_REQUEST mode with moderate usage)"
    cloudwatch     = "~$1-5 (logs and metrics)"
    sqs_dlq        = "~$0-2 (minimal usage expected)"
    total_estimate = "~$26-72 per month for moderate traffic volumes"
    note          = "Actual costs depend on data volume, request frequency, and retention settings"
  }
}

# Deployment Information
output "deployment_info" {
  description = "Important deployment and configuration information"
  value = {
    region                = var.region
    environment          = var.environment
    project_name         = var.project_name
    deployment_timestamp = timestamp()
    terraform_workspace  = terraform.workspace
    lambda_runtime       = aws_lambda_function.retail_event_processor.runtime
    lambda_memory_mb     = aws_lambda_function.retail_event_processor.memory_size
    lambda_timeout_sec   = aws_lambda_function.retail_event_processor.timeout
    kinesis_shards       = aws_kinesis_stream.retail_events_stream.shard_count
    kinesis_retention_hours = aws_kinesis_stream.retail_events_stream.retention_period
    dynamodb_billing_mode = aws_dynamodb_table.retail_events_data.billing_mode
  }
}

# Monitoring and Troubleshooting Outputs
output "monitoring_urls" {
  description = "Direct links to monitoring dashboards and logs"
  value = {
    lambda_console_url = "https://${var.region}.console.aws.amazon.com/lambda/home?region=${var.region}#/functions/${aws_lambda_function.retail_event_processor.function_name}"
    kinesis_console_url = "https://${var.region}.console.aws.amazon.com/kinesis/home?region=${var.region}#/streams/details/${aws_kinesis_stream.retail_events_stream.name}/details"
    dynamodb_console_url = "https://${var.region}.console.aws.amazon.com/dynamodbv2/home?region=${var.region}#table?name=${aws_dynamodb_table.retail_events_data.name}"
    cloudwatch_logs_url = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_logs.name, "/", "$252F")}"
    cloudwatch_metrics_url = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#metricsV2:graph=~();search=RetailEventProcessing"
  }
}