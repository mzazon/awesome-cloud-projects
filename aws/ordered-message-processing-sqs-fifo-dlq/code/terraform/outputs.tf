# ============================================================================
# Core Infrastructure Outputs
# ============================================================================

output "project_name" {
  description = "The project name used for resource naming"
  value       = local.project_name
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# ============================================================================
# SQS Queue Outputs
# ============================================================================

output "main_queue_url" {
  description = "URL of the main FIFO queue for message processing"
  value       = aws_sqs_queue.main_queue.url
}

output "main_queue_arn" {
  description = "ARN of the main FIFO queue"
  value       = aws_sqs_queue.main_queue.arn
}

output "main_queue_name" {
  description = "Name of the main FIFO queue"
  value       = aws_sqs_queue.main_queue.name
}

output "dlq_url" {
  description = "URL of the dead letter queue"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "ARN of the dead letter queue"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  description = "Name of the dead letter queue"
  value       = aws_sqs_queue.dlq.name
}

# ============================================================================
# DynamoDB Outputs
# ============================================================================

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for order state management"
  value       = aws_dynamodb_table.orders.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.orders.arn
}

output "dynamodb_stream_arn" {
  description = "ARN of the DynamoDB stream for real-time data changes"
  value       = aws_dynamodb_table.orders.stream_arn
}

output "dynamodb_gsi_name" {
  description = "Name of the Global Secondary Index for message group queries"
  value       = "MessageGroup-ProcessedAt-index"
}

# ============================================================================
# S3 Bucket Outputs
# ============================================================================

output "s3_archive_bucket_name" {
  description = "Name of the S3 bucket for message archiving"
  value       = aws_s3_bucket.message_archive.bucket
}

output "s3_archive_bucket_arn" {
  description = "ARN of the S3 archive bucket"
  value       = aws_s3_bucket.message_archive.arn
}

output "s3_archive_bucket_domain_name" {
  description = "Domain name of the S3 archive bucket"
  value       = aws_s3_bucket.message_archive.bucket_domain_name
}

# ============================================================================
# SNS Topic Outputs
# ============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for operational alerts"
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.alerts.name
}

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "message_processor_function_name" {
  description = "Name of the message processor Lambda function"
  value       = aws_lambda_function.message_processor.function_name
}

output "message_processor_function_arn" {
  description = "ARN of the message processor Lambda function"
  value       = aws_lambda_function.message_processor.arn
}

output "poison_handler_function_name" {
  description = "Name of the poison message handler Lambda function"
  value       = aws_lambda_function.poison_handler.function_name
}

output "poison_handler_function_arn" {
  description = "ARN of the poison message handler Lambda function"
  value       = aws_lambda_function.poison_handler.arn
}

output "message_replay_function_name" {
  description = "Name of the message replay Lambda function"
  value       = aws_lambda_function.message_replay.function_name
}

output "message_replay_function_arn" {
  description = "ARN of the message replay Lambda function"
  value       = aws_lambda_function.message_replay.arn
}

# ============================================================================
# IAM Role Outputs
# ============================================================================

output "processor_role_arn" {
  description = "ARN of the message processor IAM role"
  value       = aws_iam_role.processor_role.arn
}

output "poison_handler_role_arn" {
  description = "ARN of the poison message handler IAM role"
  value       = aws_iam_role.poison_handler_role.arn
}

# ============================================================================
# CloudWatch Outputs
# ============================================================================

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for Lambda functions"
  value = {
    processor      = aws_cloudwatch_log_group.processor_logs.name
    poison_handler = aws_cloudwatch_log_group.poison_handler_logs.name
    replay         = aws_cloudwatch_log_group.replay_logs.name
  }
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarms for monitoring"
  value = {
    high_failure_rate     = aws_cloudwatch_metric_alarm.high_failure_rate.alarm_name
    poison_messages       = aws_cloudwatch_metric_alarm.poison_messages_detected.alarm_name
    high_latency         = aws_cloudwatch_metric_alarm.high_processing_latency.alarm_name
  }
}

# ============================================================================
# KMS Outputs (if encryption is enabled)
# ============================================================================

output "kms_key_id" {
  description = "ID of the KMS key used for encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.fifo_processing_key[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.fifo_processing_key[0].arn : null
}

output "kms_alias_name" {
  description = "Alias name of the KMS key (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_alias.fifo_processing_alias[0].name : null
}

# ============================================================================
# Event Source Mapping Outputs
# ============================================================================

output "processor_event_source_mapping_uuid" {
  description = "UUID of the event source mapping for message processor"
  value       = aws_lambda_event_source_mapping.processor_trigger.uuid
}

output "poison_handler_event_source_mapping_uuid" {
  description = "UUID of the event source mapping for poison handler"
  value       = aws_lambda_event_source_mapping.poison_handler_trigger.uuid
}

# ============================================================================
# Useful Commands and URLs
# ============================================================================

output "useful_commands" {
  description = "Useful AWS CLI commands for testing and monitoring"
  value = {
    send_test_message = "aws sqs send-message --queue-url ${aws_sqs_queue.main_queue.url} --message-body '{\"orderId\":\"test-001\",\"orderType\":\"BUY\",\"amount\":100,\"timestamp\":\"2025-01-11T12:00:00Z\"}' --message-group-id 'test-group' --message-deduplication-id 'test-dedup-001'"
    
    check_queue_depth = "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.main_queue.url} --attribute-names ApproximateNumberOfMessages"
    
    check_dlq_depth = "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.dlq.url} --attribute-names ApproximateNumberOfMessages"
    
    scan_orders_table = "aws dynamodb scan --table-name ${aws_dynamodb_table.orders.name} --max-items 10"
    
    list_s3_objects = "aws s3 ls s3://${aws_s3_bucket.message_archive.bucket}/poison-messages/ --recursive"
    
    view_processor_logs = "aws logs tail /aws/lambda/${aws_lambda_function.message_processor.function_name}"
    
    invoke_replay_function = "aws lambda invoke --function-name ${aws_lambda_function.message_replay.function_name} --payload '{\"replay_request\":{\"start_time\":\"2025-01-11T00:00:00Z\",\"dry_run\":true}}' response.json"
  }
}

output "aws_console_urls" {
  description = "AWS Console URLs for easy access to resources"
  value = {
    sqs_queues = "https://${data.aws_region.current.name}.console.aws.amazon.com/sqs/v2/home?region=${data.aws_region.current.name}"
    
    dynamodb_table = "https://${data.aws_region.current.name}.console.aws.amazon.com/dynamodbv2/home?region=${data.aws_region.current.name}#table?name=${aws_dynamodb_table.orders.name}"
    
    s3_bucket = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.message_archive.bucket}?region=${data.aws_region.current.name}"
    
    cloudwatch_logs = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups"
    
    cloudwatch_metrics = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();namespace=FIFO"
    
    lambda_functions = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions"
    
    sns_topic = "https://${data.aws_region.current.name}.console.aws.amazon.com/sns/v3/home?region=${data.aws_region.current.name}#/topic/${aws_sns_topic.alerts.arn}"
  }
}

# ============================================================================
# Configuration Summary
# ============================================================================

output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    fifo_queue_throughput_limit = "perMessageGroupId"
    deduplication_scope        = "messageGroup"
    max_receive_count          = var.max_receive_count
    message_retention_days     = var.message_retention_period / 86400
    lambda_reserved_concurrency = var.lambda_reserved_concurrency
    processor_batch_size       = var.processor_batch_size
    poison_handler_batch_size  = var.poison_handler_batch_size
    kms_encryption_enabled     = var.enable_kms_encryption
    s3_versioning_enabled      = var.enable_s3_versioning
    email_notifications        = var.notification_email != "" ? "enabled" : "disabled"
  }
}