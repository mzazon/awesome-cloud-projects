# Simple Random Data API with Lambda and API Gateway
# This Terraform configuration creates a serverless API that generates random data

# Data source to get current AWS account information
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention with random suffix
  name_prefix = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  
  # Common tags for all resources
  common_tags = merge({
    Name        = local.name_prefix
    Environment = var.environment
    Project     = var.project_name
  }, var.additional_tags)
}

# CloudWatch Log Group for Lambda function logs
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Description = "Log group for ${local.name_prefix} Lambda function"
  })
}

# CloudWatch Log Group for API Gateway access logs (if enabled)
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count = var.enable_api_logging ? 1 : 0
  
  name              = "/aws/apigateway/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Description = "Access log group for ${local.name_prefix} API Gateway"
  })
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role"

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
    Description = "Execution role for ${local.name_prefix} Lambda function"
  })
}

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# Create the Python code for the Lambda function
locals {
  lambda_function_code = <<-EOF
import json
import random
import logging

# Configure logging  
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    AWS Lambda handler for random data API
    Returns random quotes, numbers, or colors based on query parameter
    """
    
    try:
        # Log the incoming request
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Parse query parameters
        query_params = event.get('queryStringParameters') or {}
        data_type = query_params.get('type', 'quote').lower()
        
        # Random data collections
        quotes = [
            "The only way to do great work is to love what you do. - Steve Jobs",
            "Innovation distinguishes between a leader and a follower. - Steve Jobs",
            "Life is what happens to you while you're busy making other plans. - John Lennon",
            "The future belongs to those who believe in the beauty of their dreams. - Eleanor Roosevelt",
            "Success is not final, failure is not fatal: it is the courage to continue that counts. - Winston Churchill"
        ]
        
        colors = [
            {"name": "Ocean Blue", "hex": "#006994", "rgb": "rgb(0, 105, 148)"},
            {"name": "Sunset Orange", "hex": "#FF6B35", "rgb": "rgb(255, 107, 53)"},
            {"name": "Forest Green", "hex": "#2E8B57", "rgb": "rgb(46, 139, 87)"},
            {"name": "Purple Haze", "hex": "#9370DB", "rgb": "rgb(147, 112, 219)"},
            {"name": "Golden Yellow", "hex": "#FFD700", "rgb": "rgb(255, 215, 0)"}
        ]
        
        # Generate response based on type
        if data_type == 'quote':
            data = random.choice(quotes)
        elif data_type == 'number':
            data = random.randint(1, 1000)
        elif data_type == 'color':
            data = random.choice(colors)
        else:
            # Default to quote for unknown types
            data = random.choice(quotes)
            data_type = 'quote'
        
        # Create response
        response_body = {
            'type': data_type,
            'data': data,
            'timestamp': context.aws_request_id,
            'message': f'Random {data_type} generated successfully'
        }
        
        # Return successful response with CORS headers
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps(response_body)
        }
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        
        # Return error response
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': 'Failed to generate random data'
            })
        }
EOF
}

# Create ZIP archive for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/${local.name_prefix}-function.zip"
  
  source {
    content  = local.lambda_function_code
    filename = "lambda_function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "random_data_api" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.name_prefix
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  description = "Random data API generator - generates quotes, numbers, and colors"

  # Ensure the log group is created before the Lambda function
  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  tags = merge(local.common_tags, {
    Description = "Lambda function for ${local.name_prefix} random data API"
  })
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "random_data_api" {
  name        = local.name_prefix
  description = "Random data API using Lambda - generates quotes, numbers, and colors"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    Description = "REST API for ${local.name_prefix} random data service"
  })
}

# API Gateway resource for /random endpoint
resource "aws_api_gateway_resource" "random_resource" {
  rest_api_id = aws_api_gateway_rest_api.random_data_api.id
  parent_id   = aws_api_gateway_rest_api.random_data_api.root_resource_id
  path_part   = "random"
}

# API Gateway GET method for /random
resource "aws_api_gateway_method" "random_get" {
  rest_api_id   = aws_api_gateway_rest_api.random_data_api.id
  resource_id   = aws_api_gateway_resource.random_resource.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.querystring.type" = false
  }
}

# API Gateway OPTIONS method for CORS (if enabled)
resource "aws_api_gateway_method" "random_options" {
  count = var.enable_cors ? 1 : 0
  
  rest_api_id   = aws_api_gateway_rest_api.random_data_api.id
  resource_id   = aws_api_gateway_resource.random_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# API Gateway method response for GET
resource "aws_api_gateway_method_response" "random_get_200" {
  rest_api_id = aws_api_gateway_rest_api.random_data_api.id
  resource_id = aws_api_gateway_resource.random_resource.id
  http_method = aws_api_gateway_method.random_get.http_method
  status_code = "200"

  response_headers = var.enable_cors ? {
    "Access-Control-Allow-Origin"  = true
    "Access-Control-Allow-Methods" = true
    "Access-Control-Allow-Headers" = true
  } : {}

  response_models = {
    "application/json" = "Empty"
  }
}

# API Gateway method response for OPTIONS (CORS)
resource "aws_api_gateway_method_response" "random_options_200" {
  count = var.enable_cors ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.random_data_api.id
  resource_id = aws_api_gateway_resource.random_resource.id
  http_method = aws_api_gateway_method.random_options[0].http_method
  status_code = "200"

  response_headers = {
    "Access-Control-Allow-Origin"  = true
    "Access-Control-Allow-Methods" = true
    "Access-Control-Allow-Headers" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

# API Gateway Lambda integration for GET method
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.random_data_api.id
  resource_id = aws_api_gateway_resource.random_resource.id
  http_method = aws_api_gateway_method.random_get.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.random_data_api.invoke_arn

  request_parameters = {
    "integration.request.querystring.type" = "method.request.querystring.type"
  }
}

# API Gateway integration for OPTIONS method (CORS)
resource "aws_api_gateway_integration" "options_integration" {
  count = var.enable_cors ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.random_data_api.id
  resource_id = aws_api_gateway_resource.random_resource.id
  http_method = aws_api_gateway_method.random_options[0].http_method

  type = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# API Gateway integration response for GET method
resource "aws_api_gateway_integration_response" "lambda_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.random_data_api.id
  resource_id = aws_api_gateway_resource.random_resource.id
  http_method = aws_api_gateway_method.random_get.http_method
  status_code = aws_api_gateway_method_response.random_get_200.status_code

  depends_on = [aws_api_gateway_integration.lambda_integration]
}

# API Gateway integration response for OPTIONS method (CORS)
resource "aws_api_gateway_integration_response" "options_integration_response" {
  count = var.enable_cors ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.random_data_api.id
  resource_id = aws_api_gateway_resource.random_resource.id
  http_method = aws_api_gateway_method.random_options[0].http_method
  status_code = aws_api_gateway_method_response.random_options_200[0].status_code

  response_headers = {
    "Access-Control-Allow-Origin"  = "'${join(",", var.cors_allowed_origins)}'"
    "Access-Control-Allow-Methods" = "'${join(",", var.cors_allowed_methods)}'"
    "Access-Control-Allow-Headers" = "'${join(",", var.cors_allowed_headers)}'"
  }

  depends_on = [aws_api_gateway_integration.options_integration[0]]
}

# Lambda permission for API Gateway to invoke the function
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.random_data_api.function_name
  principal     = "apigateway.amazonaws.com"

  # Allow invocation from any stage, any method, any resource
  source_arn = "${aws_api_gateway_rest_api.random_data_api.execution_arn}/*/*"
}

# IAM role for API Gateway CloudWatch logging (if enabled)
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  count = var.enable_api_logging ? 1 : 0
  
  name = "${local.name_prefix}-api-gateway-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Description = "CloudWatch logging role for ${local.name_prefix} API Gateway"
  })
}

# Attach CloudWatch logs policy to API Gateway role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  count = var.enable_api_logging ? 1 : 0
  
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
  role       = aws_iam_role.api_gateway_cloudwatch_role[0].name
}

# API Gateway account settings for CloudWatch logging
resource "aws_api_gateway_account" "main" {
  count = var.enable_api_logging ? 1 : 0
  
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role[0].arn
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.random_data_api.id

  # Force redeployment when configuration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.random_resource.id,
      aws_api_gateway_method.random_get.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.random_get,
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_method_response.random_get_200,
    aws_api_gateway_integration_response.lambda_integration_response
  ]
}

# API Gateway stage
resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.random_data_api.id
  stage_name    = var.api_stage_name

  # Access logging configuration (if enabled)
  dynamic "access_log_settings" {
    for_each = var.enable_api_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway_logs[0].arn
      format = jsonencode({
        requestId      = "$context.requestId"
        ip             = "$context.identity.sourceIp"
        caller         = "$context.identity.caller"
        user           = "$context.identity.user"
        requestTime    = "$context.requestTime"
        httpMethod     = "$context.httpMethod"
        resourcePath   = "$context.resourcePath"
        status         = "$context.status"
        protocol       = "$context.protocol"
        responseLength = "$context.responseLength"
      })
    }
  }

  # Enable X-Ray tracing
  xray_tracing_enabled = true

  tags = merge(local.common_tags, {
    Description = "API stage ${var.api_stage_name} for ${local.name_prefix}"
  })
}

# API Gateway method settings for throttling and monitoring
resource "aws_api_gateway_method_settings" "main" {
  rest_api_id = aws_api_gateway_rest_api.random_data_api.id
  stage_name  = aws_api_gateway_stage.main.stage_name
  method_path = "*/*"

  settings {
    # Enable CloudWatch metrics
    metrics_enabled = true
    logging_level   = var.enable_api_logging ? "INFO" : "OFF"

    # Throttling settings
    throttling_rate_limit  = var.api_throttle_rate_limit
    throttling_burst_limit = var.api_throttle_burst_limit

    # Enable detailed CloudWatch metrics
    data_trace_enabled = var.enable_api_logging
  }
}