# Outputs for Dead Letter Queue Processing infrastructure

# SQS Queue Information
output "main_queue_url" {
  description = "URL of the main processing SQS queue"
  value       = aws_sqs_queue.main.url
}

output "main_queue_arn" {
  description = "ARN of the main processing SQS queue"
  value       = aws_sqs_queue.main.arn
}

output "main_queue_name" {
  description = "Name of the main processing SQS queue"
  value       = aws_sqs_queue.main.name
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

# Lambda Function Information
output "main_processor_function_name" {
  description = "Name of the main processing Lambda function"
  value       = aws_lambda_function.main_processor.function_name
}

output "main_processor_function_arn" {
  description = "ARN of the main processing Lambda function"
  value       = aws_lambda_function.main_processor.arn
}

output "dlq_monitor_function_name" {
  description = "Name of the DLQ monitoring Lambda function"
  value       = aws_lambda_function.dlq_monitor.function_name
}

output "dlq_monitor_function_arn" {
  description = "ARN of the DLQ monitoring Lambda function"
  value       = aws_lambda_function.dlq_monitor.arn
}

# IAM Role Information
output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

# CloudWatch Log Groups
output "main_processor_log_group" {
  description = "CloudWatch log group for main processor function"
  value       = aws_cloudwatch_log_group.main_processor_logs.name
}

output "dlq_monitor_log_group" {
  description = "CloudWatch log group for DLQ monitor function"
  value       = aws_cloudwatch_log_group.dlq_monitor_logs.name
}

# CloudWatch Alarms (conditional)
output "dlq_alarm_name" {
  description = "Name of the DLQ messages CloudWatch alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.dlq_messages[0].alarm_name : null
}

output "error_rate_alarm_name" {
  description = "Name of the error rate CloudWatch alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.error_rate[0].alarm_name : null
}

# Event Source Mappings
output "main_queue_event_mapping_uuid" {
  description = "UUID of the main queue event source mapping"
  value       = aws_lambda_event_source_mapping.main_queue_mapping.uuid
}

output "dlq_event_mapping_uuid" {
  description = "UUID of the DLQ event source mapping"
  value       = aws_lambda_event_source_mapping.dlq_mapping.uuid
}

# Configuration Information
output "max_receive_count" {
  description = "Maximum receive count before messages are sent to DLQ"
  value       = var.max_receive_count
}

output "message_retention_period" {
  description = "Message retention period in seconds"
  value       = var.message_retention_period
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Environment Variables for Testing
output "environment_variables" {
  description = "Environment variables for testing and CLI commands"
  value = {
    AWS_REGION         = data.aws_region.current.name
    AWS_ACCOUNT_ID     = data.aws_caller_identity.current.account_id
    MAIN_QUEUE_URL     = aws_sqs_queue.main.url
    DLQ_URL            = aws_sqs_queue.dlq.url
    MAIN_QUEUE_NAME    = aws_sqs_queue.main.name
    DLQ_NAME           = aws_sqs_queue.dlq.name
    PROCESSOR_FUNCTION = aws_lambda_function.main_processor.function_name
    MONITOR_FUNCTION   = aws_lambda_function.dlq_monitor.function_name
    RANDOM_SUFFIX      = random_id.suffix.hex
  }
}

# Testing Commands
output "test_commands" {
  description = "Useful commands for testing the DLQ processing system"
  value = {
    send_test_message = "aws sqs send-message --queue-url ${aws_sqs_queue.main.url} --message-body '{\"orderId\":\"TEST-001\",\"orderValue\":500,\"customerId\":\"CUST-001\"}'"
    check_main_queue  = "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.main.url} --attribute-names ApproximateNumberOfMessages"
    check_dlq         = "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.dlq.url} --attribute-names ApproximateNumberOfMessages"
    view_main_logs    = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.main_processor_logs.name} --start-time $(date -d '10 minutes ago' +%s)000"
    view_dlq_logs     = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.dlq_monitor_logs.name} --start-time $(date -d '10 minutes ago' +%s)000"
  }
}

# Monitoring URLs (CloudWatch Console Links)
output "monitoring_urls" {
  description = "CloudWatch console URLs for monitoring"
  value = {
    main_queue_metrics = "https://${data.aws_region.current.name}.console.aws.amazon.com/sqs/v2/home?region=${data.aws_region.current.name}#/queues/https%3A%2F%2Fsqs.${data.aws_region.current.name}.amazonaws.com%2F${data.aws_caller_identity.current.account_id}%2F${aws_sqs_queue.main.name}"
    dlq_metrics        = "https://${data.aws_region.current.name}.console.aws.amazon.com/sqs/v2/home?region=${data.aws_region.current.name}#/queues/https%3A%2F%2Fsqs.${data.aws_region.current.name}.amazonaws.com%2F${data.aws_caller_identity.current.account_id}%2F${aws_sqs_queue.dlq.name}"
    lambda_metrics     = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions"
    cloudwatch_alarms  = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#alarmsV2:"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for development workloads"
  value = {
    sqs_requests      = "First 1M requests free, then $0.40 per million requests"
    lambda_invocations = "First 1M invocations free, then $0.20 per million invocations"
    lambda_compute    = "First 400,000 GB-seconds free, then $0.0000166667 per GB-second"
    cloudwatch_logs   = "First 5 GB free, then $0.50 per GB ingested"
    estimated_monthly = "$5-10 for development workloads with moderate message volume"
  }
}