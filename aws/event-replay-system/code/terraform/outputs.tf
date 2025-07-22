# Outputs for EventBridge Archive and Replay Infrastructure
# These outputs provide important information about the deployed resources

output "event_bus_name" {
  description = "Name of the created EventBridge event bus"
  value       = aws_cloudwatch_event_bus.custom.name
}

output "event_bus_arn" {
  description = "ARN of the created EventBridge event bus"
  value       = aws_cloudwatch_event_bus.custom.arn
}

output "archive_name" {
  description = "Name of the created EventBridge archive"
  value       = aws_cloudwatch_event_archive.main.name
}

output "archive_arn" {
  description = "ARN of the created EventBridge archive"
  value       = aws_cloudwatch_event_archive.main.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function for event processing"
  value       = aws_lambda_function.event_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for event processing"
  value       = aws_lambda_function.event_processor.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for logs and artifacts"
  value       = aws_s3_bucket.logs.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for logs and artifacts"
  value       = aws_s3_bucket.logs.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.event_rule.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.event_rule.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for Lambda function"
  value       = aws_iam_role.lambda_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "replay_monitoring_log_group_name" {
  description = "Name of the CloudWatch log group for replay monitoring"
  value       = aws_cloudwatch_log_group.replay_monitoring.name
}

output "replay_script_s3_key" {
  description = "S3 key for the replay automation script"
  value       = aws_s3_object.replay_script.key
}

output "replay_script_s3_url" {
  description = "S3 URL for the replay automation script"
  value       = "s3://${aws_s3_bucket.logs.bucket}/${aws_s3_object.replay_script.key}"
}

output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm for replay failures"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.replay_failures[0].alarm_name : "N/A - Alarms disabled"
}

output "archive_retention_days" {
  description = "Number of days events are retained in the archive"
  value       = var.archive_retention_days
}

output "event_pattern" {
  description = "Event pattern used for archive filtering"
  value       = local.event_pattern
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Cross-region replication outputs (when enabled)
output "replication_event_bus_name" {
  description = "Name of the cross-region replication event bus"
  value       = var.enable_cross_region_replication ? aws_cloudwatch_event_bus.replication[0].name : "N/A - Cross-region replication disabled"
}

output "replication_event_bus_arn" {
  description = "ARN of the cross-region replication event bus"
  value       = var.enable_cross_region_replication ? aws_cloudwatch_event_bus.replication[0].arn : "N/A - Cross-region replication disabled"
}

output "replication_region" {
  description = "AWS region for cross-region replication"
  value       = var.replication_region
}

# Usage examples for common operations
output "sample_event_command" {
  description = "Sample AWS CLI command to send test events"
  value = <<EOF
aws events put-events \
    --entries Source=myapp.orders,DetailType="Order Created",Detail='{"orderId":"test-123","amount":100,"customerId":"customer-123"}' \
    --event-bus-name ${aws_cloudwatch_event_bus.custom.name}
EOF
}

output "replay_command_example" {
  description = "Example AWS CLI command to start a replay"
  value = <<EOF
aws events start-replay \
    --replay-name "manual-replay-$(date +%Y%m%d-%H%M%S)" \
    --event-source-arn ${aws_cloudwatch_event_bus.custom.arn} \
    --event-start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --event-end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --destination '{"Arn": "${aws_cloudwatch_event_bus.custom.arn}"}'
EOF
}

output "monitor_lambda_logs_command" {
  description = "AWS CLI command to monitor Lambda function logs"
  value = <<EOF
aws logs tail ${aws_cloudwatch_log_group.lambda_logs.name} --follow
EOF
}

output "check_archive_status_command" {
  description = "AWS CLI command to check archive status"
  value = <<EOF
aws events describe-archive --archive-name ${aws_cloudwatch_event_archive.main.name}
EOF
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = <<EOF
EventBridge Archive and Replay Infrastructure Deployed Successfully!

Key Resources:
- Event Bus: ${aws_cloudwatch_event_bus.custom.name}
- Archive: ${aws_cloudwatch_event_archive.main.name} (${var.archive_retention_days} days retention)
- Lambda Function: ${aws_lambda_function.event_processor.function_name}
- S3 Bucket: ${aws_s3_bucket.logs.bucket}
- EventBridge Rule: ${aws_cloudwatch_event_rule.event_rule.name}

Next Steps:
1. Send test events using the sample_event_command
2. Wait for events to be archived (up to 10 minutes)
3. Use the replay_command_example to test replay functionality
4. Monitor Lambda logs using monitor_lambda_logs_command

For automation, use the replay script at: s3://${aws_s3_bucket.logs.bucket}/${aws_s3_object.replay_script.key}
EOF
}