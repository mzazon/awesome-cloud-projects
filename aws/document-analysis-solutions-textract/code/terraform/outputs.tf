# outputs.tf - Output values for the Textract document analysis solution

output "input_bucket_name" {
  description = "Name of the S3 input bucket for document uploads"
  value       = aws_s3_bucket.input_bucket.bucket
}

output "input_bucket_arn" {
  description = "ARN of the S3 input bucket"
  value       = aws_s3_bucket.input_bucket.arn
}

output "output_bucket_name" {
  description = "Name of the S3 output bucket for processed documents"
  value       = aws_s3_bucket.output_bucket.bucket
}

output "output_bucket_arn" {
  description = "ARN of the S3 output bucket"
  value       = aws_s3_bucket.output_bucket.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function processing documents"
  value       = aws_lambda_function.textract_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.textract_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.textract_processor.invoke_arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = aws_sns_topic.textract_notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.textract_notifications.arn
}

output "iam_role_name" {
  description = "Name of the IAM role used by the Lambda function"
  value       = aws_iam_role.textract_lambda_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.textract_lambda_role.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# URLs for easy access
output "input_bucket_url" {
  description = "S3 console URL for the input bucket"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.input_bucket.bucket}"
}

output "output_bucket_url" {
  description = "S3 console URL for the output bucket"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.output_bucket.bucket}"
}

output "lambda_function_url" {
  description = "AWS console URL for the Lambda function"
  value       = "https://console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.textract_processor.function_name}"
}

output "cloudwatch_logs_url" {
  description = "CloudWatch console URL for Lambda function logs"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_logs.name, "/", "$252F")}"
}

# Configuration values
output "allowed_file_extensions" {
  description = "List of allowed file extensions for processing"
  value       = var.allowed_file_extensions
}

output "textract_feature_types" {
  description = "Textract feature types enabled for document analysis"
  value       = var.textract_feature_types
}

output "lambda_configuration" {
  description = "Lambda function configuration summary"
  value = {
    runtime     = var.lambda_runtime
    timeout     = var.lambda_timeout
    memory_size = var.lambda_memory_size
    xray_tracing = var.enable_xray_tracing
  }
}

output "s3_configuration" {
  description = "S3 bucket configuration summary"
  value = {
    versioning_enabled = var.enable_s3_versioning
    encryption_enabled = var.enable_s3_encryption
    lifecycle_enabled  = var.s3_lifecycle_enabled
    lifecycle_days     = var.s3_lifecycle_expiration_days
  }
}

# Deployment instructions
output "deployment_instructions" {
  description = "Instructions for using the deployed infrastructure"
  value = <<-EOT
  
  Document Analysis Solution Deployed Successfully!
  
  Quick Start:
  1. Upload documents to: s3://${aws_s3_bucket.input_bucket.bucket}/
  2. Processed results will appear in: s3://${aws_s3_bucket.output_bucket.bucket}/processed/
  3. Monitor processing in CloudWatch Logs: ${aws_cloudwatch_log_group.lambda_logs.name}
  
  Supported file types: ${join(", ", var.allowed_file_extensions)}
  
  AWS CLI Examples:
  # Upload a document for processing
  aws s3 cp document.pdf s3://${aws_s3_bucket.input_bucket.bucket}/
  
  # List processed results
  aws s3 ls s3://${aws_s3_bucket.output_bucket.bucket}/processed/
  
  # Download processed results
  aws s3 cp s3://${aws_s3_bucket.output_bucket.bucket}/processed/document.pdf.json ./
  
  # View Lambda function logs
  aws logs describe-log-streams --log-group-name "${aws_cloudwatch_log_group.lambda_logs.name}"
  
  EOT
}

# Cost optimization tips
output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = <<-EOT
  
  Cost Optimization Tips:
  
  1. Monitor Textract usage - charges apply per page processed
  2. Use S3 lifecycle policies to automatically delete old files
  3. Consider using S3 Intelligent Tiering for long-term storage
  4. Monitor Lambda execution time and optimize memory allocation
  5. Use CloudWatch to identify unused resources
  
  Current Configuration:
  - S3 Lifecycle: ${var.s3_lifecycle_enabled ? "Enabled (${var.s3_lifecycle_expiration_days} days)" : "Disabled"}
  - Lambda Memory: ${var.lambda_memory_size}MB
  - Lambda Timeout: ${var.lambda_timeout}s
  - Log Retention: ${var.cloudwatch_log_retention_days} days
  
  EOT
}