# Infrastructure Outputs
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# S3 Bucket Outputs
output "input_bucket_name" {
  description = "Name of the S3 input bucket for documents"
  value       = aws_s3_bucket.input.bucket
}

output "input_bucket_arn" {
  description = "ARN of the S3 input bucket"
  value       = aws_s3_bucket.input.arn
}

output "output_bucket_name" {
  description = "Name of the S3 output bucket for processed documents"
  value       = aws_s3_bucket.output.bucket
}

output "output_bucket_arn" {
  description = "ARN of the S3 output bucket"
  value       = aws_s3_bucket.output.arn
}

# DynamoDB Outputs
output "metadata_table_name" {
  description = "Name of the DynamoDB table for document metadata"
  value       = aws_dynamodb_table.metadata.name
}

output "metadata_table_arn" {
  description = "ARN of the DynamoDB metadata table"
  value       = aws_dynamodb_table.metadata.arn
}

# SNS Outputs
output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = aws_sns_topic.notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic"
  value       = aws_sns_topic.notifications.arn
}

# Lambda Function Outputs
output "document_classifier_function_name" {
  description = "Name of the document classifier Lambda function"
  value       = aws_lambda_function.document_classifier.function_name
}

output "document_classifier_function_arn" {
  description = "ARN of the document classifier Lambda function"
  value       = aws_lambda_function.document_classifier.arn
}

output "textract_processor_function_name" {
  description = "Name of the Textract processor Lambda function"
  value       = aws_lambda_function.textract_processor.function_name
}

output "textract_processor_function_arn" {
  description = "ARN of the Textract processor Lambda function"
  value       = aws_lambda_function.textract_processor.arn
}

output "async_results_processor_function_name" {
  description = "Name of the async results processor Lambda function"
  value       = aws_lambda_function.async_results_processor.function_name
}

output "async_results_processor_function_arn" {
  description = "ARN of the async results processor Lambda function"
  value       = aws_lambda_function.async_results_processor.arn
}

output "document_query_function_name" {
  description = "Name of the document query Lambda function"
  value       = aws_lambda_function.document_query.function_name
}

output "document_query_function_arn" {
  description = "ARN of the document query Lambda function"
  value       = aws_lambda_function.document_query.arn
}

# Step Functions Outputs
output "step_functions_state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.textract_workflow.name
}

output "step_functions_state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.textract_workflow.arn
}

# IAM Role Outputs
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution.arn
}

output "step_functions_role_arn" {
  description = "ARN of the Step Functions execution IAM role"
  value       = aws_iam_role.step_functions.arn
}

# CloudWatch Log Group Outputs
output "document_classifier_log_group" {
  description = "CloudWatch log group for document classifier function"
  value       = aws_cloudwatch_log_group.document_classifier.name
}

output "textract_processor_log_group" {
  description = "CloudWatch log group for Textract processor function"
  value       = aws_cloudwatch_log_group.textract_processor.name
}

output "async_results_processor_log_group" {
  description = "CloudWatch log group for async results processor function"
  value       = aws_cloudwatch_log_group.async_results_processor.name
}

output "document_query_log_group" {
  description = "CloudWatch log group for document query function"
  value       = aws_cloudwatch_log_group.document_query.name
}

output "step_functions_log_group" {
  description = "CloudWatch log group for Step Functions"
  value       = aws_cloudwatch_log_group.step_functions.name
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the deployed infrastructure"
  value = {
    upload_documents = "Upload documents to s3://${aws_s3_bucket.input.bucket}/documents/ to trigger processing"
    view_results     = "Check s3://${aws_s3_bucket.output.bucket}/results/ for processed results"
    query_metadata   = "Invoke ${aws_lambda_function.document_query.function_name} to query document metadata"
    monitor_logs     = "Check CloudWatch logs in /aws/lambda/ for function execution details"
    step_functions   = "Monitor workflow execution in Step Functions console: ${aws_sfn_state_machine.textract_workflow.name}"
  }
}

# Deployment Verification Commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    list_buckets     = "aws s3 ls | grep ${local.name_prefix}"
    check_table      = "aws dynamodb describe-table --table-name ${aws_dynamodb_table.metadata.name}"
    list_functions   = "aws lambda list-functions --query 'Functions[?contains(FunctionName, `${local.name_prefix}`)].FunctionName'"
    check_sns_topic  = "aws sns get-topic-attributes --topic-arn ${aws_sns_topic.notifications.arn}"
    test_upload      = "aws s3 cp test-document.pdf s3://${aws_s3_bucket.input.bucket}/documents/"
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = {
    s3_lifecycle    = "S3 lifecycle policies are ${var.s3_lifecycle_enabled ? "enabled" : "disabled"} - consider enabling for cost savings"
    dynamodb_mode   = "DynamoDB is using ${var.dynamodb_billing_mode} billing mode"
    lambda_memory   = "Lambda functions are configured with ${var.lambda_memory_size}MB memory - adjust based on usage patterns"
    log_retention   = "CloudWatch logs retention is set to ${var.lambda_log_retention_days} days"
    monitoring      = "Enhanced monitoring is ${var.enable_enhanced_monitoring ? "enabled" : "disabled"}"
  }
}

# Security Information
output "security_features" {
  description = "Security features enabled in the deployment"
  value = {
    s3_encryption        = var.enable_s3_encryption ? "S3 buckets are encrypted with AES-256" : "S3 encryption is disabled"
    dynamodb_encryption  = var.enable_dynamodb_encryption ? "DynamoDB encryption at rest is enabled" : "DynamoDB encryption is disabled"
    s3_public_access     = "S3 public access is blocked on all buckets"
    iam_least_privilege  = "IAM roles follow least privilege principle"
    sns_encryption       = "SNS topic is encrypted with AWS managed KMS key"
    vpc_endpoints        = "Consider adding VPC endpoints for enhanced security"
  }
}

# Integration Endpoints
output "integration_endpoints" {
  description = "Endpoints for integrating with external systems"
  value = {
    step_functions_api = "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:${aws_sfn_state_machine.textract_workflow.name}"
    query_lambda_api   = aws_lambda_function.document_query.arn
    sns_notifications  = aws_sns_topic.notifications.arn
    input_bucket_events = "s3://${aws_s3_bucket.input.bucket}/documents/"
  }
}