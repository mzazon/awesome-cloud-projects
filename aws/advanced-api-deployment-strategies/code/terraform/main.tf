# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  resource_suffix = random_id.suffix.hex
  common_name     = "${var.project_name}-${local.resource_suffix}"
  
  # Lambda function names with suffix
  blue_function_name  = "${var.blue_function_name}-${local.resource_suffix}"
  green_function_name = "${var.green_function_name}-${local.resource_suffix}"
  
  # API Gateway name with suffix
  api_name = "${var.api_name}-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(var.default_tags, {
    Name = local.common_name
  })
}

# IAM Role for Lambda Functions
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

# Additional IAM policy for Lambda functions (X-Ray, VPC, etc.)
resource "aws_iam_role_policy" "lambda_additional_permissions" {
  name = "lambda-additional-permissions-${local.resource_suffix}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# VPC permissions for Lambda (if VPC config is provided)
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  count      = var.vpc_config != null ? 1 : 0
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# SQS Dead Letter Queue (if enabled)
resource "aws_sqs_queue" "lambda_dlq" {
  count                     = var.enable_dlq ? 1 : 0
  name                      = "lambda-dlq-${local.resource_suffix}"
  message_retention_seconds = 1209600 # 14 days
  
  tags = local.common_tags
}

# Blue Lambda Function (Current Production Version)
resource "aws_lambda_function" "blue_function" {
  filename         = "blue_function.zip"
  function_name    = local.blue_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  # Enable X-Ray tracing
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }
  
  # VPC configuration (if provided)
  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [var.vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }
  
  # Dead Letter Queue configuration
  dynamic "dead_letter_config" {
    for_each = var.enable_dlq ? [1] : []
    content {
      target_arn = aws_sqs_queue.lambda_dlq[0].arn
    }
  }
  
  # Lambda Layer (if provided)
  layers = var.lambda_layer_arn != null ? [var.lambda_layer_arn] : []
  
  # Reserved concurrency
  reserved_concurrent_executions = var.lambda_reserved_concurrency
  
  # Environment variables
  environment {
    variables = {
      ENVIRONMENT = "blue"
      VERSION     = var.blue_version
      STAGE       = "production"
    }
  }
  
  tags = merge(local.common_tags, {
    Environment = "blue"
    Version     = var.blue_version
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_additional_permissions
  ]
}

# Green Lambda Function (New Version for Testing)
resource "aws_lambda_function" "green_function" {
  filename         = "green_function.zip"
  function_name    = local.green_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  # Enable X-Ray tracing
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }
  
  # VPC configuration (if provided)
  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [var.vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }
  
  # Dead Letter Queue configuration
  dynamic "dead_letter_config" {
    for_each = var.enable_dlq ? [1] : []
    content {
      target_arn = aws_sqs_queue.lambda_dlq[0].arn
    }
  }
  
  # Lambda Layer (if provided)
  layers = var.lambda_layer_arn != null ? [var.lambda_layer_arn] : []
  
  # Reserved concurrency
  reserved_concurrent_executions = var.lambda_reserved_concurrency
  
  # Environment variables
  environment {
    variables = {
      ENVIRONMENT = "green"
      VERSION     = var.green_version
      STAGE       = "staging"
    }
  }
  
  tags = merge(local.common_tags, {
    Environment = "green"
    Version     = var.green_version
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_additional_permissions
  ]
}

# Create placeholder Lambda function code files
resource "local_file" "blue_function_code" {
  filename = "blue_function.py"
  content  = <<EOF
import json
import os

def lambda_handler(event, context):
    """
    Blue environment Lambda function handler
    Represents the current production version
    """
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'message': 'Hello from Blue environment!',
            'version': os.environ.get('VERSION', 'v1.0.0'),
            'environment': os.environ.get('ENVIRONMENT', 'blue'),
            'timestamp': context.aws_request_id,
            'function_name': context.function_name
        })
    }
EOF
}

resource "local_file" "green_function_code" {
  filename = "green_function.py"
  content  = <<EOF
import json
import os

def lambda_handler(event, context):
    """
    Green environment Lambda function handler
    Represents the new version with enhanced features
    """
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'message': 'Hello from Green environment!',
            'version': os.environ.get('VERSION', 'v2.0.0'),
            'environment': os.environ.get('ENVIRONMENT', 'green'),
            'timestamp': context.aws_request_id,
            'function_name': context.function_name,
            'new_feature': 'Enhanced response format'
        })
    }
EOF
}

# Create ZIP files for Lambda functions
data "archive_file" "blue_function_zip" {
  type        = "zip"
  source_file = local_file.blue_function_code.filename
  output_path = "blue_function.zip"
  depends_on  = [local_file.blue_function_code]
}

data "archive_file" "green_function_zip" {
  type        = "zip"
  source_file = local_file.green_function_code.filename
  output_path = "green_function.zip"
  depends_on  = [local_file.green_function_code]
}

# IAM Role for API Gateway CloudWatch Logs
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  count = var.enable_api_gateway_logging ? 1 : 0
  name  = "api-gateway-cloudwatch-role-${local.resource_suffix}"

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

  tags = local.common_tags
}

# Attach CloudWatch logs policy to API Gateway role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_policy" {
  count      = var.enable_api_gateway_logging ? 1 : 0
  role       = aws_iam_role.api_gateway_cloudwatch_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# API Gateway Account Configuration for CloudWatch Logs
resource "aws_api_gateway_account" "api_gateway_account" {
  count               = var.enable_api_gateway_logging ? 1 : 0
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role[0].arn
  depends_on          = [aws_iam_role_policy_attachment.api_gateway_cloudwatch_policy]
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "advanced_deployment_api" {
  name        = local.api_name
  description = var.api_description

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  # Enable binary media types if needed
  binary_media_types = ["*/*"]

  tags = local.common_tags
}

# API Gateway Resource (/hello)
resource "aws_api_gateway_resource" "hello_resource" {
  rest_api_id = aws_api_gateway_rest_api.advanced_deployment_api.id
  parent_id   = aws_api_gateway_rest_api.advanced_deployment_api.root_resource_id
  path_part   = "hello"
}

# API Gateway Method (GET /hello)
resource "aws_api_gateway_method" "hello_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.advanced_deployment_api.id
  resource_id   = aws_api_gateway_resource.hello_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# API Gateway Integration with Blue Lambda (Production)
resource "aws_api_gateway_integration" "blue_lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.advanced_deployment_api.id
  resource_id = aws_api_gateway_resource.hello_resource.id
  http_method = aws_api_gateway_method.hello_get_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.blue_function.invoke_arn
}

# Lambda Permission for API Gateway to invoke Blue function
resource "aws_lambda_permission" "blue_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.blue_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.advanced_deployment_api.execution_arn}/*/*"
}

# Lambda Permission for API Gateway to invoke Green function
resource "aws_lambda_permission" "green_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.green_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.advanced_deployment_api.execution_arn}/*/*"
}

# API Gateway Deployment for Production (Blue)
resource "aws_api_gateway_deployment" "production_deployment" {
  depends_on = [
    aws_api_gateway_integration.blue_lambda_integration,
    aws_lambda_permission.blue_lambda_permission
  ]

  rest_api_id = aws_api_gateway_rest_api.advanced_deployment_api.id
  description = "Production deployment with Blue environment"

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage for Production
resource "aws_api_gateway_stage" "production_stage" {
  deployment_id = aws_api_gateway_deployment.production_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.advanced_deployment_api.id
  stage_name    = var.api_stage_name
  description   = "Production stage with Blue environment"

  # Enable X-Ray tracing
  xray_tracing_enabled = var.enable_xray_tracing

  # Configure throttling
  throttle_settings {
    rate_limit  = var.api_throttle_rate_limit
    burst_limit = var.api_throttle_burst_limit
  }

  # Method-level settings for monitoring and logging
  method_settings {
    method_path = "*/*"
    
    # Enable detailed CloudWatch metrics
    metrics_enabled = var.enable_detailed_metrics
    
    # Configure logging
    logging_level   = var.enable_api_gateway_logging ? "INFO" : "OFF"
    data_trace_enabled = var.enable_api_gateway_logging
    
    # Throttling settings
    throttling_rate_limit  = var.api_throttle_rate_limit
    throttling_burst_limit = var.api_throttle_burst_limit
  }

  # Canary deployment settings (if enabled)
  dynamic "canary_settings" {
    for_each = var.enable_canary_deployment ? [1] : []
    content {
      percent_traffic = var.canary_percent_traffic
      use_stage_cache = false
      stage_variable_overrides = {
        environment = "canary"
      }
    }
  }

  tags = local.common_tags
  
  depends_on = [aws_api_gateway_account.api_gateway_account]
}

# API Gateway Deployment for Staging (Green)
resource "aws_api_gateway_deployment" "staging_deployment" {
  depends_on = [
    aws_api_gateway_integration.blue_lambda_integration,
    aws_lambda_permission.green_lambda_permission
  ]

  rest_api_id = aws_api_gateway_rest_api.advanced_deployment_api.id
  description = "Staging deployment with Green environment"

  lifecycle {
    create_before_destroy = true
  }
}

# Update Integration for Staging to point to Green Lambda
resource "aws_api_gateway_integration" "green_lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.advanced_deployment_api.id
  resource_id = aws_api_gateway_resource.hello_resource.id
  http_method = aws_api_gateway_method.hello_get_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.green_function.invoke_arn
}

# API Gateway Stage for Staging
resource "aws_api_gateway_stage" "staging_stage" {
  deployment_id = aws_api_gateway_deployment.staging_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.advanced_deployment_api.id
  stage_name    = var.api_staging_stage_name
  description   = "Staging stage for Green environment testing"

  # Enable X-Ray tracing
  xray_tracing_enabled = var.enable_xray_tracing

  # Configure throttling
  throttle_settings {
    rate_limit  = var.api_throttle_rate_limit
    burst_limit = var.api_throttle_burst_limit
  }

  # Method-level settings for monitoring and logging
  method_settings {
    method_path = "*/*"
    
    # Enable detailed CloudWatch metrics
    metrics_enabled = var.enable_detailed_metrics
    
    # Configure logging
    logging_level   = var.enable_api_gateway_logging ? "INFO" : "OFF"
    data_trace_enabled = var.enable_api_gateway_logging
    
    # Throttling settings
    throttling_rate_limit  = var.api_throttle_rate_limit
    throttling_burst_limit = var.api_throttle_burst_limit
  }

  tags = local.common_tags
  
  depends_on = [aws_api_gateway_account.api_gateway_account]
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  count             = var.enable_api_gateway_logging ? 1 : 0
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.advanced_deployment_api.id}/${var.api_stage_name}"
  retention_in_days = 14
  
  tags = local.common_tags
}

# CloudWatch Alarm for 4XX Errors
resource "aws_cloudwatch_metric_alarm" "api_4xx_errors" {
  alarm_name          = "${local.api_name}-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "This metric monitors 4XX errors for API Gateway"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.advanced_deployment_api.name
    Stage   = aws_api_gateway_stage.production_stage.stage_name
  }

  treat_missing_data = "notBreaching"
  
  tags = local.common_tags
}

# CloudWatch Alarm for 5XX Errors
resource "aws_cloudwatch_metric_alarm" "api_5xx_errors" {
  alarm_name          = "${local.api_name}-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = var.error_rate_threshold
  alarm_description   = "This metric monitors 5XX errors for API Gateway"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.advanced_deployment_api.name
    Stage   = aws_api_gateway_stage.production_stage.stage_name
  }

  treat_missing_data = "notBreaching"
  
  tags = local.common_tags
}

# CloudWatch Alarm for High Latency
resource "aws_cloudwatch_metric_alarm" "api_high_latency" {
  alarm_name          = "${local.api_name}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Average"
  threshold           = var.latency_threshold
  alarm_description   = "This metric monitors API Gateway latency"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.advanced_deployment_api.name
    Stage   = aws_api_gateway_stage.production_stage.stage_name
  }

  treat_missing_data = "notBreaching"
  
  tags = local.common_tags
}

# CloudWatch Alarm for Lambda Blue Function Errors
resource "aws_cloudwatch_metric_alarm" "blue_lambda_errors" {
  alarm_name          = "${local.blue_function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.error_rate_threshold
  alarm_description   = "This metric monitors Blue Lambda function errors"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.blue_function.function_name
  }

  treat_missing_data = "notBreaching"
  
  tags = local.common_tags
}

# CloudWatch Alarm for Lambda Green Function Errors
resource "aws_cloudwatch_metric_alarm" "green_lambda_errors" {
  alarm_name          = "${local.green_function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.error_rate_threshold
  alarm_description   = "This metric monitors Green Lambda function errors"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.green_function.function_name
  }

  treat_missing_data = "notBreaching"
  
  tags = local.common_tags
}

# Custom Domain Name (if provided)
resource "aws_api_gateway_domain_name" "custom_domain" {
  count           = var.custom_domain_name != null ? 1 : 0
  domain_name     = var.custom_domain_name
  certificate_arn = var.certificate_arn

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

# API Gateway Base Path Mapping for Custom Domain
resource "aws_api_gateway_base_path_mapping" "custom_domain_mapping" {
  count       = var.custom_domain_name != null ? 1 : 0
  api_id      = aws_api_gateway_rest_api.advanced_deployment_api.id
  stage_name  = aws_api_gateway_stage.production_stage.stage_name
  domain_name = aws_api_gateway_domain_name.custom_domain[0].domain_name
}

# Route 53 Record for Custom Domain (if provided)
resource "aws_route53_record" "custom_domain_record" {
  count   = var.custom_domain_name != null && var.route53_hosted_zone_id != null ? 1 : 0
  zone_id = var.route53_hosted_zone_id
  name    = var.custom_domain_name
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.custom_domain[0].regional_domain_name
    zone_id                = aws_api_gateway_domain_name.custom_domain[0].regional_zone_id
    evaluate_target_health = false
  }
}