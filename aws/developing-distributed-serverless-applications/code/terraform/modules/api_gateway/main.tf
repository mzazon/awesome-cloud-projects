# API Gateway Module for Multi-Region Aurora DSQL Application
# This module creates API Gateway resources, methods, and deployments

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# =============================================================================
# API GATEWAY RESOURCES
# =============================================================================

# Get the root resource of the API Gateway
data "aws_api_gateway_resource" "root" {
  rest_api_id = var.api_id
  path        = "/"
}

# Create /health resource
resource "aws_api_gateway_resource" "health" {
  rest_api_id = var.api_id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "health"
}

# Create /users resource
resource "aws_api_gateway_resource" "users" {
  rest_api_id = var.api_id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "users"
}

# =============================================================================
# API GATEWAY METHODS - HEALTH ENDPOINT
# =============================================================================

# GET method for /health
resource "aws_api_gateway_method" "health_get" {
  rest_api_id   = var.api_id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "GET"
  authorization = "NONE"
  api_key_required = var.api_key_required
}

# Integration for GET /health
resource "aws_api_gateway_integration" "health_get" {
  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.health_get.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${var.lambda_arn}/invocations"
}

# OPTIONS method for CORS - /health
resource "aws_api_gateway_method" "health_options" {
  rest_api_id   = var.api_id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# Integration for OPTIONS /health (CORS)
resource "aws_api_gateway_integration" "health_options" {
  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.health_options.http_method
  
  type = "MOCK"
  
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# Method response for OPTIONS /health
resource "aws_api_gateway_method_response" "health_options" {
  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.health_options.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# Integration response for OPTIONS /health
resource "aws_api_gateway_integration_response" "health_options" {
  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.health_options.http_method
  status_code = aws_api_gateway_method_response.health_options.status_code
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'${join(",", var.cors_headers)}'"
    "method.response.header.Access-Control-Allow-Methods" = "'${join(",", var.cors_methods)}'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${join(",", var.cors_origins)}'"
  }
}

# =============================================================================
# API GATEWAY METHODS - USERS ENDPOINT
# =============================================================================

# GET method for /users
resource "aws_api_gateway_method" "users_get" {
  rest_api_id   = var.api_id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "GET"
  authorization = "NONE"
  api_key_required = var.api_key_required
}

# Integration for GET /users
resource "aws_api_gateway_integration" "users_get" {
  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.users_get.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${var.lambda_arn}/invocations"
}

# POST method for /users
resource "aws_api_gateway_method" "users_post" {
  rest_api_id   = var.api_id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = var.api_key_required
}

# Integration for POST /users
resource "aws_api_gateway_integration" "users_post" {
  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.users_post.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${var.lambda_arn}/invocations"
}

# OPTIONS method for CORS - /users
resource "aws_api_gateway_method" "users_options" {
  rest_api_id   = var.api_id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# Integration for OPTIONS /users (CORS)
resource "aws_api_gateway_integration" "users_options" {
  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.users_options.http_method
  
  type = "MOCK"
  
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# Method response for OPTIONS /users
resource "aws_api_gateway_method_response" "users_options" {
  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.users_options.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# Integration response for OPTIONS /users
resource "aws_api_gateway_integration_response" "users_options" {
  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.users_options.http_method
  status_code = aws_api_gateway_method_response.users_options.status_code
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'${join(",", var.cors_headers)}'"
    "method.response.header.Access-Control-Allow-Methods" = "'${join(",", var.cors_methods)}'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${join(",", var.cors_origins)}'"
  }
}

# =============================================================================
# API GATEWAY DEPLOYMENT
# =============================================================================

# CloudWatch log group for API Gateway (if logging enabled)
resource "aws_cloudwatch_log_group" "api_gateway" {
  count = var.enable_logging ? 1 : 0
  
  name              = "/aws/apigateway/${var.api_id}"
  retention_in_days = 7
  
  tags = var.tags
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = var.api_id
  stage_name  = var.stage_name
  
  # Force redeployment when configuration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.health.id,
      aws_api_gateway_resource.users.id,
      aws_api_gateway_method.health_get.id,
      aws_api_gateway_method.users_get.id,
      aws_api_gateway_method.users_post.id,
      aws_api_gateway_integration.health_get.id,
      aws_api_gateway_integration.users_get.id,
      aws_api_gateway_integration.users_post.id,
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
  
  depends_on = [
    aws_api_gateway_method.health_get,
    aws_api_gateway_method.users_get,
    aws_api_gateway_method.users_post,
    aws_api_gateway_integration.health_get,
    aws_api_gateway_integration.users_get,
    aws_api_gateway_integration.users_post,
  ]
}

# API Gateway stage configuration
resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = var.api_id
  stage_name    = var.stage_name
  
  # Enable logging if requested
  dynamic "access_log_settings" {
    for_each = var.enable_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway[0].arn
      format = jsonencode({
        requestId      = "$context.requestId"
        extendedRequestId = "$context.extendedRequestId"
        ip             = "$context.identity.sourceIp"
        caller         = "$context.identity.caller"
        user           = "$context.identity.user"
        requestTime    = "$context.requestTime"
        httpMethod     = "$context.httpMethod"
        resourcePath   = "$context.resourcePath"
        status         = "$context.status"
        protocol       = "$context.protocol"
        responseLength = "$context.responseLength"
        responseTime   = "$context.responseTime"
        error          = "$context.error.message"
        integrationError = "$context.integration.error"
      })
    }
  }
  
  # X-Ray tracing
  xray_tracing_enabled = true
  
  tags = var.tags
}

# API Gateway method settings
resource "aws_api_gateway_method_settings" "main" {
  rest_api_id = var.api_id
  stage_name  = aws_api_gateway_stage.main.stage_name
  method_path = "*/*"
  
  settings {
    metrics_enabled        = true
    logging_level         = var.enable_logging ? "INFO" : "OFF"
    data_trace_enabled    = var.enable_logging
    throttling_rate_limit = var.throttle_rate_limit
    throttling_burst_limit = var.throttle_burst_limit
  }
}