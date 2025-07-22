# API Gateway Outputs
output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.petstore_api.id
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.petstore_api.arn
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.petstore_api.execution_arn
}

output "api_gateway_created_date" {
  description = "Creation date of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.petstore_api.created_date
}

# API Stages
output "api_stage_dev_invoke_url" {
  description = "Invoke URL for the development stage"
  value       = aws_api_gateway_stage.dev.invoke_url
}

output "api_stage_prod_invoke_url" {
  description = "Invoke URL for the production stage"
  value       = aws_api_gateway_stage.prod.invoke_url
}

# Custom Domain
output "custom_domain_name" {
  description = "Custom domain name for the API"
  value       = aws_api_gateway_domain_name.api_domain.domain_name
}

output "custom_domain_regional_domain_name" {
  description = "Regional domain name for the custom domain"
  value       = aws_api_gateway_domain_name.api_domain.regional_domain_name
}

output "custom_domain_regional_zone_id" {
  description = "Regional zone ID for the custom domain"
  value       = aws_api_gateway_domain_name.api_domain.regional_zone_id
}

output "custom_domain_cloudfront_domain_name" {
  description = "CloudFront domain name for edge-optimized endpoint"
  value       = aws_api_gateway_domain_name.api_domain.cloudfront_domain_name
}

output "custom_domain_cloudfront_zone_id" {
  description = "CloudFront zone ID for edge-optimized endpoint"
  value       = aws_api_gateway_domain_name.api_domain.cloudfront_zone_id
}

# API Endpoints
output "api_endpoints" {
  description = "Available API endpoints"
  value = {
    production_root     = "https://${aws_api_gateway_domain_name.api_domain.domain_name}/pets"
    production_v1       = "https://${aws_api_gateway_domain_name.api_domain.domain_name}/v1/pets"
    development         = "https://${aws_api_gateway_domain_name.api_domain.domain_name}/v1-dev/pets"
    default_dev_url     = aws_api_gateway_stage.dev.invoke_url
    default_prod_url    = aws_api_gateway_stage.prod.invoke_url
  }
}

# SSL Certificate
output "acm_certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = aws_acm_certificate.api_cert.arn
}

output "acm_certificate_status" {
  description = "Status of the ACM certificate"
  value       = aws_acm_certificate.api_cert.status
}

output "acm_certificate_domain_validation_options" {
  description = "Domain validation options for the ACM certificate"
  value       = aws_acm_certificate.api_cert.domain_validation_options
  sensitive   = false
}

# Lambda Functions
output "lambda_function_name" {
  description = "Name of the main Lambda function"
  value       = aws_lambda_function.petstore_handler.function_name
}

output "lambda_function_arn" {
  description = "ARN of the main Lambda function"
  value       = aws_lambda_function.petstore_handler.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the main Lambda function"
  value       = aws_lambda_function.petstore_handler.invoke_arn
}

output "authorizer_function_name" {
  description = "Name of the custom authorizer Lambda function"
  value       = aws_lambda_function.petstore_authorizer.function_name
}

output "authorizer_function_arn" {
  description = "ARN of the custom authorizer Lambda function"
  value       = aws_lambda_function.petstore_authorizer.arn
}

output "custom_authorizer_id" {
  description = "ID of the custom authorizer"
  value       = aws_api_gateway_authorizer.petstore_authorizer.id
}

# IAM Roles
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# CloudWatch Log Groups
output "lambda_log_group_name" {
  description = "Name of the Lambda function CloudWatch log group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

output "authorizer_log_group_name" {
  description = "Name of the authorizer function CloudWatch log group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.authorizer_logs[0].name : null
}

output "api_gateway_log_group_name" {
  description = "Name of the API Gateway CloudWatch log group"
  value       = var.enable_api_gateway_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].name : null
}

# DNS Information
output "dns_validation_record" {
  description = "DNS validation record for certificate verification"
  value = var.certificate_validation_method == "DNS" ? {
    name  = tolist(aws_acm_certificate.api_cert.domain_validation_options)[0].resource_record_name
    type  = tolist(aws_acm_certificate.api_cert.domain_validation_options)[0].resource_record_type
    value = tolist(aws_acm_certificate.api_cert.domain_validation_options)[0].resource_record_value
  } : null
}

output "route53_record_created" {
  description = "Whether Route 53 DNS record was created"
  value       = var.route53_hosted_zone_id != "" ? true : false
}

# Security Information
output "api_throttling_settings" {
  description = "API throttling configuration"
  value = {
    prod_rate_limit   = var.api_throttle_rate_limit
    prod_burst_limit  = var.api_throttle_burst_limit
    dev_rate_limit    = var.dev_throttle_rate_limit
    dev_burst_limit   = var.dev_throttle_burst_limit
  }
}

# Resource Identifiers
output "resource_identifiers" {
  description = "Important resource identifiers for reference"
  value = {
    api_gateway_id              = aws_api_gateway_rest_api.petstore_api.id
    pets_resource_id           = aws_api_gateway_resource.pets.id
    lambda_function_name       = aws_lambda_function.petstore_handler.function_name
    authorizer_function_name   = aws_lambda_function.petstore_authorizer.function_name
    custom_domain_name         = aws_api_gateway_domain_name.api_domain.domain_name
    certificate_arn            = aws_acm_certificate.api_cert.arn
    execution_role_arn         = aws_iam_role.lambda_execution_role.arn
  }
}

# Testing Information
output "testing_information" {
  description = "Information for testing the API"
  value = {
    unauthorized_test = "curl -v https://${aws_api_gateway_domain_name.api_domain.domain_name}/pets"
    authorized_test   = "curl -v -H 'Authorization: Bearer valid-token' https://${aws_api_gateway_domain_name.api_domain.domain_name}/pets"
    post_test         = "curl -v -X POST -H 'Authorization: Bearer valid-token' -H 'Content-Type: application/json' -d '{\"name\":\"Fluffy\",\"type\":\"cat\"}' https://${aws_api_gateway_domain_name.api_domain.domain_name}/pets"
    dev_test          = "curl -v -H 'Authorization: Bearer valid-token' https://${aws_api_gateway_domain_name.api_domain.domain_name}/v1-dev/pets"
  }
}