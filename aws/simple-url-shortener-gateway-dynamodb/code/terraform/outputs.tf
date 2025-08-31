# Output values for the URL Shortener infrastructure
# These outputs provide important information for using and integrating with the deployed resources

output "api_gateway_url" {
  description = "Base URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.url_shortener_api.id}.execute-api.${local.region}.amazonaws.com/${var.api_gateway_stage_name}"
}

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.url_shortener_api.id
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.url_shortener_api.arn
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.url_shortener_api.execution_arn
}

output "create_short_url_endpoint" {
  description = "Full URL endpoint for creating short URLs"
  value       = "https://${aws_api_gateway_rest_api.url_shortener_api.id}.execute-api.${local.region}.amazonaws.com/${var.api_gateway_stage_name}/shorten"
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing URL mappings"
  value       = aws_dynamodb_table.url_mappings.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.url_mappings.arn
}

output "lambda_create_function_name" {
  description = "Name of the Lambda function for creating short URLs"
  value       = aws_lambda_function.create_function.function_name
}

output "lambda_create_function_arn" {
  description = "ARN of the Lambda function for creating short URLs"
  value       = aws_lambda_function.create_function.arn
}

output "lambda_redirect_function_name" {
  description = "Name of the Lambda function for URL redirection"
  value       = aws_lambda_function.redirect_function.function_name
}

output "lambda_redirect_function_arn" {
  description = "ARN of the Lambda function for URL redirection"
  value       = aws_lambda_function.redirect_function.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "cloudwatch_log_group_create_function" {
  description = "CloudWatch Log Group name for the create function"
  value       = aws_cloudwatch_log_group.create_function_logs.name
}

output "cloudwatch_log_group_redirect_function" {
  description = "CloudWatch Log Group name for the redirect function"
  value       = aws_cloudwatch_log_group.redirect_function_logs.name
}

output "cloudwatch_log_group_api_gateway" {
  description = "CloudWatch Log Group name for API Gateway access logs (if enabled)"
  value       = var.enable_api_access_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].name : null
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "project_name" {
  description = "Project name used in resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = local.region
}

output "usage_instructions" {
  description = "Instructions for using the URL shortener service"
  value = <<-EOT
    URL Shortener Service Deployed Successfully!
    
    To create a short URL, make a POST request to:
    ${aws_api_gateway_rest_api.url_shortener_api.id}.execute-api.${local.region}.amazonaws.com/${var.api_gateway_stage_name}/shorten
    
    Example using curl:
    curl -X POST https://${aws_api_gateway_rest_api.url_shortener_api.id}.execute-api.${local.region}.amazonaws.com/${var.api_gateway_stage_name}/shorten \
      -H "Content-Type: application/json" \
      -d '{"url": "https://example.com/very-long-url"}'
    
    Response will include:
    - shortCode: The generated short code
    - shortUrl: The full short URL for sharing
    - originalUrl: The original URL that was shortened
    
    To use a short URL, simply access:
    https://${aws_api_gateway_rest_api.url_shortener_api.id}.execute-api.${local.region}.amazonaws.com/${var.api_gateway_stage_name}/{shortCode}
    
    The service will automatically redirect to the original URL.
  EOT
}

output "monitoring_dashboard_url" {
  description = "URL to CloudWatch dashboard for monitoring (construct manually)"
  value       = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards:"
}

output "cost_optimization_notes" {
  description = "Notes about cost optimization for this deployment"
  value = <<-EOT
    Cost Optimization Notes:
    
    1. DynamoDB: Using ${var.dynamodb_billing_mode} billing mode
    2. Lambda: Functions scale automatically from 0 to handle traffic
    3. API Gateway: Pay-per-request pricing with throttling configured
    4. CloudWatch Logs: Retention set to ${var.log_retention_in_days} days to manage costs
    
    Estimated monthly cost for 1000 URL creations and 10,000 redirects:
    - DynamoDB: ~$0.25 (PAY_PER_REQUEST)
    - Lambda: ~$0.02 (free tier eligible)
    - API Gateway: ~$3.50
    - CloudWatch Logs: ~$0.50
    Total: ~$4.27/month
  EOT
}

output "security_considerations" {
  description = "Important security considerations for this deployment"
  value = <<-EOT
    Security Considerations:
    
    1. API Gateway has no authentication - consider adding API keys for production
    2. Lambda functions use least-privilege IAM roles
    3. DynamoDB uses server-side encryption with AWS managed keys
    4. CORS is enabled for web browser access
    5. CloudWatch logging is enabled for audit trails
    
    For production use, consider adding:
    - API Gateway authentication (API keys, Cognito, etc.)
    - Custom domain with SSL certificate
    - WAF for additional protection
    - Enhanced monitoring and alerting
  EOT
}