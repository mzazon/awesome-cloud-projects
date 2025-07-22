# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Generate consistent resource names
  resource_suffix = random_id.suffix.hex
  api_name        = "${var.project_name}-${local.resource_suffix}"
  function_name   = "api-backend-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(var.default_tags, {
    Name = local.api_name
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role-${local.resource_suffix}"

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

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = <<EOF
import json
import time
import os

def lambda_handler(event, context):
    # Simulate some processing time
    time.sleep(0.1)
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'message': 'Hello from throttled API!',
            'timestamp': int(time.time()),
            'requestId': context.aws_request_id,
            'region': os.environ.get('AWS_REGION', 'unknown')
        })
    }
EOF
    filename = "lambda_function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "api_backend" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = local.common_tags
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.api_backend.function_name}"
  retention_in_days = 14

  tags = local.common_tags
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = local.api_name
  description = "Demo API for throttling and rate limiting"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

# API Gateway resource for /data endpoint
resource "aws_api_gateway_resource" "data" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "data"
}

# API Gateway method (GET)
resource "aws_api_gateway_method" "get_data" {
  rest_api_id      = aws_api_gateway_rest_api.main.id
  resource_id      = aws_api_gateway_resource.data.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}

# API Gateway integration with Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.data.id
  http_method = aws_api_gateway_method.get_data.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.api_backend.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  # Force new deployment when API configuration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.data.id,
      aws_api_gateway_method.get_data.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.get_data,
    aws_api_gateway_integration.lambda_integration
  ]
}

# API Gateway stage with throttling configuration
resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.stage_name
  description   = "Production stage with throttling"

  # Stage-level throttling settings
  throttle_settings {
    rate_limit  = var.stage_throttle_rate_limit
    burst_limit = var.stage_throttle_burst_limit
  }

  # Enable CloudWatch metrics and logging
  xray_tracing_enabled = true

  tags = local.common_tags

  depends_on = [aws_cloudwatch_log_group.api_gateway_logs]
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.main.id}/${var.stage_name}"
  retention_in_days = 14

  tags = local.common_tags
}

# Usage Plans
resource "aws_api_gateway_usage_plan" "premium" {
  name        = "Premium-Plan-${local.resource_suffix}"
  description = "Premium tier with high limits"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.main.stage_name
  }

  quota_settings {
    limit  = var.premium_quota_limit
    offset = 0
    period = "MONTH"
  }

  throttle_settings {
    rate_limit  = var.premium_rate_limit
    burst_limit = var.premium_burst_limit
  }

  tags = local.common_tags
}

resource "aws_api_gateway_usage_plan" "standard" {
  name        = "Standard-Plan-${local.resource_suffix}"
  description = "Standard tier with moderate limits"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.main.stage_name
  }

  quota_settings {
    limit  = var.standard_quota_limit
    offset = 0
    period = "MONTH"
  }

  throttle_settings {
    rate_limit  = var.standard_rate_limit
    burst_limit = var.standard_burst_limit
  }

  tags = local.common_tags
}

resource "aws_api_gateway_usage_plan" "basic" {
  name        = "Basic-Plan-${local.resource_suffix}"
  description = "Basic tier with low limits"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.main.stage_name
  }

  quota_settings {
    limit  = var.basic_quota_limit
    offset = 0
    period = "MONTH"
  }

  throttle_settings {
    rate_limit  = var.basic_rate_limit
    burst_limit = var.basic_burst_limit
  }

  tags = local.common_tags
}

# API Keys for different customer tiers
resource "aws_api_gateway_api_key" "premium" {
  name        = "premium-customer-${local.resource_suffix}"
  description = "Premium tier customer API key"
  enabled     = true

  tags = merge(local.common_tags, {
    Tier = "Premium"
  })
}

resource "aws_api_gateway_api_key" "standard" {
  name        = "standard-customer-${local.resource_suffix}"
  description = "Standard tier customer API key"
  enabled     = true

  tags = merge(local.common_tags, {
    Tier = "Standard"
  })
}

resource "aws_api_gateway_api_key" "basic" {
  name        = "basic-customer-${local.resource_suffix}"
  description = "Basic tier customer API key"
  enabled     = true

  tags = merge(local.common_tags, {
    Tier = "Basic"
  })
}

# Associate API keys with usage plans
resource "aws_api_gateway_usage_plan_key" "premium" {
  key_id        = aws_api_gateway_api_key.premium.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.premium.id
}

resource "aws_api_gateway_usage_plan_key" "standard" {
  key_id        = aws_api_gateway_api_key.standard.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.standard.id
}

resource "aws_api_gateway_usage_plan_key" "basic" {
  key_id        = aws_api_gateway_api_key.basic.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.basic.id
}

# CloudWatch Alarms (conditional)
resource "aws_cloudwatch_metric_alarm" "api_high_throttling" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "API-High-Throttling-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Count"
  namespace           = "AWS/ApiGateway"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.throttling_alarm_threshold
  alarm_description   = "This metric monitors API Gateway throttling events"
  alarm_unit          = "Count"

  dimensions = {
    ApiName = aws_api_gateway_rest_api.main.name
    Stage   = aws_api_gateway_stage.main.stage_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "api_high_4xx_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "API-High-4xx-Errors-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.error_alarm_threshold
  alarm_description   = "This metric monitors API Gateway 4xx errors"
  alarm_unit          = "Count"

  dimensions = {
    ApiName = aws_api_gateway_rest_api.main.name
    Stage   = aws_api_gateway_stage.main.stage_name
  }

  tags = local.common_tags
}