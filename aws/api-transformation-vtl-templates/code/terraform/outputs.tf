# Output values for the request/response transformation infrastructure

# ===== API GATEWAY OUTPUTS =====

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.transformation_api.id
}

output "api_gateway_name" {
  description = "Name of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.transformation_api.name
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.transformation_api.arn
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.transformation_api.execution_arn
}

output "api_gateway_url" {
  description = "Base URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.transformation_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}"
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.transformation_api.stage_name
}

output "api_gateway_deployment_id" {
  description = "ID of the API Gateway deployment"
  value       = aws_api_gateway_deployment.transformation_api.id
}

# ===== API ENDPOINTS =====

output "users_endpoint" {
  description = "Full URL for the users endpoint"
  value       = "https://${aws_api_gateway_rest_api.transformation_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/users"
}

output "post_users_endpoint" {
  description = "POST endpoint for creating users"
  value       = "https://${aws_api_gateway_rest_api.transformation_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/users"
}

output "get_users_endpoint" {
  description = "GET endpoint for retrieving users with query parameters"
  value       = "https://${aws_api_gateway_rest_api.transformation_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/users?limit=10&offset=0&filter=email:example.com&sort=-createdAt"
}

# ===== LAMBDA OUTPUTS =====

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.data_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.data_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.data_processor.invoke_arn
}

output "lambda_function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.data_processor.version
}

output "lambda_function_runtime" {
  description = "Runtime of the Lambda function"
  value       = aws_lambda_function.data_processor.runtime
}

output "lambda_function_memory_size" {
  description = "Memory size of the Lambda function"
  value       = aws_lambda_function.data_processor.memory_size
}

output "lambda_function_timeout" {
  description = "Timeout of the Lambda function"
  value       = aws_lambda_function.data_processor.timeout
}

# ===== IAM OUTPUTS =====

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# ===== S3 OUTPUTS =====

output "s3_bucket_name" {
  description = "Name of the S3 bucket for API data storage"
  value       = aws_s3_bucket.api_data_store.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for API data storage"
  value       = aws_s3_bucket.api_data_store.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.api_data_store.bucket_domain_name
}

output "s3_bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.api_data_store.region
}

# ===== CLOUDWATCH OUTPUTS =====

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "api_gateway_log_group_name" {
  description = "Name of the CloudWatch log group for API Gateway access logs"
  value       = var.enable_api_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].name : "Not enabled"
}

output "api_gateway_log_group_arn" {
  description = "ARN of the CloudWatch log group for API Gateway access logs"
  value       = var.enable_api_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].arn : "Not enabled"
}

output "api_gateway_execution_log_group_name" {
  description = "Name of the CloudWatch log group for API Gateway execution logs"
  value       = var.enable_api_logging ? aws_cloudwatch_log_group.api_gateway_execution_logs[0].name : "Not enabled"
}

# ===== API GATEWAY MODELS =====

output "user_create_request_model_name" {
  description = "Name of the user creation request model"
  value       = aws_api_gateway_model.user_create_request.name
}

output "user_response_model_name" {
  description = "Name of the user response model"
  value       = aws_api_gateway_model.user_response.name
}

output "error_response_model_name" {
  description = "Name of the error response model"
  value       = aws_api_gateway_model.error_response.name
}

# ===== CONFIGURATION OUTPUTS =====

output "request_validator_id" {
  description = "ID of the request validator"
  value       = var.enable_request_validation ? aws_api_gateway_request_validator.comprehensive_validator[0].id : "Not enabled"
}

output "xray_tracing_enabled" {
  description = "Whether X-Ray tracing is enabled"
  value       = var.enable_xray_tracing
}

output "api_logging_enabled" {
  description = "Whether API Gateway logging is enabled"
  value       = var.enable_api_logging
}

output "detailed_metrics_enabled" {
  description = "Whether detailed CloudWatch metrics are enabled"
  value       = var.enable_detailed_metrics
}

# ===== RESOURCE IDENTIFIERS =====

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "users_resource_id" {
  description = "ID of the /users resource"
  value       = aws_api_gateway_resource.users.id
}

output "users_resource_path" {
  description = "Path of the /users resource"
  value       = aws_api_gateway_resource.users.path
}

# ===== TESTING OUTPUTS =====

output "curl_test_commands" {
  description = "Example curl commands for testing the API"
  value = {
    post_user_valid = "curl -X POST '${aws_api_gateway_rest_api.transformation_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/users' -H 'Content-Type: application/json' -d '{\"firstName\":\"John\",\"lastName\":\"Doe\",\"email\":\"john.doe@example.com\",\"phoneNumber\":\"+1234567890\",\"preferences\":{\"notifications\":true,\"theme\":\"dark\",\"language\":\"en\"},\"metadata\":{\"source\":\"web_app\",\"campaign\":\"spring_2024\"}}'"
    
    post_user_invalid = "curl -X POST '${aws_api_gateway_rest_api.transformation_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/users' -H 'Content-Type: application/json' -d '{\"firstName\":\"Jane\",\"lastName\":\"Smith\",\"email\":\"invalid-email\",\"phoneNumber\":\"+1234567890\"}'"
    
    get_users_with_params = "curl -G '${aws_api_gateway_rest_api.transformation_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/users' -d 'limit=5' -d 'offset=10' -d 'filter=email:example.com' -d 'sort=-createdAt'"
    
    get_users_simple = "curl -X GET '${aws_api_gateway_rest_api.transformation_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/users'"
  }
}

# ===== MONITORING OUTPUTS =====

output "cloudwatch_dashboard_url" {
  description = "URL to CloudWatch dashboard for monitoring"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${local.api_name}-dashboard"
}

output "api_gateway_console_url" {
  description = "URL to API Gateway console for this API"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/apigateway/home?region=${data.aws_region.current.name}#/apis/${aws_api_gateway_rest_api.transformation_api.id}"
}

output "lambda_console_url" {
  description = "URL to Lambda console for this function"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.data_processor.function_name}"
}

# ===== SECURITY OUTPUTS =====

output "cors_configuration" {
  description = "CORS configuration for the API"
  value = {
    allowed_origins = var.cors_allowed_origins
    allowed_methods = var.cors_allowed_methods
    allowed_headers = var.cors_allowed_headers
  }
}

output "throttling_configuration" {
  description = "Throttling configuration for the API"
  value = {
    rate_limit  = var.throttle_rate_limit
    burst_limit = var.throttle_burst_limit
  }
}

# ===== DEPLOYMENT INFORMATION =====

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "deployment_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "deployment_environment" {
  description = "Environment where resources are deployed"
  value       = var.environment
}

output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

# ===== VALIDATION OUTPUTS =====

output "validation_enabled" {
  description = "Whether request validation is enabled"
  value       = var.enable_request_validation
}

output "supported_methods" {
  description = "List of supported HTTP methods"
  value       = ["GET", "POST", "OPTIONS"]
}

output "supported_content_types" {
  description = "List of supported content types"
  value       = ["application/json"]
}

# ===== TRANSFORMATION DETAILS =====

output "transformation_capabilities" {
  description = "Summary of transformation capabilities"
  value = {
    request_transformation  = "VTL templates convert client requests to backend format"
    response_transformation = "VTL templates standardize backend responses to client format"
    query_parameter_transformation = "Query parameters converted to structured backend requests"
    error_handling = "Custom error responses with standardized format"
    validation = "JSON Schema validation for request bodies"
    cors_support = "Full CORS support with configurable origins"
  }
}

output "vtl_features_used" {
  description = "List of VTL features demonstrated in this implementation"
  value = [
    "Field mapping and renaming",
    "Conditional logic (#if, #else, #end)",
    "Utility functions ($util.escapeJavaScript)",
    "Context variables ($context)",
    "Input path functions ($input.path, $input.params)",
    "String manipulation and formatting",
    "JSON parsing and generation",
    "Error handling and validation"
  ]
}