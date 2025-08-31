# Main Terraform Configuration for Simple Timezone Converter with Lambda and API Gateway
# This configuration creates a serverless REST API for timezone conversion using AWS Lambda and API Gateway

# Data sources for current AWS region and account information
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Generate random suffix for resource uniqueness if not provided
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  
  # Only create if resource_suffix is empty
  count = var.resource_suffix == "" ? 1 : 0
}

# Local values for consistent naming and tagging across resources
locals {
  # Use provided suffix or generate random one
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_string.suffix[0].result
  
  # Consistent naming pattern for all resources
  name_prefix = "${var.project_name}-${local.resource_suffix}"
  
  # Common tags applied to all resources
  common_tags = {
    Environment   = var.environment
    Project       = var.project_name
    ManagedBy     = "Terraform"
    CreatedBy     = "timezone-converter-recipe"
    CostCenter    = var.cost_center
    Component     = "timezone-converter-api"
  }
}

# Create Lambda function source code file
# This creates the Python code that handles timezone conversion logic
resource "local_file" "lambda_source" {
  filename = "${path.module}/lambda_function.py"
  content  = <<-EOT
import json
import logging
from datetime import datetime
from zoneinfo import ZoneInfo

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Convert timestamp between timezones
    
    Expected event format:
    {
      "timestamp": "2025-07-12T15:30:00",
      "from_timezone": "UTC",
      "to_timezone": "America/New_York"
    }
    """
    try:
        # Parse the request body
        if 'body' in event:
            body = json.loads(event['body'])
        else:
            body = event
        
        # Extract required parameters
        timestamp_str = body.get('timestamp')
        from_tz = body.get('from_timezone', 'UTC')
        to_tz = body.get('to_timezone')
        
        # Validate required parameters
        if not timestamp_str or not to_tz:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Missing required parameters: timestamp and to_timezone'
                })
            }
        
        # Parse the timestamp
        try:
            # Try parsing with timezone info first
            if 'T' in timestamp_str and ('+' in timestamp_str or 'Z' in timestamp_str):
                dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            else:
                # Parse as naive datetime and assign source timezone
                dt_naive = datetime.fromisoformat(timestamp_str)
                dt = dt_naive.replace(tzinfo=ZoneInfo(from_tz))
        except ValueError as e:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': f'Invalid timestamp format: {str(e)}'
                })
            }
        
        # Convert to target timezone
        try:
            target_tz = ZoneInfo(to_tz)
            converted_dt = dt.astimezone(target_tz)
        except Exception as e:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': f'Invalid timezone: {str(e)}'
                })
            }
        
        # Format response
        response_data = {
            'original_timestamp': timestamp_str,
            'original_timezone': from_tz,
            'converted_timestamp': converted_dt.isoformat(),
            'target_timezone': to_tz,
            'timezone_offset': converted_dt.strftime('%z'),
            'timezone_name': converted_dt.tzname()
        }
        
        logger.info(f"Converted {timestamp_str} from {from_tz} to {to_tz}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(response_data)
        }
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error'
            })
        }
EOT
}

# Create deployment package for Lambda function
# This archives the Python code into a ZIP file for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_source.filename
  output_path = "${path.module}/lambda-deployment.zip"
  
  # Ensure the source file is created before archiving
  depends_on = [local_file.lambda_source]
}

# CloudWatch Log Group for Lambda function
# This creates a dedicated log group with configurable retention period
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-${var.lambda_function_name}"
  retention_in_days = var.log_retention_in_days
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-logs"
    Type = "CloudWatch Log Group"
  })
}

# IAM Role for Lambda execution
# This role allows Lambda to write logs to CloudWatch and execute basic operations
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-${var.lambda_role_name}"
  
  # Trust policy allowing Lambda service to assume this role
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
    Name = "${local.name_prefix}-lambda-execution-role"
    Type = "IAM Role"
  })
}

# Attach basic execution policy to Lambda role
# This provides permissions for CloudWatch Logs operations
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Conditional X-Ray policy attachment for tracing
resource "aws_iam_role_policy_attachment" "lambda_xray_execution" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Lambda Function
# This creates the timezone converter function with configurable runtime and memory settings
resource "aws_lambda_function" "timezone_converter" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-${var.lambda_function_name}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  description     = var.lambda_description
  
  # Use SHA256 hash of the ZIP file to trigger updates when code changes
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  # Optional X-Ray tracing configuration
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }
  
  # Environment variables can be added here if needed
  environment {
    variables = {
      LOG_LEVEL = "INFO"
      PYTHON_VERSION = var.lambda_runtime
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-timezone-converter-function"
    Type = "Lambda Function"
  })
  
  # Ensure log group exists before function creation
  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}

# API Gateway REST API
# This creates the main API Gateway that will route requests to the Lambda function
resource "aws_api_gateway_rest_api" "timezone_converter_api" {
  name        = "${local.name_prefix}-${var.api_gateway_name}"
  description = var.api_gateway_description
  
  # Configure endpoint type (REGIONAL, EDGE, or PRIVATE)
  endpoint_configuration {
    types = [var.api_gateway_endpoint_type]
  }
  
  # Enable binary media types if needed for file uploads
  binary_media_types = []
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-gateway"
    Type = "API Gateway REST API"
  })
}

# API Gateway Resource for /convert endpoint
# This creates the /convert path under the root resource
resource "aws_api_gateway_resource" "convert_resource" {
  rest_api_id = aws_api_gateway_rest_api.timezone_converter_api.id
  parent_id   = aws_api_gateway_rest_api.timezone_converter_api.root_resource_id
  path_part   = "convert"
}

# API Gateway Method for POST requests to /convert
# This defines the HTTP method that clients will use to call the API
resource "aws_api_gateway_method" "convert_post" {
  rest_api_id   = aws_api_gateway_rest_api.timezone_converter_api.id
  resource_id   = aws_api_gateway_resource.convert_resource.id
  http_method   = "POST"
  authorization = "NONE"
  
  # Request validation can be added here
  # request_validator_id = aws_api_gateway_request_validator.example.id
}

# API Gateway Integration with Lambda function
# This connects the API Gateway method to the Lambda function using proxy integration
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.timezone_converter_api.id
  resource_id             = aws_api_gateway_resource.convert_resource.id
  http_method             = aws_api_gateway_method.convert_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.timezone_converter.invoke_arn
}

# OPTIONS method for CORS preflight requests (if CORS is enabled)
resource "aws_api_gateway_method" "convert_options" {
  count         = var.enable_cors ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.timezone_converter_api.id
  resource_id   = aws_api_gateway_resource.convert_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# Mock integration for OPTIONS method to handle CORS preflight
resource "aws_api_gateway_integration" "options_integration" {
  count       = var.enable_cors ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.timezone_converter_api.id
  resource_id = aws_api_gateway_resource.convert_resource.id
  http_method = aws_api_gateway_method.convert_options[0].http_method
  type        = "MOCK"
  
  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

# Method response for OPTIONS (CORS)
resource "aws_api_gateway_method_response" "options_response" {
  count       = var.enable_cors ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.timezone_converter_api.id
  resource_id = aws_api_gateway_resource.convert_resource.id
  http_method = aws_api_gateway_method.convert_options[0].http_method
  status_code = "200"
  
  response_headers = {
    "Access-Control-Allow-Headers" = true
    "Access-Control-Allow-Methods" = true
    "Access-Control-Allow-Origin"  = true
  }
}

# Integration response for OPTIONS (CORS)
resource "aws_api_gateway_integration_response" "options_integration_response" {
  count       = var.enable_cors ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.timezone_converter_api.id
  resource_id = aws_api_gateway_resource.convert_resource.id
  http_method = aws_api_gateway_method.convert_options[0].http_method
  status_code = "200"
  
  response_headers = {
    "Access-Control-Allow-Headers" = "'${join(",", var.cors_allow_headers)}'"
    "Access-Control-Allow-Methods" = "'${join(",", var.cors_allow_methods)}'"
    "Access-Control-Allow-Origin"  = "'${join(",", var.cors_allow_origins)}'"
  }
  
  depends_on = [aws_api_gateway_integration.options_integration]
}

# Lambda permission for API Gateway to invoke the function
# This grants API Gateway the necessary permissions to call the Lambda function
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.timezone_converter.function_name
  principal     = "apigateway.amazonaws.com"
  
  # Allow invocation from any method and resource within this API
  source_arn = "${aws_api_gateway_rest_api.timezone_converter_api.execution_arn}/*/*/*"
}

# API Gateway Deployment
# This creates an immutable deployment of the API configuration
resource "aws_api_gateway_deployment" "timezone_converter_deployment" {
  rest_api_id = aws_api_gateway_rest_api.timezone_converter_api.id
  
  # Trigger redeployment when API configuration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.convert_resource.id,
      aws_api_gateway_method.convert_post.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
  
  depends_on = [
    aws_api_gateway_method.convert_post,
    aws_api_gateway_integration.lambda_integration,
    aws_lambda_permission.api_gateway_invoke
  ]
}

# API Gateway Stage
# This creates a named deployment stage (e.g., "prod", "dev") with its own configuration
resource "aws_api_gateway_stage" "timezone_converter_stage" {
  deployment_id = aws_api_gateway_deployment.timezone_converter_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.timezone_converter_api.id
  stage_name    = var.api_gateway_stage_name
  
  # Enable detailed CloudWatch metrics if requested
  xray_tracing_enabled = var.enable_xray_tracing
  
  # Configure throttling settings
  throttle_settings {
    rate_limit  = var.api_throttle_rate_limit
    burst_limit = var.api_throttle_burst_limit
  }
  
  # Enable detailed CloudWatch metrics if requested
  dynamic "access_log_settings" {
    for_each = var.enable_detailed_cloudwatch_metrics ? [1] : []
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
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-stage-${var.api_gateway_stage_name}"
    Type = "API Gateway Stage"
  })
}

# CloudWatch Log Group for API Gateway access logs (conditional)
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_detailed_cloudwatch_metrics ? 1 : 0
  name              = "/aws/apigateway/${local.name_prefix}-${var.api_gateway_name}"
  retention_in_days = var.log_retention_in_days
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-gateway-logs"
    Type = "CloudWatch Log Group"
  })
}

# API Gateway Method Settings for detailed monitoring
resource "aws_api_gateway_method_settings" "convert_settings" {
  count       = var.enable_detailed_cloudwatch_metrics ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.timezone_converter_api.id
  stage_name  = aws_api_gateway_stage.timezone_converter_stage.stage_name
  method_path = "*/*"
  
  settings {
    metrics_enabled    = true
    logging_level      = "INFO"
    data_trace_enabled = false  # Set to true for full request/response logging (be careful with sensitive data)
    
    throttling_rate_limit  = var.api_throttle_rate_limit
    throttling_burst_limit = var.api_throttle_burst_limit
  }
}