# Output values for the clickstream analytics infrastructure

# Kinesis Stream outputs
output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.clickstream_events.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.clickstream_events.arn
}

output "kinesis_stream_shards" {
  description = "Number of shards in the Kinesis Data Stream"
  value       = aws_kinesis_stream.clickstream_events.shard_count
}

# S3 Bucket outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for raw data archive"
  value       = aws_s3_bucket.clickstream_archive.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for raw data archive"
  value       = aws_s3_bucket.clickstream_archive.arn
}

# DynamoDB Table outputs
output "dynamodb_page_metrics_table_name" {
  description = "Name of the DynamoDB table for page metrics"
  value       = aws_dynamodb_table.page_metrics.name
}

output "dynamodb_page_metrics_table_arn" {
  description = "ARN of the DynamoDB table for page metrics"
  value       = aws_dynamodb_table.page_metrics.arn
}

output "dynamodb_session_metrics_table_name" {
  description = "Name of the DynamoDB table for session metrics"
  value       = aws_dynamodb_table.session_metrics.name
}

output "dynamodb_session_metrics_table_arn" {
  description = "ARN of the DynamoDB table for session metrics"
  value       = aws_dynamodb_table.session_metrics.arn
}

output "dynamodb_counters_table_name" {
  description = "Name of the DynamoDB table for counters"
  value       = aws_dynamodb_table.counters.name
}

output "dynamodb_counters_table_arn" {
  description = "ARN of the DynamoDB table for counters"
  value       = aws_dynamodb_table.counters.arn
}

# Lambda Function outputs
output "lambda_event_processor_function_name" {
  description = "Name of the event processor Lambda function"
  value       = aws_lambda_function.event_processor.function_name
}

output "lambda_event_processor_function_arn" {
  description = "ARN of the event processor Lambda function"
  value       = aws_lambda_function.event_processor.arn
}

output "lambda_anomaly_detector_function_name" {
  description = "Name of the anomaly detector Lambda function"
  value       = var.enable_anomaly_detection ? aws_lambda_function.anomaly_detector[0].function_name : null
}

output "lambda_anomaly_detector_function_arn" {
  description = "ARN of the anomaly detector Lambda function"
  value       = var.enable_anomaly_detection ? aws_lambda_function.anomaly_detector[0].arn : null
}

# IAM Role outputs
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# SNS Topic outputs (when enabled)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for anomaly alerts"
  value       = var.enable_sns_alerts ? aws_sns_topic.anomaly_alerts[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for anomaly alerts"
  value       = var.enable_sns_alerts ? aws_sns_topic.anomaly_alerts[0].name : null
}

# Dead Letter Queue outputs
output "dlq_url" {
  description = "URL of the SQS dead letter queue"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "ARN of the SQS dead letter queue"
  value       = aws_sqs_queue.dlq.arn
}

# CloudWatch Dashboard outputs
output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value = var.enable_cloudwatch_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.clickstream_dashboard[0].dashboard_name}" : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.clickstream_dashboard[0].dashboard_name : null
}

# Resource naming outputs for external use
output "resource_name_prefix" {
  description = "Common name prefix used for all resources"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.random_suffix
}

output "table_prefix" {
  description = "Prefix used for DynamoDB table names"
  value       = local.table_prefix
}

# Configuration summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    aws_region                = var.aws_region
    environment              = var.environment
    project_name            = var.project_name
    kinesis_shard_count     = var.kinesis_shard_count
    kinesis_retention_period = var.kinesis_retention_period
    lambda_memory_size      = var.lambda_memory_size
    lambda_timeout          = var.lambda_timeout
    batch_size              = var.batch_size
    anomaly_detection_enabled = var.enable_anomaly_detection
    sns_alerts_enabled      = var.enable_sns_alerts
    cloudwatch_dashboard_enabled = var.enable_cloudwatch_dashboard
    dynamodb_billing_mode   = var.dynamodb_billing_mode
  }
}

# Test client configuration
output "test_client_configuration" {
  description = "Configuration for test client applications"
  value = {
    stream_name = aws_kinesis_stream.clickstream_events.name
    aws_region  = data.aws_region.current.name
    endpoint_url = "https://kinesis.${data.aws_region.current.name}.amazonaws.com"
  }
}

# Monitoring endpoints
output "monitoring_endpoints" {
  description = "Endpoints and resources for monitoring the solution"
  value = {
    cloudwatch_logs = {
      event_processor = "/aws/lambda/${aws_lambda_function.event_processor.function_name}"
      anomaly_detector = var.enable_anomaly_detection ? "/aws/lambda/${aws_lambda_function.anomaly_detector[0].function_name}" : null
    }
    cloudwatch_metrics = {
      namespace = "Clickstream/Events"
      kinesis_namespace = "AWS/Kinesis"
      lambda_namespace = "AWS/Lambda"
      dynamodb_namespace = "AWS/DynamoDB"
    }
    dashboard_url = var.enable_cloudwatch_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.clickstream_dashboard[0].dashboard_name}" : null
  }
}