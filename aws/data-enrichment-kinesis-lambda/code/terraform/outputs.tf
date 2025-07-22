# outputs.tf - Output values for the streaming data enrichment infrastructure

# =============================================================================
# Resource Identifiers
# =============================================================================

output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.data_stream.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.data_stream.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.enrichment_function.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.enrichment_function.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB lookup table"
  value       = aws_dynamodb_table.enrichment_lookup.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB lookup table"
  value       = aws_dynamodb_table.enrichment_lookup.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for enriched data"
  value       = aws_s3_bucket.enriched_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for enriched data"
  value       = aws_s3_bucket.enriched_data.arn
}

# =============================================================================
# IAM Resources
# =============================================================================

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# =============================================================================
# Event Source Mapping
# =============================================================================

output "event_source_mapping_uuid" {
  description = "UUID of the event source mapping between Kinesis and Lambda"
  value       = aws_lambda_event_source_mapping.kinesis_lambda_trigger.uuid
}

# =============================================================================
# CloudWatch Resources
# =============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarm names"
  value = var.cloudwatch_alarms_enabled ? {
    lambda_errors               = aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name
    kinesis_incoming_records    = aws_cloudwatch_metric_alarm.kinesis_incoming_records[0].alarm_name
    lambda_duration            = aws_cloudwatch_metric_alarm.lambda_duration[0].alarm_name
  } : {}
}

# =============================================================================
# Testing and Validation Commands
# =============================================================================

output "kinesis_put_record_command" {
  description = "AWS CLI command to put a test record into the Kinesis stream"
  value = <<-EOT
    aws kinesis put-record \
      --stream-name ${aws_kinesis_stream.data_stream.name} \
      --partition-key "test-user" \
      --data '{
        "event_type": "page_view",
        "user_id": "user123",
        "page": "/product/test123",
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "session_id": "test_session"
      }' \
      --region ${data.aws_region.current.name}
  EOT
}

output "lambda_logs_command" {
  description = "AWS CLI command to view Lambda function logs"
  value = <<-EOT
    aws logs filter-log-events \
      --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name} \
      --start-time $(date -d '10 minutes ago' +%s)000 \
      --region ${data.aws_region.current.name}
  EOT
}

output "s3_list_objects_command" {
  description = "AWS CLI command to list enriched data in S3"
  value = <<-EOT
    aws s3 ls s3://${aws_s3_bucket.enriched_data.bucket}/enriched-data/ --recursive \
      --region ${data.aws_region.current.name}
  EOT
}

output "kinesis_stream_metrics_command" {
  description = "AWS CLI command to get Kinesis stream metrics"
  value = <<-EOT
    aws cloudwatch get-metric-statistics \
      --namespace AWS/Kinesis \
      --metric-name IncomingRecords \
      --dimensions Name=StreamName,Value=${aws_kinesis_stream.data_stream.name} \
      --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
      --period 300 \
      --statistics Sum \
      --region ${data.aws_region.current.name}
  EOT
}

# =============================================================================
# Resource URLs for Console Access
# =============================================================================

output "kinesis_console_url" {
  description = "URL to view Kinesis stream in AWS Console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/kinesis/home?region=${data.aws_region.current.name}#/streams/details/${aws_kinesis_stream.data_stream.name}/details"
}

output "lambda_console_url" {
  description = "URL to view Lambda function in AWS Console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.enrichment_function.function_name}"
}

output "dynamodb_console_url" {
  description = "URL to view DynamoDB table in AWS Console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/dynamodbv2/home?region=${data.aws_region.current.name}#table?name=${aws_dynamodb_table.enrichment_lookup.name}"
}

output "s3_console_url" {
  description = "URL to view S3 bucket in AWS Console"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.enriched_data.bucket}?region=${data.aws_region.current.name}"
}

output "cloudwatch_logs_console_url" {
  description = "URL to view CloudWatch logs in AWS Console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_logs.name, "/", "$252F")}"
}

# =============================================================================
# Infrastructure Summary
# =============================================================================

output "infrastructure_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    kinesis_stream = {
      name        = aws_kinesis_stream.data_stream.name
      shard_count = var.kinesis_shard_count
      encryption  = "KMS"
    }
    lambda_function = {
      name         = aws_lambda_function.enrichment_function.function_name
      runtime      = aws_lambda_function.enrichment_function.runtime
      timeout      = var.lambda_timeout
      memory_size  = var.lambda_memory_size
    }
    dynamodb_table = {
      name         = aws_dynamodb_table.enrichment_lookup.name
      billing_mode = var.dynamodb_billing_mode
    }
    s3_bucket = {
      name       = aws_s3_bucket.enriched_data.bucket
      versioning = var.s3_versioning_enabled
      encryption = "AES256"
    }
    monitoring = {
      enhanced_kinesis_monitoring = var.enable_enhanced_monitoring
      cloudwatch_alarms_enabled   = var.cloudwatch_alarms_enabled
      log_retention_days          = var.cloudwatch_log_retention_days
    }
  }
}