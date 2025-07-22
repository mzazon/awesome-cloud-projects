# Outputs for S3 Event Notifications and Automated Processing

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket for file processing"
  value       = aws_s3_bucket.file_processing.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.file_processing.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.file_processing.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.file_processing.bucket_regional_domain_name
}

# SNS Topic Information
output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.file_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.file_notifications.name
}

# SQS Queue Information
output "sqs_queue_url" {
  description = "URL of the SQS queue for batch processing"
  value       = aws_sqs_queue.batch_processing.url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue"
  value       = aws_sqs_queue.batch_processing.arn
}

output "sqs_queue_name" {
  description = "Name of the SQS queue"
  value       = aws_sqs_queue.batch_processing.name
}

output "sqs_dlq_url" {
  description = "URL of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.url
}

output "sqs_dlq_arn" {
  description = "ARN of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.arn
}

# Lambda Function Information
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.file_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.file_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.file_processor.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

# CloudWatch Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# Monitoring and Alarms
output "lambda_error_alarm_name" {
  description = "Name of the Lambda error alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "sqs_depth_alarm_name" {
  description = "Name of the SQS queue depth alarm"
  value       = aws_cloudwatch_metric_alarm.sqs_queue_depth.alarm_name
}

# Email Subscription Information
output "email_subscription_arn" {
  description = "ARN of the email subscription (if created)"
  value       = var.notification_email != "your-email@example.com" ? aws_sns_topic_subscription.email_notification[0].arn : null
}

output "email_subscription_pending" {
  description = "Whether email subscription is pending confirmation"
  value       = var.notification_email != "your-email@example.com" ? aws_sns_topic_subscription.email_notification[0].pending_confirmation : null
}

# Testing Information
output "test_upload_commands" {
  description = "CLI commands to test the event processing system"
  value = {
    sns_notification = "aws s3 cp test-file.txt s3://${aws_s3_bucket.file_processing.bucket}/uploads/test-sns.txt"
    sqs_processing   = "aws s3 cp test-file.txt s3://${aws_s3_bucket.file_processing.bucket}/batch/test-sqs.txt"
    lambda_immediate = "aws s3 cp test-file.txt s3://${aws_s3_bucket.file_processing.bucket}/immediate/test-lambda.txt"
  }
}

# Verification Commands
output "verification_commands" {
  description = "Commands to verify the infrastructure is working"
  value = {
    check_sqs_messages    = "aws sqs receive-message --queue-url ${aws_sqs_queue.batch_processing.url}"
    check_lambda_logs     = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name} --order-by LastEventTime --descending"
    check_sns_topic       = "aws sns get-topic-attributes --topic-arn ${aws_sns_topic.file_notifications.arn}"
    list_bucket_contents  = "aws s3 ls s3://${aws_s3_bucket.file_processing.bucket}/ --recursive"
  }
}

# Resource Summary
output "infrastructure_summary" {
  description = "Summary of created infrastructure resources"
  value = {
    s3_bucket          = aws_s3_bucket.file_processing.bucket
    sns_topic          = aws_sns_topic.file_notifications.name
    sqs_queue          = aws_sqs_queue.batch_processing.name
    lambda_function    = aws_lambda_function.file_processor.function_name
    cloudwatch_logs    = aws_cloudwatch_log_group.lambda_logs.name
    event_notifications = var.enable_s3_event_notifications ? "Enabled" : "Disabled"
    email_notifications = var.notification_email != "your-email@example.com" ? "Configured" : "Not configured"
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = {
    s3_lifecycle_policy   = "Consider implementing S3 lifecycle policies to transition files to cheaper storage classes"
    lambda_right_sizing   = "Monitor Lambda CloudWatch metrics to optimize memory allocation and timeout settings"
    sqs_long_polling      = "SQS long polling is enabled to reduce costs and improve efficiency"
    cloudwatch_retention  = "CloudWatch logs retention is set to ${var.cloudwatch_log_retention_days} days to control storage costs"
  }
}

# Security Information
output "security_features" {
  description = "Security features implemented"
  value = {
    s3_encryption         = "AES256 server-side encryption enabled"
    s3_public_access      = "Public access blocked"
    s3_versioning         = "Versioning enabled"
    iam_least_privilege   = "IAM roles follow principle of least privilege"
    cross_service_access  = "Resource-based policies restrict cross-service access to specific resources"
  }
}