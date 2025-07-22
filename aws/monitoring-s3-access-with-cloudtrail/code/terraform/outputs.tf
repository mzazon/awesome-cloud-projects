# S3 Bucket Outputs
output "source_bucket_name" {
  description = "Name of the source S3 bucket being monitored"
  value       = aws_s3_bucket.source.bucket
}

output "source_bucket_arn" {
  description = "ARN of the source S3 bucket being monitored"
  value       = aws_s3_bucket.source.arn
}

output "logs_bucket_name" {
  description = "Name of the S3 bucket containing access logs"
  value       = aws_s3_bucket.logs.bucket
}

output "logs_bucket_arn" {
  description = "ARN of the S3 bucket containing access logs"
  value       = aws_s3_bucket.logs.arn
}

output "cloudtrail_bucket_name" {
  description = "Name of the S3 bucket containing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.bucket
}

output "cloudtrail_bucket_arn" {
  description = "ARN of the S3 bucket containing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.arn
}

# CloudTrail Outputs
output "cloudtrail_name" {
  description = "Name of the CloudTrail trail"
  value       = aws_cloudtrail.main.name
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = aws_cloudtrail.main.arn
}

output "cloudtrail_home_region" {
  description = "Home region of the CloudTrail trail"
  value       = aws_cloudtrail.main.home_region
}

# CloudWatch Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for CloudTrail"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.cloudtrail[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for CloudTrail"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.cloudtrail[0].arn : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = var.enable_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${var.dashboard_name}" : null
}

# SNS Outputs
output "sns_topic_name" {
  description = "Name of the SNS topic for security alerts"
  value       = var.enable_security_monitoring ? aws_sns_topic.security_alerts[0].name : null
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for security alerts"
  value       = var.enable_security_monitoring ? aws_sns_topic.security_alerts[0].arn : null
}

# EventBridge Outputs
output "eventbridge_rule_unauthorized_access" {
  description = "Name of the EventBridge rule for unauthorized access detection"
  value       = var.enable_security_monitoring ? aws_cloudwatch_event_rule.unauthorized_access[0].name : null
}

output "eventbridge_rule_bucket_policy_changes" {
  description = "Name of the EventBridge rule for bucket policy changes"
  value       = var.enable_security_monitoring ? aws_cloudwatch_event_rule.bucket_policy_changes[0].name : null
}

# Lambda Outputs
output "lambda_function_name" {
  description = "Name of the Lambda function for security monitoring"
  value       = var.enable_lambda_monitoring ? aws_lambda_function.security_monitor[0].function_name : null
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for security monitoring"
  value       = var.enable_lambda_monitoring ? aws_lambda_function.security_monitor[0].arn : null
}

# IAM Role Outputs
output "cloudtrail_logs_role_arn" {
  description = "ARN of the IAM role for CloudTrail CloudWatch integration"
  value       = var.enable_cloudwatch_logs ? aws_iam_role.cloudtrail_logs[0].arn : null
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda execution"
  value       = var.enable_lambda_monitoring ? aws_iam_role.lambda_execution[0].arn : null
}

# Configuration Outputs
output "s3_access_logging_enabled" {
  description = "Whether S3 access logging is enabled"
  value       = true
}

output "cloudtrail_data_events_enabled" {
  description = "Whether CloudTrail data events are enabled"
  value       = true
}

output "security_monitoring_enabled" {
  description = "Whether security monitoring is enabled"
  value       = var.enable_security_monitoring
}

output "lambda_monitoring_enabled" {
  description = "Whether Lambda monitoring is enabled"
  value       = var.enable_lambda_monitoring
}

output "dashboard_enabled" {
  description = "Whether CloudWatch dashboard is enabled"
  value       = var.enable_dashboard
}

# Sample Commands
output "sample_upload_command" {
  description = "Sample command to upload a file to the source bucket"
  value       = "aws s3 cp <local-file> s3://${aws_s3_bucket.source.bucket}/"
}

output "sample_logs_check_command" {
  description = "Sample command to check for access logs"
  value       = "aws s3 ls s3://${aws_s3_bucket.logs.bucket}/access-logs/ --recursive"
}

output "sample_cloudtrail_lookup_command" {
  description = "Sample command to lookup CloudTrail events"
  value       = "aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=${aws_s3_bucket.source.bucket} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S)"
}

# Security Insights Queries
output "cloudwatch_insights_failed_access_query" {
  description = "CloudWatch Insights query for failed access attempts"
  value       = var.enable_cloudwatch_logs ? "fields @timestamp, eventName, sourceIPAddress, errorCode, errorMessage | filter errorCode = \"AccessDenied\" | stats count() by sourceIPAddress | sort count desc" : null
}

output "cloudwatch_insights_unusual_access_query" {
  description = "CloudWatch Insights query for unusual access patterns"
  value       = var.enable_cloudwatch_logs ? "fields @timestamp, eventName, sourceIPAddress, userIdentity.type | filter eventName like /GetObject|PutObject|DeleteObject/ | stats count() by sourceIPAddress, userIdentity.type | sort count desc" : null
}

output "cloudwatch_insights_admin_actions_query" {
  description = "CloudWatch Insights query for administrative actions"
  value       = var.enable_cloudwatch_logs ? "fields @timestamp, eventName, sourceIPAddress, userIdentity.arn | filter eventName like /PutBucket|DeleteBucket|PutBucketPolicy/ | sort @timestamp desc" : null
}