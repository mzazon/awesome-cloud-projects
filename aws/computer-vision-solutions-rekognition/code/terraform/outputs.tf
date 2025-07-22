# Output values for the Computer Vision Solutions with Amazon Rekognition
# These outputs provide important information for using the deployed infrastructure

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket for image storage"
  value       = aws_s3_bucket.image_storage.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for image storage"
  value       = aws_s3_bucket.image_storage.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.image_storage.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.image_storage.bucket_regional_domain_name
}

# Rekognition Collection Information
output "rekognition_collection_id" {
  description = "ID of the Rekognition face collection"
  value       = aws_rekognition_collection.face_collection.collection_id
}

output "rekognition_collection_arn" {
  description = "ARN of the Rekognition face collection"
  value       = aws_rekognition_collection.face_collection.collection_arn
}

output "rekognition_collection_face_count" {
  description = "Number of faces in the Rekognition collection"
  value       = aws_rekognition_collection.face_collection.face_count
}

# Lambda Function Information
output "lambda_function_name" {
  description = "Name of the Lambda function for image processing"
  value       = aws_lambda_function.image_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for image processing"
  value       = aws_lambda_function.image_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.image_processor.invoke_arn
}

output "lambda_function_last_modified" {
  description = "Last modified date of the Lambda function"
  value       = aws_lambda_function.image_processor.last_modified
}

# IAM Role Information
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# DynamoDB Table Information (conditional)
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for analysis results"
  value       = var.enable_dynamodb ? aws_dynamodb_table.analysis_results[0].name : null
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for analysis results"
  value       = var.enable_dynamodb ? aws_dynamodb_table.analysis_results[0].arn : null
}

output "dynamodb_table_stream_arn" {
  description = "Stream ARN of the DynamoDB table"
  value       = var.enable_dynamodb ? aws_dynamodb_table.analysis_results[0].stream_arn : null
}

# CloudWatch Log Group Information (conditional)
output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].arn : null
}

# API Gateway Information (conditional)
output "api_gateway_rest_api_id" {
  description = "ID of the API Gateway REST API"
  value       = var.enable_api_gateway ? aws_api_gateway_rest_api.computer_vision_api[0].id : null
}

output "api_gateway_rest_api_execution_arn" {
  description = "Execution ARN of the API Gateway REST API"
  value       = var.enable_api_gateway ? aws_api_gateway_rest_api.computer_vision_api[0].execution_arn : null
}

output "api_gateway_url" {
  description = "URL of the API Gateway endpoint"
  value       = var.enable_api_gateway ? "https://${aws_api_gateway_rest_api.computer_vision_api[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}" : null
}

output "api_gateway_analyze_endpoint" {
  description = "Full URL for the analyze endpoint"
  value       = var.enable_api_gateway ? "https://${aws_api_gateway_rest_api.computer_vision_api[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/analyze" : null
}

# SNS Topic Information (conditional)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = var.enable_sns_notifications ? aws_sns_topic.analysis_notifications[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = var.enable_sns_notifications ? aws_sns_topic.analysis_notifications[0].name : null
}

# VPC Endpoint Information (conditional)
output "vpc_endpoint_id" {
  description = "ID of the S3 VPC endpoint"
  value       = var.enable_vpc_endpoint ? aws_vpc_endpoint.s3_endpoint[0].id : null
}

output "vpc_endpoint_dns_entries" {
  description = "DNS entries for the S3 VPC endpoint"
  value       = var.enable_vpc_endpoint ? aws_vpc_endpoint.s3_endpoint[0].dns_entry : null
}

# Deployment Information
output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "deployment_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the deployed computer vision solution"
  value = {
    upload_images = "Upload images to s3://${aws_s3_bucket.image_storage.bucket}/images/ to trigger automatic analysis"
    view_results  = "Analysis results are stored in s3://${aws_s3_bucket.image_storage.bucket}/results/ and ${var.enable_dynamodb ? "DynamoDB table: ${aws_dynamodb_table.analysis_results[0].name}" : "S3 only"}"
    api_endpoint  = var.enable_api_gateway ? "Use POST requests to: https://${aws_api_gateway_rest_api.computer_vision_api[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/analyze" : "API Gateway not enabled"
    logs         = var.enable_cloudwatch_logs ? "Monitor logs at: /aws/lambda/${aws_lambda_function.image_processor.function_name}" : "CloudWatch logs not enabled"
  }
}

# Sample CLI Commands
output "sample_cli_commands" {
  description = "Sample CLI commands for testing the solution"
  value = {
    upload_test_image = "aws s3 cp my-image.jpg s3://${aws_s3_bucket.image_storage.bucket}/images/"
    list_collection_faces = "aws rekognition list-faces --collection-id ${aws_rekognition_collection.face_collection.collection_id}"
    view_lambda_logs = var.enable_cloudwatch_logs ? "aws logs tail /aws/lambda/${aws_lambda_function.image_processor.function_name} --follow" : "CloudWatch logs not enabled"
    query_dynamodb = var.enable_dynamodb ? "aws dynamodb scan --table-name ${aws_dynamodb_table.analysis_results[0].name}" : "DynamoDB not enabled"
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs with this solution"
  value = {
    s3_lifecycle = var.s3_lifecycle_enabled ? "S3 lifecycle policies are enabled to transition objects to cheaper storage classes" : "Enable S3 lifecycle policies to reduce storage costs"
    dynamodb_mode = var.enable_dynamodb ? "DynamoDB is set to ${var.dynamodb_billing_mode} billing mode" : "DynamoDB not enabled"
    lambda_memory = "Lambda memory is set to ${var.lambda_memory_size}MB - adjust based on performance needs"
    rekognition_free_tier = "Rekognition provides 1,000 free image analyses per month for the first 12 months"
  }
}

# Security Information
output "security_features" {
  description = "Security features implemented in this solution"
  value = {
    s3_encryption = var.enable_s3_encryption ? "S3 server-side encryption is enabled" : "S3 encryption is disabled"
    s3_public_access = "S3 public access is blocked for security"
    iam_least_privilege = "IAM roles follow least privilege principle"
    dynamodb_encryption = var.enable_dynamodb ? "DynamoDB encryption at rest is enabled" : "DynamoDB not enabled"
    vpc_endpoint = var.enable_vpc_endpoint ? "VPC endpoint is configured for S3 access" : "VPC endpoint not configured"
  }
}