# S3 bucket outputs
output "input_bucket_name" {
  description = "Name of the S3 bucket for input documents"
  value       = aws_s3_bucket.input_documents.bucket
}

output "input_bucket_arn" {
  description = "ARN of the S3 bucket for input documents"
  value       = aws_s3_bucket.input_documents.arn
}

output "output_bucket_name" {
  description = "Name of the S3 bucket for output summaries"
  value       = aws_s3_bucket.output_summaries.bucket
}

output "output_bucket_arn" {
  description = "ARN of the S3 bucket for output summaries"
  value       = aws_s3_bucket.output_summaries.arn
}

# Lambda function outputs
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.document_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.document_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.document_processor.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# CloudWatch outputs
output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard (if enabled)"
  value = var.enable_cloudwatch_dashboard ? (
    "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.monitoring[0].dashboard_name}"
  ) : "Dashboard not enabled"
}

# SNS outputs (conditional)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications (if enabled)"
  value       = var.enable_sns_notifications ? aws_sns_topic.notifications[0].arn : "SNS notifications not enabled"
}

# KMS outputs (conditional)
output "kms_key_id" {
  description = "ID of the KMS key used for encryption (if enabled)"
  value       = var.enable_bucket_encryption ? aws_kms_key.bucket_encryption[0].key_id : "Bucket encryption not enabled"
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption (if enabled)"
  value       = var.enable_bucket_encryption ? aws_kms_key.bucket_encryption[0].arn : "Bucket encryption not enabled"
}

output "kms_alias_name" {
  description = "Alias name of the KMS key (if enabled)"
  value       = var.enable_bucket_encryption ? aws_kms_alias.bucket_encryption[0].name : "Bucket encryption not enabled"
}

# Configuration outputs
output "bedrock_model_id" {
  description = "Bedrock model ID used for summarization"
  value       = var.bedrock_model_id
}

output "document_prefix" {
  description = "S3 prefix for input documents"
  value       = var.document_prefix
}

output "supported_document_types" {
  description = "List of supported document file extensions"
  value       = var.supported_document_types
}

output "max_document_size_mb" {
  description = "Maximum document size in MB"
  value       = var.max_document_size_mb
}

# Resource naming outputs
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "name_prefix" {
  description = "Name prefix used for resource naming"
  value       = local.name_prefix
}

# Usage instructions
output "usage_instructions" {
  description = "Instructions for using the document summarization system"
  value = <<EOF
Document Summarization System Deployment Complete!

Upload documents to: s3://${aws_s3_bucket.input_documents.bucket}/${var.document_prefix}
Summaries will be stored in: s3://${aws_s3_bucket.output_summaries.bucket}/summaries/

Example usage:
aws s3 cp your-document.pdf s3://${aws_s3_bucket.input_documents.bucket}/${var.document_prefix}

Monitor logs:
aws logs tail /aws/lambda/${aws_lambda_function.document_processor.function_name} --follow

Check for summaries:
aws s3 ls s3://${aws_s3_bucket.output_summaries.bucket}/summaries/

${var.enable_cloudwatch_dashboard ? "CloudWatch Dashboard: https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.monitoring[0].dashboard_name}" : ""}
${var.enable_sns_notifications ? "Email notifications enabled for: ${var.notification_email}" : ""}
EOF
}

# Cost optimization outputs
output "cost_optimization_notes" {
  description = "Notes for cost optimization"
  value = <<EOF
Cost Optimization Tips:
- S3 Lifecycle policies are ${var.bucket_lifecycle_enabled ? "enabled" : "disabled"}
- Lambda reserved concurrency is ${var.enable_lambda_reserved_concurrency ? "enabled (${var.lambda_reserved_concurrency})" : "disabled"}
- CloudWatch log retention: 14 days
- Monitor Bedrock usage costs through CloudWatch metrics
- Consider using S3 Intelligent Tiering for larger document volumes
EOF
}

# Security configuration outputs
output "security_configuration" {
  description = "Security configuration summary"
  value = <<EOF
Security Configuration:
- S3 bucket encryption: ${var.enable_bucket_encryption ? "Enabled (KMS)" : "Disabled"}
- S3 public access: Blocked
- Lambda execution role: Least privilege IAM permissions
- VPC configuration: Not configured (consider for enhanced security)
- Resource-based policies: Applied to S3 buckets and Lambda function
EOF
}