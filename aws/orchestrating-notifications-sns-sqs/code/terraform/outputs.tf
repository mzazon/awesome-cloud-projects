# ==========================================
# SNS Outputs
# ==========================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.notifications.name
}

# ==========================================
# SQS Outputs
# ==========================================

output "email_queue_url" {
  description = "URL of the email processing queue"
  value       = aws_sqs_queue.email_queue.url
}

output "email_queue_arn" {
  description = "ARN of the email processing queue"
  value       = aws_sqs_queue.email_queue.arn
}

output "sms_queue_url" {
  description = "URL of the SMS processing queue"
  value       = aws_sqs_queue.sms_queue.url
}

output "sms_queue_arn" {
  description = "ARN of the SMS processing queue"
  value       = aws_sqs_queue.sms_queue.arn
}

output "webhook_queue_url" {
  description = "URL of the webhook processing queue"
  value       = aws_sqs_queue.webhook_queue.url
}

output "webhook_queue_arn" {
  description = "ARN of the webhook processing queue"
  value       = aws_sqs_queue.webhook_queue.arn
}

output "dlq_url" {
  description = "URL of the dead letter queue"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "ARN of the dead letter queue"
  value       = aws_sqs_queue.dlq.arn
}

# ==========================================
# Lambda Function Outputs
# ==========================================

output "email_lambda_function_name" {
  description = "Name of the email notification Lambda function"
  value       = aws_lambda_function.email_handler.function_name
}

output "email_lambda_function_arn" {
  description = "ARN of the email notification Lambda function"
  value       = aws_lambda_function.email_handler.arn
}

output "webhook_lambda_function_name" {
  description = "Name of the webhook notification Lambda function"
  value       = aws_lambda_function.webhook_handler.function_name
}

output "webhook_lambda_function_arn" {
  description = "ARN of the webhook notification Lambda function"
  value       = aws_lambda_function.webhook_handler.arn
}

output "dlq_lambda_function_name" {
  description = "Name of the DLQ processor Lambda function"
  value       = aws_lambda_function.dlq_processor.function_name
}

output "dlq_lambda_function_arn" {
  description = "ARN of the DLQ processor Lambda function"
  value       = aws_lambda_function.dlq_processor.arn
}

# ==========================================
# IAM Outputs
# ==========================================

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

# ==========================================
# CloudWatch Log Groups
# ==========================================

output "email_handler_log_group_name" {
  description = "Name of the email handler CloudWatch log group"
  value       = aws_cloudwatch_log_group.email_handler_logs.name
}

output "webhook_handler_log_group_name" {
  description = "Name of the webhook handler CloudWatch log group"
  value       = aws_cloudwatch_log_group.webhook_handler_logs.name
}

output "dlq_processor_log_group_name" {
  description = "Name of the DLQ processor CloudWatch log group"
  value       = aws_cloudwatch_log_group.dlq_processor_logs.name
}

# ==========================================
# System Information
# ==========================================

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

# ==========================================
# Test Commands
# ==========================================

output "test_sns_publish_command" {
  description = "AWS CLI command to test SNS message publishing"
  value = <<-EOF
    aws sns publish \
      --topic-arn ${aws_sns_topic.notifications.arn} \
      --message '{"subject":"Test Email","message":"This is a test email notification","recipient":"${var.test_email}"}' \
      --message-attributes '{"notification_type":{"DataType":"String","StringValue":"email"}}'
  EOF
}

output "test_webhook_publish_command" {
  description = "AWS CLI command to test webhook notification"
  value = <<-EOF
    aws sns publish \
      --topic-arn ${aws_sns_topic.notifications.arn} \
      --message '{"subject":"Test Webhook","message":"This is a test webhook notification","webhook_url":"${var.webhook_url}","payload":{"test":true}}' \
      --message-attributes '{"notification_type":{"DataType":"String","StringValue":"webhook"}}'
  EOF
}

output "test_broadcast_publish_command" {
  description = "AWS CLI command to test broadcast notification"
  value = <<-EOF
    aws sns publish \
      --topic-arn ${aws_sns_topic.notifications.arn} \
      --message '{"subject":"Broadcast Test","message":"This notification goes to all channels","recipient":"${var.test_email}","webhook_url":"${var.webhook_url}","payload":{"broadcast":true}}' \
      --message-attributes '{"notification_type":{"DataType":"String","StringValue":"all"}}'
  EOF
}

# ==========================================
# Monitoring Commands
# ==========================================

output "check_queue_depths_command" {
  description = "AWS CLI command to check queue message counts"
  value = <<-EOF
    echo "Queue Message Counts:"
    echo "Email Queue: $(aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.email_queue.url} --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text)"
    echo "SMS Queue: $(aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.sms_queue.url} --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text)"
    echo "Webhook Queue: $(aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.webhook_queue.url} --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text)"
    echo "DLQ: $(aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.dlq.url} --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text)"
  EOF
}

output "view_lambda_logs_command" {
  description = "AWS CLI command to view Lambda function logs"
  value = <<-EOF
    echo "To view logs for each Lambda function:"
    echo "Email Handler: aws logs tail ${aws_cloudwatch_log_group.email_handler_logs.name} --follow"
    echo "Webhook Handler: aws logs tail ${aws_cloudwatch_log_group.webhook_handler_logs.name} --follow"
    echo "DLQ Processor: aws logs tail ${aws_cloudwatch_log_group.dlq_processor_logs.name} --follow"
  EOF
}