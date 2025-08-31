# Main Terraform configuration for URL Shortener service
# This creates a serverless URL shortener using API Gateway, Lambda, and DynamoDB

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming and configuration
locals {
  resource_suffix = random_string.suffix.result
  region          = var.aws_region != null ? var.aws_region : data.aws_region.current.name
  account_id      = data.aws_caller_identity.current.account_id

  # Resource names with consistent naming convention
  table_name                = "${var.project_name}-${var.environment}-${local.resource_suffix}"
  lambda_role_name          = "${var.project_name}-lambda-role-${var.environment}-${local.resource_suffix}"
  create_function_name      = "${var.project_name}-create-${var.environment}-${local.resource_suffix}"
  redirect_function_name    = "${var.project_name}-redirect-${var.environment}-${local.resource_suffix}"
  api_name                  = "${var.project_name}-api-${var.environment}-${local.resource_suffix}"

  # Common tags applied to all resources
  common_tags = merge({
    Environment = var.environment
    Component   = "URLShortener"
    CreatedBy   = "Terraform"
  }, var.additional_tags)
}

# DynamoDB table for storing URL mappings
# Uses on-demand billing for cost optimization and automatic scaling
resource "aws_dynamodb_table" "url_mappings" {
  name         = local.table_name
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "shortCode"

  # Only set capacity if using provisioned billing
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "shortCode"
    type = "S" # String type
  }

  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption using AWS managed keys
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name        = local.table_name
    Description = "Stores URL shortener mappings"
  })
}

# IAM role for Lambda functions
# Provides necessary permissions for DynamoDB access and CloudWatch logging
resource "aws_iam_role" "lambda_execution_role" {
  name = local.lambda_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = local.lambda_role_name
    Description = "Execution role for URL shortener Lambda functions"
  })
}

# Attach basic Lambda execution policy for CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for DynamoDB access
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${local.lambda_role_name}-dynamodb-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.url_mappings.arn
      }
    ]
  })
}

# Optional X-Ray tracing policy
resource "aws_iam_role_policy_attachment" "lambda_xray_policy" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "create_function_logs" {
  name              = "/aws/lambda/${local.create_function_name}"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.common_tags, {
    Name        = "${local.create_function_name}-logs"
    Description = "Logs for URL creation Lambda function"
  })
}

resource "aws_cloudwatch_log_group" "redirect_function_logs" {
  name              = "/aws/lambda/${local.redirect_function_name}"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.common_tags, {
    Name        = "${local.redirect_function_name}-logs"
    Description = "Logs for URL redirect Lambda function"
  })
}

# Archive Lambda function code for deployment
data "archive_file" "create_function_zip" {
  type        = "zip"
  output_path = "${path.module}/create-function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/create_function.py", {
      short_code_length = var.short_code_length
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "redirect_function_zip" {
  type        = "zip"
  output_path = "${path.module}/redirect-function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/redirect_function.py", {
      short_code_length = var.short_code_length
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for creating short URLs
resource "aws_lambda_function" "create_function" {
  filename         = data.archive_file.create_function_zip.output_path
  function_name    = local.create_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.create_function_zip.output_base64sha256
  runtime         = "python3.12"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      TABLE_NAME        = aws_dynamodb_table.url_mappings.name
      SHORT_CODE_LENGTH = var.short_code_length
    }
  }

  # Optional X-Ray tracing
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_dynamodb_policy,
    aws_cloudwatch_log_group.create_function_logs
  ]

  tags = merge(local.common_tags, {
    Name        = local.create_function_name
    Description = "Creates short URLs and stores mappings"
  })
}

# Lambda function for URL redirection
resource "aws_lambda_function" "redirect_function" {
  filename         = data.archive_file.redirect_function_zip.output_path
  function_name    = local.redirect_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.redirect_function_zip.output_base64sha256
  runtime         = "python3.12"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      TABLE_NAME        = aws_dynamodb_table.url_mappings.name
      SHORT_CODE_LENGTH = var.short_code_length
    }
  }

  # Optional X-Ray tracing
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_dynamodb_policy,
    aws_cloudwatch_log_group.redirect_function_logs
  ]

  tags = merge(local.common_tags, {
    Name        = local.redirect_function_name
    Description = "Handles URL redirection from short codes"
  })
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "url_shortener_api" {
  name        = local.api_name
  description = "Serverless URL Shortener API"

  endpoint_configuration {
    types = ["EDGE"] # Use edge-optimized for global distribution
  }

  tags = merge(local.common_tags, {
    Name        = local.api_name
    Description = "REST API for URL shortener service"
  })
}

# API Gateway Resources
resource "aws_api_gateway_resource" "shorten_resource" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener_api.id
  parent_id   = aws_api_gateway_rest_api.url_shortener_api.root_resource_id
  path_part   = "shorten"
}

resource "aws_api_gateway_resource" "shortcode_resource" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener_api.id
  parent_id   = aws_api_gateway_rest_api.url_shortener_api.root_resource_id
  path_part   = "{shortCode}"
}

# API Gateway Methods
resource "aws_api_gateway_method" "shorten_post" {
  rest_api_id   = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id   = aws_api_gateway_resource.shorten_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "shorten_options" {
  rest_api_id   = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id   = aws_api_gateway_resource.shorten_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "shortcode_get" {
  rest_api_id   = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id   = aws_api_gateway_resource.shortcode_resource.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.shortCode" = true
  }
}

# API Gateway Integrations
resource "aws_api_gateway_integration" "shorten_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id = aws_api_gateway_resource.shorten_resource.id
  http_method = aws_api_gateway_method.shorten_post.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.create_function.invoke_arn
}

resource "aws_api_gateway_integration" "shorten_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id = aws_api_gateway_resource.shorten_resource.id
  http_method = aws_api_gateway_method.shorten_options.http_method

  type                 = "MOCK"
  passthrough_behavior = "WHEN_NO_MATCH"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_integration" "shortcode_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id = aws_api_gateway_resource.shortcode_resource.id
  http_method = aws_api_gateway_method.shortcode_get.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.redirect_function.invoke_arn
}

# CORS Configuration for OPTIONS method
resource "aws_api_gateway_method_response" "shorten_options_response" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id = aws_api_gateway_resource.shorten_resource.id
  http_method = aws_api_gateway_method.shorten_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "shorten_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener_api.id
  resource_id = aws_api_gateway_resource.shorten_resource.id
  http_method = aws_api_gateway_method.shorten_options.http_method
  status_code = aws_api_gateway_method_response.shorten_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.shorten_options_integration]
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke_create" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.url_shortener_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_invoke_redirect" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.redirect_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.url_shortener_api.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "url_shortener_deployment" {
  depends_on = [
    aws_api_gateway_integration.shorten_post_integration,
    aws_api_gateway_integration.shorten_options_integration,
    aws_api_gateway_integration.shortcode_get_integration,
    aws_api_gateway_integration_response.shorten_options_integration_response
  ]

  rest_api_id = aws_api_gateway_rest_api.url_shortener_api.id

  triggers = {
    # Redeploy when any integration changes
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.shorten_resource.id,
      aws_api_gateway_resource.shortcode_resource.id,
      aws_api_gateway_method.shorten_post.id,
      aws_api_gateway_method.shorten_options.id,
      aws_api_gateway_method.shortcode_get.id,
      aws_api_gateway_integration.shorten_post_integration.id,
      aws_api_gateway_integration.shorten_options_integration.id,
      aws_api_gateway_integration.shortcode_get_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "url_shortener_stage" {
  deployment_id = aws_api_gateway_deployment.url_shortener_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.url_shortener_api.id
  stage_name    = var.api_gateway_stage_name

  # Throttling configuration
  throttle_settings {
    burst_limit = var.api_throttle_burst_limit
    rate_limit  = var.api_throttle_rate_limit
  }

  # Optional access logging
  dynamic "access_log_settings" {
    for_each = var.enable_api_access_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway_logs[0].arn
      format = jsonencode({
        requestId      = "$context.requestId"
        ip            = "$context.identity.sourceIp"
        caller        = "$context.identity.caller"
        user          = "$context.identity.user"
        requestTime   = "$context.requestTime"
        httpMethod    = "$context.httpMethod"
        resourcePath  = "$context.resourcePath"
        status        = "$context.status"
        protocol      = "$context.protocol"
        responseLength = "$context.responseLength"
      })
    }
  }

  # X-Ray tracing
  xray_tracing_enabled = var.enable_xray_tracing

  tags = merge(local.common_tags, {
    Name        = "${local.api_name}-${var.api_gateway_stage_name}"
    Description = "API Gateway stage for URL shortener"
  })
}

# CloudWatch Log Group for API Gateway access logs
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_api_access_logging ? 1 : 0
  name              = "/aws/apigateway/${local.api_name}"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.common_tags, {
    Name        = "${local.api_name}-access-logs"
    Description = "Access logs for URL shortener API Gateway"
  })
}