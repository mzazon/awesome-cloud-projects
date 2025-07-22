# Outputs for AWS Intelligent Document Processing with Amazon Textract
# These outputs provide important resource information for integration,
# verification, and operational management of the document processing pipeline

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket storing documents and processing results"
  value       = aws_s3_bucket.textract_documents.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for IAM policy configuration and cross-account access"
  value       = aws_s3_bucket.textract_documents.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket for direct API access"
  value       = aws_s3_bucket.textract_documents.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket for optimized access"
  value       = aws_s3_bucket.textract_documents.bucket_regional_domain_name
}

output "documents_upload_path" {
  description = "S3 path where documents should be uploaded to trigger processing"
  value       = "s3://${aws_s3_bucket.textract_documents.id}/${var.documents_prefix}/"
}

output "results_download_path" {
  description = "S3 path where processed results can be retrieved"
  value       = "s3://${aws_s3_bucket.textract_documents.id}/${var.results_prefix}/"
}

# Lambda Function Information
output "lambda_function_name" {
  description = "Name of the Lambda function processing documents with Textract"
  value       = aws_lambda_function.textract_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for integration with other AWS services"
  value       = aws_lambda_function.textract_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function for API Gateway integration"
  value       = aws_lambda_function.textract_processor.invoke_arn
}

output "lambda_function_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.textract_processor_role.arn
}

output "lambda_function_version" {
  description = "Version of the deployed Lambda function"
  value       = aws_lambda_function.textract_processor.version
}

# CloudWatch Logging Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.textract_processor_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for monitoring integration"
  value       = aws_cloudwatch_log_group.textract_processor_logs.arn
}

# Monitoring and Alarms Information
output "error_alarm_name" {
  description = "Name of the CloudWatch alarm monitoring Lambda function errors"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.lambda_error_alarm[0].alarm_name : null
}

output "duration_alarm_name" {
  description = "Name of the CloudWatch alarm monitoring Lambda function duration"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.lambda_duration_alarm[0].alarm_name : null
}

# IAM Information
output "lambda_execution_role_name" {
  description = "Name of the IAM role for Lambda function execution"
  value       = aws_iam_role.textract_processor_role.name
}

output "textract_policy_arn" {
  description = "ARN of the custom IAM policy for Textract and S3 access"
  value       = aws_iam_policy.textract_processor_policy.arn
}

# Configuration Information
output "supported_document_formats" {
  description = "List of supported document formats for processing"
  value       = var.supported_formats
}

output "processing_configuration" {
  description = "Configuration summary of the document processing pipeline"
  value = {
    lambda_runtime    = var.lambda_runtime
    lambda_timeout    = var.lambda_timeout
    lambda_memory     = var.lambda_memory_size
    log_retention     = var.log_retention_days
    monitoring_enabled = var.enable_monitoring
    textract_api_version = var.textract_api_version
  }
}

# Regional Information
output "aws_region" {
  description = "AWS region where the infrastructure is deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where the infrastructure is deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Security Information
output "bucket_encryption_status" {
  description = "Encryption configuration of the S3 bucket"
  value = {
    server_side_encryption = "AES256"
    public_access_blocked  = true
    versioning_enabled     = true
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the infrastructure (USD)"
  value = {
    s3_storage_gb     = "~$0.023 per GB stored"
    lambda_requests   = "~$0.20 per 1M requests"
    lambda_duration   = "~$0.0000166667 per GB-second"
    textract_pages    = "~$1.50 per 1000 pages"
    cloudwatch_logs   = "~$0.50 per GB ingested"
    note             = "Actual costs depend on usage patterns and document volume"
  }
}

# Integration Information
output "integration_endpoints" {
  description = "Key endpoints and identifiers for integrating with external systems"
  value = {
    upload_endpoint   = "s3://${aws_s3_bucket.textract_documents.id}/${var.documents_prefix}/"
    results_endpoint  = "s3://${aws_s3_bucket.textract_documents.id}/${var.results_prefix}/"
    lambda_function   = aws_lambda_function.textract_processor.function_name
    log_group        = aws_cloudwatch_log_group.textract_processor_logs.name
  }
}

# Environment Information
output "deployment_details" {
  description = "Details about the current deployment for operations and troubleshooting"
  value = {
    environment       = var.environment
    project_name      = var.project_name
    resource_prefix   = local.name_prefix
    random_suffix     = local.random_suffix
    deployment_time   = timestamp()
    terraform_version = ">=1.0"
  }
}

# Operational Commands
output "useful_commands" {
  description = "Useful AWS CLI commands for managing and monitoring the deployment"
  value = {
    upload_test_document = "aws s3 cp test-document.pdf s3://${aws_s3_bucket.textract_documents.id}/${var.documents_prefix}/"
    list_results        = "aws s3 ls s3://${aws_s3_bucket.textract_documents.id}/${var.results_prefix}/"
    view_lambda_logs    = "aws logs tail ${aws_cloudwatch_log_group.textract_processor_logs.name} --follow"
    invoke_lambda       = "aws lambda invoke --function-name ${aws_lambda_function.textract_processor.function_name} response.json"
    check_bucket_events = "aws s3api get-bucket-notification-configuration --bucket ${aws_s3_bucket.textract_documents.id}"
  }
}

# Troubleshooting Information
output "troubleshooting_resources" {
  description = "Resources and identifiers for troubleshooting issues"
  value = {
    lambda_function_arn    = aws_lambda_function.textract_processor.arn
    s3_bucket_name        = aws_s3_bucket.textract_documents.id
    iam_role_arn          = aws_iam_role.textract_processor_role.arn
    log_group_name        = aws_cloudwatch_log_group.textract_processor_logs.name
    error_alarm_arn       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.lambda_error_alarm[0].arn : null
    duration_alarm_arn    = var.enable_monitoring ? aws_cloudwatch_metric_alarm.lambda_duration_alarm[0].arn : null
  }
}