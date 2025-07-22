# Outputs for S3 Scheduled Backups Infrastructure
# This file defines all output values that will be displayed after deployment

# S3 Bucket Information
output "primary_bucket_name" {
  description = "Name of the primary S3 bucket"
  value       = aws_s3_bucket.primary.bucket
}

output "primary_bucket_arn" {
  description = "ARN of the primary S3 bucket"
  value       = aws_s3_bucket.primary.arn
}

output "backup_bucket_name" {
  description = "Name of the backup S3 bucket"
  value       = aws_s3_bucket.backup.bucket
}

output "backup_bucket_arn" {
  description = "ARN of the backup S3 bucket"
  value       = aws_s3_bucket.backup.arn
}

output "backup_bucket_versioning_enabled" {
  description = "Whether versioning is enabled on the backup bucket"
  value       = var.enable_versioning
}

# Lambda Function Information
output "lambda_function_name" {
  description = "Name of the Lambda backup function"
  value       = aws_lambda_function.backup_function.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda backup function"
  value       = aws_lambda_function.backup_function.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda backup function"
  value       = aws_lambda_function.backup_function.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_backup_role.arn
}

# EventBridge Information
output "backup_schedule_rule_name" {
  description = "Name of the EventBridge schedule rule"
  value       = aws_cloudwatch_event_rule.backup_schedule.name
}

output "backup_schedule_rule_arn" {
  description = "ARN of the EventBridge schedule rule"
  value       = aws_cloudwatch_event_rule.backup_schedule.arn
}

output "backup_schedule_expression" {
  description = "The schedule expression for backup execution"
  value       = aws_cloudwatch_event_rule.backup_schedule.schedule_expression
}

# CloudWatch Logs
output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_backup_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_backup_logs.arn
}

# Configuration Information
output "lifecycle_configuration" {
  description = "Lifecycle configuration details for the backup bucket"
  value = {
    ia_transition_days     = var.lifecycle_ia_transition_days
    glacier_transition_days = var.lifecycle_glacier_transition_days
    expiration_days        = var.lifecycle_expiration_days
  }
}

output "encryption_enabled" {
  description = "Whether server-side encryption is enabled for S3 buckets"
  value       = var.enable_encryption
}

# Resource URLs and Management
output "s3_console_urls" {
  description = "AWS Console URLs for S3 buckets"
  value = {
    primary_bucket = "https://console.aws.amazon.com/s3/buckets/${aws_s3_bucket.primary.bucket}"
    backup_bucket  = "https://console.aws.amazon.com/s3/buckets/${aws_s3_bucket.backup.bucket}"
  }
}

output "lambda_console_url" {
  description = "AWS Console URL for Lambda function"
  value       = "https://console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.backup_function.function_name}"
}

output "cloudwatch_logs_url" {
  description = "AWS Console URL for CloudWatch logs"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_backup_logs.name, "/", "$252F")}"
}

output "eventbridge_console_url" {
  description = "AWS Console URL for EventBridge rule"
  value       = "https://console.aws.amazon.com/events/home?region=${data.aws_region.current.name}#/rules/${aws_cloudwatch_event_rule.backup_schedule.name}"
}

# Testing Commands
output "test_commands" {
  description = "Commands to test the backup solution"
  value = {
    upload_test_file = "echo 'Test file content' | aws s3 cp - s3://${aws_s3_bucket.primary.bucket}/test-file.txt"
    invoke_lambda    = "aws lambda invoke --function-name ${aws_lambda_function.backup_function.function_name} --payload '{}' response.json"
    check_backup     = "aws s3 ls s3://${aws_s3_bucket.backup.bucket}/"
    view_logs        = "aws logs tail /aws/lambda/${aws_lambda_function.backup_function.function_name} --follow"
  }
}

# Cost Optimization Information
output "cost_optimization_notes" {
  description = "Cost optimization information for the backup solution"
  value = {
    storage_classes = "Objects transition to Standard-IA after ${var.lifecycle_ia_transition_days} days, then to Glacier after ${var.lifecycle_glacier_transition_days} days"
    expiration      = var.lifecycle_expiration_days > 0 ? "Objects expire after ${var.lifecycle_expiration_days} days" : "No automatic expiration configured"
    lambda_cost     = "Lambda charges per invocation and execution time (typically <$0.01 per backup)"
    s3_requests     = "S3 charges apply for PUT, GET, and LIST requests during backup operations"
  }
}

# Summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    primary_bucket    = aws_s3_bucket.primary.bucket
    backup_bucket     = aws_s3_bucket.backup.bucket
    lambda_function   = aws_lambda_function.backup_function.function_name
    schedule          = aws_cloudwatch_event_rule.backup_schedule.schedule_expression
    versioning        = var.enable_versioning ? "Enabled" : "Disabled"
    encryption        = var.enable_encryption ? "Enabled" : "Disabled"
    aws_region        = data.aws_region.current.name
    deployment_time   = timestamp()
  }
}