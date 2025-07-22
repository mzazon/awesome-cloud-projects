# Output values for the asynchronous API patterns infrastructure

#------------------------------------------------------------------------------
# API Gateway Outputs
#------------------------------------------------------------------------------

output "api_gateway_url" {
  description = "Base URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}"
}

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.main.id
}

output "api_gateway_name" {
  description = "Name of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.main.name
}

output "api_submit_endpoint" {
  description = "Full URL for the job submission endpoint"
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/submit"
}

output "api_status_endpoint" {
  description = "Base URL for the status checking endpoint (append /{jobId})"
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/status"
}

#------------------------------------------------------------------------------
# SQS Queue Outputs
#------------------------------------------------------------------------------

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

#------------------------------------------------------------------------------
# DynamoDB Table Outputs
#------------------------------------------------------------------------------

output "jobs_table_name" {
  description = "Name of the DynamoDB jobs table"
  value       = aws_dynamodb_table.jobs.name
}

output "jobs_table_arn" {
  description = "ARN of the DynamoDB jobs table"
  value       = aws_dynamodb_table.jobs.arn
}

#------------------------------------------------------------------------------
# S3 Bucket Outputs
#------------------------------------------------------------------------------

output "results_bucket_name" {
  description = "Name of the S3 bucket for storing job results"
  value       = aws_s3_bucket.results.id
}

output "results_bucket_arn" {
  description = "ARN of the S3 bucket for storing job results"
  value       = aws_s3_bucket.results.arn
}

output "results_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.results.bucket_domain_name
}

#------------------------------------------------------------------------------
# Lambda Function Outputs
#------------------------------------------------------------------------------

output "job_processor_function_name" {
  description = "Name of the job processor Lambda function"
  value       = aws_lambda_function.job_processor.function_name
}

output "job_processor_function_arn" {
  description = "ARN of the job processor Lambda function"
  value       = aws_lambda_function.job_processor.arn
}

output "status_checker_function_name" {
  description = "Name of the status checker Lambda function"
  value       = aws_lambda_function.status_checker.function_name
}

output "status_checker_function_arn" {
  description = "ARN of the status checker Lambda function"
  value       = aws_lambda_function.status_checker.arn
}

#------------------------------------------------------------------------------
# IAM Role Outputs
#------------------------------------------------------------------------------

output "api_gateway_role_arn" {
  description = "ARN of the API Gateway IAM role"
  value       = aws_iam_role.api_gateway.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda.arn
}

#------------------------------------------------------------------------------
# CloudWatch Log Groups
#------------------------------------------------------------------------------

output "job_processor_log_group" {
  description = "CloudWatch log group for the job processor Lambda function"
  value       = aws_cloudwatch_log_group.job_processor.name
}

output "status_checker_log_group" {
  description = "CloudWatch log group for the status checker Lambda function"
  value       = aws_cloudwatch_log_group.status_checker.name
}

output "api_gateway_log_group" {
  description = "CloudWatch log group for API Gateway (if logging enabled)"
  value       = var.enable_api_gateway_logging ? aws_cloudwatch_log_group.api_gateway[0].name : null
}

#------------------------------------------------------------------------------
# Configuration Summary
#------------------------------------------------------------------------------

output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    project_name    = var.project_name
    environment     = var.environment
    aws_region      = var.aws_region
    api_stage_name  = var.api_stage_name
    cors_enabled    = var.enable_cors
    encryption_enabled = var.enable_encryption
    logging_enabled = var.enable_api_gateway_logging
  }
}

#------------------------------------------------------------------------------
# Usage Examples
#------------------------------------------------------------------------------

output "usage_examples" {
  description = "Example commands for testing the deployed API"
  value = {
    submit_job = "curl -X POST -H 'Content-Type: application/json' -d '{\"task\": \"example\", \"data\": {\"input\": \"test\"}}' ${aws_api_gateway_rest_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/submit"
    check_status = "curl ${aws_api_gateway_rest_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/status/{JOB_ID}"
  }
}

#------------------------------------------------------------------------------
# Resource Monitoring
#------------------------------------------------------------------------------

output "monitoring_resources" {
  description = "Resources created for monitoring and observability"
  value = {
    cloudwatch_log_groups = [
      aws_cloudwatch_log_group.job_processor.name,
      aws_cloudwatch_log_group.status_checker.name
    ]
    sqs_dlq_for_monitoring = aws_sqs_queue.dlq.name
    dynamodb_table_for_job_tracking = aws_dynamodb_table.jobs.name
  }
}

#------------------------------------------------------------------------------
# Cost Optimization Information
#------------------------------------------------------------------------------

output "cost_optimization_notes" {
  description = "Information about cost optimization features enabled"
  value = {
    dynamodb_billing_mode = var.dynamodb_billing_mode
    s3_lifecycle_enabled = "Enabled for noncurrent versions and incomplete multipart uploads"
    lambda_timeout_job_processor = "${var.lambda_timeout} seconds"
    lambda_memory_job_processor = "${var.lambda_memory_size} MB"
    sqs_message_retention = "${var.sqs_message_retention_period} seconds"
    api_throttling_enabled = "Burst: ${var.api_throttle_burst_limit}, Rate: ${var.api_throttle_rate_limit}"
  }
}

#------------------------------------------------------------------------------
# Security Information
#------------------------------------------------------------------------------

output "security_features" {
  description = "Security features implemented"
  value = {
    s3_public_access_blocked = "All public access blocked"
    s3_versioning_enabled = "Enabled"
    s3_encryption_enabled = var.enable_encryption
    sqs_encryption_enabled = var.enable_encryption
    dynamodb_encryption_enabled = var.enable_encryption
    dynamodb_point_in_time_recovery = "Enabled"
    iam_least_privilege = "Implemented with minimal required permissions"
    api_cors_configured = var.enable_cors
  }
}