# Kinesis Stream Outputs
output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.analytics_stream.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.analytics_stream.arn
}

output "kinesis_stream_shard_count" {
  description = "Number of shards in the Kinesis stream"
  value       = aws_kinesis_stream.analytics_stream.shard_count
}

output "kinesis_stream_retention_period" {
  description = "Data retention period of the Kinesis stream in hours"
  value       = aws_kinesis_stream.analytics_stream.retention_period
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the Lambda function for stream processing"
  value       = aws_lambda_function.stream_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for stream processing"
  value       = aws_lambda_function.stream_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.stream_processor.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the IAM role for the Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

# S3 Bucket Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for analytics data storage"
  value       = aws_s3_bucket.analytics_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for analytics data storage"
  value       = aws_s3_bucket.analytics_data.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.analytics_data.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.analytics_data.bucket_regional_domain_name
}

# CloudWatch Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.analytics_dashboard.dashboard_name}"
}

# Event Source Mapping Output
output "event_source_mapping_uuid" {
  description = "UUID of the Lambda event source mapping"
  value       = aws_lambda_event_source_mapping.kinesis_lambda.uuid
}

output "event_source_mapping_arn" {
  description = "ARN of the Lambda event source mapping"
  value       = aws_lambda_event_source_mapping.kinesis_lambda.arn
}

# Monitoring and Alerting Outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts (if created)"
  value       = length(aws_sns_topic.alerts) > 0 ? aws_sns_topic.alerts[0].arn : null
}

output "high_incoming_records_alarm_name" {
  description = "Name of the high incoming records CloudWatch alarm (if created)"
  value       = length(aws_cloudwatch_metric_alarm.high_incoming_records) > 0 ? aws_cloudwatch_metric_alarm.high_incoming_records[0].alarm_name : null
}

output "lambda_errors_alarm_name" {
  description = "Name of the Lambda errors CloudWatch alarm (if created)"
  value       = length(aws_cloudwatch_metric_alarm.lambda_errors) > 0 ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : null
}

# Resource Naming Outputs
output "resource_name_prefix" {
  description = "Prefix used for naming resources"
  value       = local.name_prefix
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.resource_suffix
}

# Environment Information Outputs
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Data Production Helper Outputs
output "sample_kinesis_put_record_command" {
  description = "Sample AWS CLI command to put a record into the Kinesis stream"
  value = "aws kinesis put-record --stream-name ${aws_kinesis_stream.analytics_stream.name} --partition-key 'user123' --data '{\"timestamp\":\"2023-01-01T12:00:00Z\",\"user_id\":\"user123\",\"event_type\":\"purchase\",\"amount\":99.99}'"
}

output "sample_python_producer_command" {
  description = "Sample Python command to send test data to the stream"
  value = "python3 data_producer.py ${aws_kinesis_stream.analytics_stream.name} 100"
}

# Cost Optimization Outputs
output "estimated_monthly_cost_breakdown" {
  description = "Estimated monthly cost breakdown for major components"
  value = {
    kinesis_stream_shard_hours = "~$${var.shard_count * 24 * 30 * 0.015} (${var.shard_count} shards × 24 hours × 30 days × $0.015/hour)"
    kinesis_put_payload_units  = "Variable based on data volume (first 1M units free, then $0.014 per 1M units)"
    lambda_requests           = "First 1M requests free, then $0.20 per 1M requests"
    lambda_compute            = "First 400,000 GB-seconds free, then $0.0000166667 per GB-second"
    s3_storage               = "$0.023 per GB for Standard storage"
    cloudwatch_metrics       = "$0.30 per metric per month (enhanced monitoring)"
    total_estimated          = "~$${var.shard_count * 24 * 30 * 0.015 + 20}-${var.shard_count * 24 * 30 * 0.015 + 100}/month (varies by usage)"
  }
}

# Security and Compliance Outputs
output "security_features_enabled" {
  description = "Security features enabled in this deployment"
  value = {
    kinesis_encryption_at_rest = "KMS encryption enabled"
    s3_encryption_at_rest     = "AES256 server-side encryption enabled"
    s3_public_access_blocked  = "All public access blocked"
    iam_least_privilege      = "IAM roles follow principle of least privilege"
    vpc_endpoints_recommended = "Consider VPC endpoints for enhanced security"
  }
}

# Operations and Maintenance Outputs
output "monitoring_links" {
  description = "Direct links to monitoring and management consoles"
  value = {
    kinesis_console   = "https://${data.aws_region.current.name}.console.aws.amazon.com/kinesis/home?region=${data.aws_region.current.name}#/streams/details/${aws_kinesis_stream.analytics_stream.name}/monitoring"
    lambda_console    = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.stream_processor.function_name}"
    s3_console        = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.analytics_data.bucket}"
    cloudwatch_logs   = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_logs.name, "/", "$252F")}"
    cloudwatch_dashboard = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.analytics_dashboard.dashboard_name}"
  }
}

# Troubleshooting Outputs
output "troubleshooting_commands" {
  description = "Useful AWS CLI commands for troubleshooting"
  value = {
    check_stream_status     = "aws kinesis describe-stream --stream-name ${aws_kinesis_stream.analytics_stream.name}"
    check_lambda_logs      = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name}"
    list_s3_objects        = "aws s3 ls s3://${aws_s3_bucket.analytics_data.bucket}/analytics-data/ --recursive"
    check_event_mapping    = "aws lambda get-event-source-mapping --uuid ${aws_lambda_event_source_mapping.kinesis_lambda.uuid}"
    view_kinesis_metrics   = "aws cloudwatch get-metric-statistics --namespace AWS/Kinesis --metric-name IncomingRecords --dimensions Name=StreamName,Value=${aws_kinesis_stream.analytics_stream.name} --statistics Sum --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300"
  }
}