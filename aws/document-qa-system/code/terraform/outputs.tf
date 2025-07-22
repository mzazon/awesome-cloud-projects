# S3 Bucket Outputs
output "documents_bucket_name" {
  description = "Name of the S3 bucket for document storage"
  value       = aws_s3_bucket.documents.bucket
}

output "documents_bucket_arn" {
  description = "ARN of the S3 bucket for document storage"
  value       = aws_s3_bucket.documents.arn
}

output "documents_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.documents.bucket_domain_name
}

# Kendra Outputs
output "kendra_index_id" {
  description = "ID of the Kendra index"
  value       = aws_kendra_index.main.id
}

output "kendra_index_arn" {
  description = "ARN of the Kendra index"
  value       = aws_kendra_index.main.arn
}

output "kendra_index_name" {
  description = "Name of the Kendra index"
  value       = aws_kendra_index.main.name
}

output "kendra_data_source_id" {
  description = "ID of the Kendra S3 data source"
  value       = aws_kendra_data_source.s3_documents.id
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the QA processor Lambda function"
  value       = aws_lambda_function.qa_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the QA processor Lambda function"
  value       = aws_lambda_function.qa_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the QA processor Lambda function"
  value       = aws_lambda_function.qa_processor.invoke_arn
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the QA processor Lambda function"
  value       = aws_lambda_function.qa_processor.qualified_arn
}

# API Gateway Outputs (conditional)
output "api_gateway_rest_api_id" {
  description = "ID of the API Gateway REST API"
  value       = var.enable_api_gateway ? aws_api_gateway_rest_api.qa_api[0].id : null
}

output "api_gateway_rest_api_arn" {
  description = "ARN of the API Gateway REST API"
  value       = var.enable_api_gateway ? aws_api_gateway_rest_api.qa_api[0].arn : null
}

output "api_gateway_invoke_url" {
  description = "URL to invoke the API Gateway"
  value       = var.enable_api_gateway ? aws_api_gateway_deployment.qa_deployment[0].invoke_url : null
}

output "api_gateway_endpoint_url" {
  description = "Full endpoint URL for the QA API"
  value       = var.enable_api_gateway ? "${aws_api_gateway_deployment.qa_deployment[0].invoke_url}/ask" : null
}

output "api_gateway_api_key" {
  description = "API key for accessing the QA API (sensitive)"
  value       = var.enable_api_gateway && var.enable_api_key ? aws_api_gateway_api_key.qa_api_key[0].value : null
  sensitive   = true
}

output "api_gateway_api_key_id" {
  description = "ID of the API Gateway API key"
  value       = var.enable_api_gateway && var.enable_api_key ? aws_api_gateway_api_key.qa_api_key[0].id : null
}

# IAM Role Outputs
output "kendra_service_role_arn" {
  description = "ARN of the Kendra service role"
  value       = aws_iam_role.kendra_service_role.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# CloudWatch Log Groups
output "lambda_log_group_name" {
  description = "Name of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "kendra_log_group_name" {
  description = "Name of the Kendra CloudWatch log group"
  value       = aws_cloudwatch_log_group.kendra_logs.name
}

output "api_gateway_log_group_name" {
  description = "Name of the API Gateway CloudWatch log group"
  value       = var.enable_api_gateway ? aws_cloudwatch_log_group.api_gateway_logs[0].name : null
}

# Configuration Information
output "bedrock_model_id" {
  description = "Bedrock model ID used for text generation"
  value       = var.bedrock_model_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Resource Naming Information
output "resource_prefix" {
  description = "Common prefix used for resource naming"
  value       = local.resource_prefix
}

output "unique_suffix" {
  description = "Unique suffix used for resource naming"
  value       = local.unique_suffix
}

# Quick Start Information
output "quick_start_instructions" {
  description = "Quick start instructions for using the QA system"
  value = <<-EOT
    # Quick Start Instructions for Intelligent Document QA System
    
    ## 1. Upload Documents to S3
    aws s3 cp your-document.pdf s3://${aws_s3_bucket.documents.bucket}/documents/
    
    ## 2. Sync Kendra Data Source
    aws kendra start-data-source-sync-job \
      --index-id ${aws_kendra_index.main.id} \
      --id ${aws_kendra_data_source.s3_documents.id}
    
    ## 3. Test the Lambda Function
    aws lambda invoke \
      --function-name ${aws_lambda_function.qa_processor.function_name} \
      --payload '{"question": "Your question here?"}' \
      response.json && cat response.json
    
    %{if var.enable_api_gateway}## 4. Use the API Gateway Endpoint
    curl -X POST "${aws_api_gateway_deployment.qa_deployment[0].invoke_url}/ask" \
      %{if var.enable_api_key}-H "x-api-key: YOUR_API_KEY" \%{endif}
      -H "Content-Type: application/json" \
      -d '{"question": "Your question here?"}'%{endif}
    
    ## Monitoring
    - Lambda Logs: ${aws_cloudwatch_log_group.lambda_logs.name}
    - Kendra Logs: ${aws_cloudwatch_log_group.kendra_logs.name}
    %{if var.enable_api_gateway}- API Gateway Logs: ${aws_cloudwatch_log_group.api_gateway_logs[0].name}%{endif}
  EOT
}

# Cost Estimation Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources"
  value = <<-EOT
    # Estimated Monthly Costs (USD)
    
    ## Kendra Index
    - Developer Edition: ~$810/month for up to 10,000 documents
    - Enterprise Edition: ~$1,008/month + per-query costs
    
    ## Lambda Function
    - Execution: ~$0.01-$1.00/month (depending on usage)
    - Storage: ~$0.01/month
    
    ## S3 Storage
    - Standard Storage: ~$0.023/GB/month
    - Requests: Variable based on upload/access patterns
    
    %{if var.enable_api_gateway}## API Gateway
    - REST API: ~$3.50 per million requests
    - Data Transfer: ~$0.09/GB for first 10TB%{endif}
    
    ## CloudWatch Logs
    - Log Storage: ~$0.50/GB/month
    - Log Ingestion: ~$0.50/GB
    
    Note: Costs vary significantly based on usage patterns.
    Monitor your AWS billing dashboard for actual costs.
  EOT
}