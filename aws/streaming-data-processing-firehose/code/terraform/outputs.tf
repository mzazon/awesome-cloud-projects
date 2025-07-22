# Outputs for Real-Time Data Processing with Kinesis Data Firehose

# S3 Bucket Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for data storage"
  value       = aws_s3_bucket.data_lake.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for data storage"
  value       = aws_s3_bucket.data_lake.arn
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.data_lake.bucket_regional_domain_name
}

# Kinesis Data Firehose Outputs
output "firehose_s3_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream for S3"
  value       = aws_kinesis_firehose_delivery_stream.s3_stream.name
}

output "firehose_s3_stream_arn" {
  description = "ARN of the Kinesis Data Firehose delivery stream for S3"
  value       = aws_kinesis_firehose_delivery_stream.s3_stream.arn
}

output "firehose_opensearch_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream for OpenSearch"
  value       = aws_kinesis_firehose_delivery_stream.opensearch_stream.name
}

output "firehose_opensearch_stream_arn" {
  description = "ARN of the Kinesis Data Firehose delivery stream for OpenSearch"
  value       = aws_kinesis_firehose_delivery_stream.opensearch_stream.arn
}

# Lambda Function Outputs
output "lambda_transform_function_name" {
  description = "Name of the Lambda data transformation function"
  value       = aws_lambda_function.data_transform.function_name
}

output "lambda_transform_function_arn" {
  description = "ARN of the Lambda data transformation function"
  value       = aws_lambda_function.data_transform.arn
}

output "lambda_transform_function_invoke_arn" {
  description = "Invoke ARN of the Lambda data transformation function"
  value       = aws_lambda_function.data_transform.invoke_arn
}

output "lambda_error_handler_function_name" {
  description = "Name of the Lambda error handler function"
  value       = aws_lambda_function.error_handler.function_name
}

output "lambda_error_handler_function_arn" {
  description = "ARN of the Lambda error handler function"
  value       = aws_lambda_function.error_handler.arn
}

# OpenSearch Domain Outputs
output "opensearch_domain_name" {
  description = "Name of the OpenSearch domain"
  value       = aws_opensearch_domain.search_domain.domain_name
}

output "opensearch_domain_arn" {
  description = "ARN of the OpenSearch domain"
  value       = aws_opensearch_domain.search_domain.arn
}

output "opensearch_domain_id" {
  description = "ID of the OpenSearch domain"
  value       = aws_opensearch_domain.search_domain.domain_id
}

output "opensearch_endpoint" {
  description = "Endpoint of the OpenSearch domain"
  value       = aws_opensearch_domain.search_domain.endpoint
}

output "opensearch_kibana_endpoint" {
  description = "Kibana endpoint of the OpenSearch domain"
  value       = aws_opensearch_domain.search_domain.kibana_endpoint
}

output "opensearch_dashboard_endpoint" {
  description = "Dashboard endpoint of the OpenSearch domain"
  value       = aws_opensearch_domain.search_domain.dashboard_endpoint
}

# IAM Role Outputs
output "firehose_role_name" {
  description = "Name of the Kinesis Data Firehose IAM role"
  value       = aws_iam_role.firehose_role.name
}

output "firehose_role_arn" {
  description = "ARN of the Kinesis Data Firehose IAM role"
  value       = aws_iam_role.firehose_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_role.arn
}

# CloudWatch Outputs
output "cloudwatch_log_group_s3_name" {
  description = "Name of the CloudWatch log group for S3 delivery"
  value       = aws_cloudwatch_log_group.s3_delivery_log.name
}

output "cloudwatch_log_group_s3_arn" {
  description = "ARN of the CloudWatch log group for S3 delivery"
  value       = aws_cloudwatch_log_group.s3_delivery_log.arn
}

output "cloudwatch_log_group_opensearch_name" {
  description = "Name of the CloudWatch log group for OpenSearch delivery"
  value       = aws_cloudwatch_log_group.opensearch_delivery_log.name
}

output "cloudwatch_log_group_opensearch_arn" {
  description = "ARN of the CloudWatch log group for OpenSearch delivery"
  value       = aws_cloudwatch_log_group.opensearch_delivery_log.arn
}

# CloudWatch Alarms Outputs
output "cloudwatch_alarm_s3_errors_name" {
  description = "Name of the CloudWatch alarm for S3 delivery errors"
  value       = aws_cloudwatch_metric_alarm.s3_delivery_errors.alarm_name
}

output "cloudwatch_alarm_s3_errors_arn" {
  description = "ARN of the CloudWatch alarm for S3 delivery errors"
  value       = aws_cloudwatch_metric_alarm.s3_delivery_errors.arn
}

output "cloudwatch_alarm_opensearch_errors_name" {
  description = "Name of the CloudWatch alarm for OpenSearch delivery errors"
  value       = aws_cloudwatch_metric_alarm.opensearch_delivery_errors.alarm_name
}

output "cloudwatch_alarm_opensearch_errors_arn" {
  description = "ARN of the CloudWatch alarm for OpenSearch delivery errors"
  value       = aws_cloudwatch_metric_alarm.opensearch_delivery_errors.arn
}

output "cloudwatch_alarm_lambda_errors_name" {
  description = "Name of the CloudWatch alarm for Lambda errors"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "cloudwatch_alarm_lambda_errors_arn" {
  description = "ARN of the CloudWatch alarm for Lambda errors"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.arn
}

# SQS Dead Letter Queue Outputs
output "dlq_url" {
  description = "URL of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "ARN of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  description = "Name of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.name
}

# Resource Naming Outputs
output "resource_prefix" {
  description = "Prefix used for naming resources"
  value       = local.resource_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource names"
  value       = random_string.suffix.result
}

# Regional Information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Data Access URLs
output "s3_data_urls" {
  description = "S3 URLs for accessing different data types"
  value = {
    raw_data         = "s3://${aws_s3_bucket.data_lake.bucket}/raw-data/"
    transformed_data = "s3://${aws_s3_bucket.data_lake.bucket}/transformed-data/"
    error_data       = "s3://${aws_s3_bucket.data_lake.bucket}/error-data/"
    opensearch_backup = "s3://${aws_s3_bucket.data_lake.bucket}/opensearch-backup/"
  }
}

# API Commands for Data Ingestion
output "firehose_put_record_command" {
  description = "AWS CLI command to put a record into the S3 Firehose stream"
  value       = "aws firehose put-record --delivery-stream-name ${aws_kinesis_firehose_delivery_stream.s3_stream.name} --record Data=<base64-encoded-data>"
}

output "firehose_put_record_batch_command" {
  description = "AWS CLI command to put a batch of records into the S3 Firehose stream"
  value       = "aws firehose put-record-batch --delivery-stream-name ${aws_kinesis_firehose_delivery_stream.s3_stream.name} --records <records-array>"
}

# Monitoring URLs
output "cloudwatch_dashboard_url" {
  description = "URL to CloudWatch dashboard for monitoring"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:"
}

output "opensearch_dashboard_url" {
  description = "URL to OpenSearch dashboard"
  value       = "https://${aws_opensearch_domain.search_domain.dashboard_endpoint}/"
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of key configuration parameters"
  value = {
    project_name           = var.project_name
    environment           = var.environment
    s3_buffer_size        = var.s3_buffer_size
    s3_buffer_interval    = var.s3_buffer_interval
    opensearch_buffer_size = var.opensearch_buffer_size
    opensearch_buffer_interval = var.opensearch_buffer_interval
    opensearch_instance_type = var.opensearch_instance_type
    opensearch_instance_count = var.opensearch_instance_count
    lambda_timeout        = var.lambda_timeout
    lambda_memory_size    = var.lambda_memory_size
    parquet_enabled       = var.enable_parquet_conversion
    transformation_enabled = var.enable_data_transformation
    encryption_enabled    = var.enable_s3_encryption
  }
}

# Testing Commands
output "test_commands" {
  description = "Commands for testing the data pipeline"
  value = {
    create_test_data = "echo '{\"event_id\":\"test001\",\"user_id\":\"user123\",\"event_type\":\"purchase\",\"amount\":150.50}' | base64"
    send_test_record = "aws firehose put-record --delivery-stream-name ${aws_kinesis_firehose_delivery_stream.s3_stream.name} --record 'Data=<base64-data>'"
    check_s3_objects = "aws s3 ls s3://${aws_s3_bucket.data_lake.bucket}/transformed-data/ --recursive"
    query_opensearch = "curl -X GET 'https://${aws_opensearch_domain.search_domain.endpoint}/realtime-events/_search?pretty'"
    view_lambda_logs = "aws logs describe-log-streams --log-group-name /aws/lambda/${aws_lambda_function.data_transform.function_name} --order-by LastEventTime --descending"
  }
}

# Resource Tags
output "applied_tags" {
  description = "Tags applied to all resources"
  value       = local.tags
}