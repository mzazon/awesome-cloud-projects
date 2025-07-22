# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for resource uniqueness
resource "random_string" "suffix" {
  count   = var.use_random_suffix ? 1 : 0
  length  = 6
  special = false
  upper   = false
}

locals {
  # Generate unique resource names
  suffix = var.use_random_suffix ? "-${random_string.suffix[0].result}" : ""
  
  function_name = "${var.resource_prefix}-${var.function_name}${local.suffix}"
  api_name      = "${var.resource_prefix}-${var.api_name}${local.suffix}"
  role_name     = "${var.resource_prefix}-lambda-role${local.suffix}"
  
  # Common tags
  common_tags = merge({
    Name        = "${var.resource_prefix}-${var.function_name}"
    Environment = var.environment
    Project     = "lambda-deployment-patterns"
    ManagedBy   = "terraform"
  }, var.additional_tags)
}

# =====================================================
# IAM Role and Policies for Lambda Function
# =====================================================

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution_role" {
  name = local.role_name

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

  tags = local.common_tags
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# =====================================================
# Lambda Function Code for Version 1 (Blue)
# =====================================================

# Create Lambda function code for Version 1
resource "local_file" "lambda_function_v1" {
  filename = "${path.module}/lambda_function_v1.py"
  content  = <<EOF
import json
import os

def lambda_handler(event, context):
    version = "1.0.0"
    message = "Hello from Lambda Version 1 - Blue Environment"
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'version': version,
            'message': message,
            'timestamp': context.aws_request_id,
            'environment': 'blue'
        })
    }
EOF
}

# Archive Lambda function code for Version 1
data "archive_file" "lambda_function_v1" {
  type        = "zip"
  source_file = local_file.lambda_function_v1.filename
  output_path = "${path.module}/function-v1.zip"
  
  depends_on = [local_file.lambda_function_v1]
}

# =====================================================
# Lambda Function Code for Version 2 (Green)
# =====================================================

# Create Lambda function code for Version 2
resource "local_file" "lambda_function_v2" {
  filename = "${path.module}/lambda_function_v2.py"
  content  = <<EOF
import json
import os

def lambda_handler(event, context):
    version = "2.0.0"
    message = "Hello from Lambda Version 2 - Green Environment with NEW FEATURES!"
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'version': version,
            'message': message,
            'timestamp': context.aws_request_id,
            'environment': 'green',
            'features': ['enhanced_logging', 'improved_performance']
        })
    }
EOF
}

# Archive Lambda function code for Version 2
data "archive_file" "lambda_function_v2" {
  type        = "zip"
  source_file = local_file.lambda_function_v2.filename
  output_path = "${path.module}/function-v2.zip"
  
  depends_on = [local_file.lambda_function_v2]
}

# =====================================================
# CloudWatch Log Group
# =====================================================

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.cloudwatch_retention_days
  
  tags = local.common_tags
}

# =====================================================
# Lambda Function with Initial Version
# =====================================================

# Lambda function with initial code (Version 1)
resource "aws_lambda_function" "deployment_demo" {
  filename         = data.archive_file.lambda_function_v1.output_path
  function_name    = local.function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function_v1.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_function_v1.output_base64sha256
  
  description = "Demo function for Lambda deployment patterns"
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = local.common_tags
}

# =====================================================
# Lambda Function Versions
# =====================================================

# Publish Version 1 (Blue)
resource "aws_lambda_function" "deployment_demo_v1" {
  filename         = data.archive_file.lambda_function_v1.output_path
  function_name    = local.function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function_v1.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_function_v1.output_base64sha256
  
  description = "Version 1 - Blue Environment"
  publish     = true
  
  depends_on = [aws_lambda_function.deployment_demo]
  
  tags = local.common_tags
}

# Update function with Version 2 code and publish
resource "aws_lambda_function" "deployment_demo_v2" {
  filename         = data.archive_file.lambda_function_v2.output_path
  function_name    = local.function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function_v2.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_function_v2.output_base64sha256
  
  description = "Version 2 - Green Environment with new features"
  publish     = true
  
  depends_on = [aws_lambda_function.deployment_demo_v1]
  
  tags = local.common_tags
}

# =====================================================
# Lambda Alias for Production Traffic Routing
# =====================================================

# Production alias for traffic routing
resource "aws_lambda_alias" "production" {
  name             = "production"
  description      = "Production alias for blue-green and canary deployments"
  function_name    = aws_lambda_function.deployment_demo.function_name
  function_version = var.enable_blue_green_deployment ? aws_lambda_function.deployment_demo_v2.version : aws_lambda_function.deployment_demo_v1.version
  
  # Configure canary deployment with weighted routing
  dynamic "routing_config" {
    for_each = var.enable_canary_deployment ? [1] : []
    content {
      additional_version_weights = {
        (aws_lambda_function.deployment_demo_v1.version) = (100 - var.canary_traffic_percentage) / 100
      }
    }
  }
  
  depends_on = [
    aws_lambda_function.deployment_demo_v1,
    aws_lambda_function.deployment_demo_v2
  ]
}

# =====================================================
# API Gateway REST API
# =====================================================

# API Gateway REST API
resource "aws_api_gateway_rest_api" "deployment_api" {
  name        = local.api_name
  description = var.api_description
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = local.common_tags
}

# API Gateway resource for /demo endpoint
resource "aws_api_gateway_resource" "demo_resource" {
  rest_api_id = aws_api_gateway_rest_api.deployment_api.id
  parent_id   = aws_api_gateway_rest_api.deployment_api.root_resource_id
  path_part   = "demo"
}

# API Gateway GET method
resource "aws_api_gateway_method" "demo_get" {
  rest_api_id   = aws_api_gateway_rest_api.deployment_api.id
  resource_id   = aws_api_gateway_resource.demo_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# API Gateway integration with Lambda function alias
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.deployment_api.id
  resource_id = aws_api_gateway_resource.demo_resource.id
  http_method = aws_api_gateway_method.demo_get.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.deployment_demo.arn}:production/invocations"
}

# API Gateway method response
resource "aws_api_gateway_method_response" "demo_response" {
  rest_api_id = aws_api_gateway_rest_api.deployment_api.id
  resource_id = aws_api_gateway_resource.demo_resource.id
  http_method = aws_api_gateway_method.demo_get.http_method
  status_code = "200"
  
  response_models = {
    "application/json" = "Empty"
  }
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_method_response.demo_response
  ]
  
  rest_api_id = aws_api_gateway_rest_api.deployment_api.id
  stage_name  = var.api_stage_name
  
  description = "Production deployment with Lambda deployment patterns"
  
  lifecycle {
    create_before_destroy = true
  }
}

# Lambda permission for API Gateway to invoke function
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.deployment_demo.function_name
  principal     = "apigateway.amazonaws.com"
  qualifier     = "production"
  
  source_arn = "${aws_api_gateway_rest_api.deployment_api.execution_arn}/*/*"
}

# =====================================================
# CloudWatch Monitoring and Alarms
# =====================================================

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "${local.function_name}-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.error_alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.error_alarm_threshold
  alarm_description   = "This metric monitors Lambda function error rate"
  alarm_actions       = []
  
  dimensions = {
    FunctionName = aws_lambda_function.deployment_demo.function_name
  }
  
  tags = local.common_tags
}

# CloudWatch alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration_alarm" {
  alarm_name          = "${local.function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = var.lambda_timeout * 1000 * 0.8  # 80% of timeout in milliseconds
  alarm_description   = "This metric monitors Lambda function execution duration"
  alarm_actions       = []
  
  dimensions = {
    FunctionName = aws_lambda_function.deployment_demo.function_name
  }
  
  tags = local.common_tags
}

# CloudWatch alarm for API Gateway 4xx errors
resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx_alarm" {
  alarm_name          = "${local.api_name}-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "This metric monitors API Gateway 4xx errors"
  alarm_actions       = []
  
  dimensions = {
    ApiName   = aws_api_gateway_rest_api.deployment_api.name
    Stage     = var.api_stage_name
  }
  
  tags = local.common_tags
}

# CloudWatch alarm for API Gateway 5xx errors
resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx_alarm" {
  alarm_name          = "${local.api_name}-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "This metric monitors API Gateway 5xx errors"
  alarm_actions       = []
  
  dimensions = {
    ApiName   = aws_api_gateway_rest_api.deployment_api.name
    Stage     = var.api_stage_name
  }
  
  tags = local.common_tags
}