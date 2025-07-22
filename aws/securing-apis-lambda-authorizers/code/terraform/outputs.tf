output "api_gateway_url" {
  description = "Base URL for the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.secure_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}"
}

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = aws_api_gateway_rest_api.secure_api.id
}

output "api_endpoints" {
  description = "Available API endpoints with their authorization requirements"
  value = {
    public_endpoint = {
      url            = "${aws_api_gateway_rest_api.secure_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/public"
      method         = "GET"
      authorization  = "None"
      description    = "Public endpoint accessible without authentication"
    }
    protected_endpoint = {
      url            = "${aws_api_gateway_rest_api.secure_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/protected"
      method         = "GET"
      authorization  = "Bearer Token"
      description    = "Protected endpoint requiring valid bearer token"
      test_tokens    = "admin-token, user-token"
    }
    admin_endpoint = {
      url            = "${aws_api_gateway_rest_api.secure_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/protected/admin"
      method         = "GET"
      authorization  = "API Key or Custom Header"
      description    = "Admin endpoint with request-based authorization"
      auth_methods   = "api_key parameter or X-Custom-Auth header"
    }
  }
}

output "lambda_functions" {
  description = "Information about the deployed Lambda functions"
  value = {
    token_authorizer = {
      function_name = aws_lambda_function.token_authorizer.function_name
      function_arn  = aws_lambda_function.token_authorizer.arn
      description   = "Token-based authorizer function"
    }
    request_authorizer = {
      function_name = aws_lambda_function.request_authorizer.function_name
      function_arn  = aws_lambda_function.request_authorizer.arn
      description   = "Request-based authorizer function"
    }
    protected_api = {
      function_name = aws_lambda_function.protected_api.function_name
      function_arn  = aws_lambda_function.protected_api.arn
      description   = "Protected business logic function"
    }
    public_api = {
      function_name = aws_lambda_function.public_api.function_name
      function_arn  = aws_lambda_function.public_api.arn
      description   = "Public business logic function"
    }
  }
}

output "authorizers" {
  description = "Information about the API Gateway authorizers"
  value = {
    token_authorizer = {
      id                    = aws_api_gateway_authorizer.token_authorizer.id
      name                  = aws_api_gateway_authorizer.token_authorizer.name
      type                  = aws_api_gateway_authorizer.token_authorizer.type
      identity_source       = aws_api_gateway_authorizer.token_authorizer.identity_source
      cache_ttl_seconds     = aws_api_gateway_authorizer.token_authorizer.authorizer_result_ttl_in_seconds
      description           = "Validates Bearer tokens in Authorization header"
    }
    request_authorizer = {
      id                    = aws_api_gateway_authorizer.request_authorizer.id
      name                  = aws_api_gateway_authorizer.request_authorizer.name
      type                  = aws_api_gateway_authorizer.request_authorizer.type
      identity_source       = aws_api_gateway_authorizer.request_authorizer.identity_source
      cache_ttl_seconds     = aws_api_gateway_authorizer.request_authorizer.authorizer_result_ttl_in_seconds
      description           = "Validates custom headers and query parameters"
    }
  }
}

output "test_commands" {
  description = "Sample curl commands for testing the API endpoints"
  value = {
    public_test = "curl -s 'https://${aws_api_gateway_rest_api.secure_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/public'"
    
    protected_user_test = "curl -s -H 'Authorization: Bearer user-token' 'https://${aws_api_gateway_rest_api.secure_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/protected'"
    
    protected_admin_test = "curl -s -H 'Authorization: Bearer admin-token' 'https://${aws_api_gateway_rest_api.secure_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/protected'"
    
    admin_api_key_test = "curl -s 'https://${aws_api_gateway_rest_api.secure_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/protected/admin?api_key=secret-api-key-123'"
    
    admin_header_test = "curl -s -H 'X-Custom-Auth: custom-auth-value' 'https://${aws_api_gateway_rest_api.secure_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/protected/admin'"
    
    unauthorized_test = "curl -s 'https://${aws_api_gateway_rest_api.secure_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/protected'"
  }
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for monitoring and debugging"
  value = {
    token_authorizer_logs = aws_cloudwatch_log_group.token_authorizer_logs.name
    request_authorizer_logs = aws_cloudwatch_log_group.request_authorizer_logs.name
    protected_function_logs = aws_cloudwatch_log_group.protected_function_logs.name
    public_function_logs = aws_cloudwatch_log_group.public_function_logs.name
    api_gateway_logs = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.api_gateway_logs[0].name : "Disabled"
  }
}

output "iam_roles" {
  description = "IAM roles created for the serverless API"
  value = {
    lambda_execution_role = {
      name = aws_iam_role.lambda_execution_role.name
      arn  = aws_iam_role.lambda_execution_role.arn
    }
    api_gateway_authorizer_role = {
      name = aws_iam_role.api_gateway_authorizer_role.name
      arn  = aws_iam_role.api_gateway_authorizer_role.arn
    }
  }
}

output "security_configuration" {
  description = "Security configuration details"
  value = {
    authorizer_cache_ttl_seconds = var.authorizer_cache_ttl
    lambda_timeout_seconds       = var.lambda_timeout
    cloudwatch_logging_enabled   = var.enable_cloudwatch_logs
    log_retention_days          = var.log_retention_days
    
    authentication_methods = [
      "Bearer Token (Authorization header)",
      "API Key (query parameter)",
      "Custom Header (X-Custom-Auth)",
      "IP-based validation (for internal networks)"
    ]
    
    authorization_patterns = [
      "TOKEN: Validates bearer tokens with caching",
      "REQUEST: Analyzes full request context for authorization decisions"
    ]
  }
}

output "cost_estimate" {
  description = "Estimated monthly costs for low-traffic usage"
  value = {
    description = "Estimated costs for 10,000 API requests per month"
    components = {
      api_gateway_requests = "$0.035 (10,000 requests × $3.50 per million)"
      lambda_invocations   = "$0.002 (10,000 invocations × $0.20 per million)"
      lambda_compute_time  = "$0.001 (assuming 100ms average duration)"
      cloudwatch_logs      = "$0.50 (log ingestion and storage)"
      total_estimated      = "~$0.54 per month"
    }
    note = "Actual costs may vary based on usage patterns, request complexity, and AWS region"
  }
}