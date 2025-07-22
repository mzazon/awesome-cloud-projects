# Main Terraform configuration for Conversational AI with Amazon Bedrock and Claude

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  resource_suffix = random_string.suffix.result
  
  # Consolidated tags for all resources
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "conversational-ai-applications-amazon-bedrock-claude"
  })
  
  # Lambda function name
  lambda_function_name = "${local.resource_prefix}-handler-${local.resource_suffix}"
  
  # DynamoDB table name
  dynamodb_table_name = "${local.resource_prefix}-conversations-${local.resource_suffix}"
  
  # API Gateway name
  api_gateway_name = "${local.resource_prefix}-api-${local.resource_suffix}"
}

# Data source to get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Data source to check available Bedrock models
data "aws_bedrock_foundation_models" "claude_models" {
  by_provider = "Anthropic"
}

# DynamoDB table for conversation storage
resource "aws_dynamodb_table" "conversations" {
  name           = local.dynamodb_table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "session_id"
  range_key      = "timestamp"
  
  # Configure capacity only if using PROVISIONED billing mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  attribute {
    name = "session_id"
    type = "S"
  }
  
  attribute {
    name = "timestamp"
    type = "N"
  }
  
  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }
  
  # Server-side encryption
  server_side_encryption {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name        = local.dynamodb_table_name
    Description = "Conversation history storage for conversational AI application"
  })
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.resource_prefix}-lambda-role-${local.resource_suffix}"
  
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
    Name        = "${local.resource_prefix}-lambda-role-${local.resource_suffix}"
    Description = "IAM role for conversational AI Lambda function"
  })
}

# IAM policy for Lambda to access Bedrock, DynamoDB, and CloudWatch
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.resource_prefix}-lambda-policy-${local.resource_suffix}"
  role = aws_iam_role.lambda_execution_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.conversations.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Conditionally attach X-Ray policy if tracing is enabled
resource "aws_iam_role_policy_attachment" "lambda_xray_execution" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "/aws/lambda/${local.lambda_function_name}"
    Description = "CloudWatch logs for conversational AI Lambda function"
  })
}

# Create Lambda function source code
resource "local_file" "lambda_source" {
  filename = "${path.module}/conversational_ai_handler.py"
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    table_name                    = aws_dynamodb_table.conversations.name
    claude_model_id              = var.claude_model_id
    max_tokens                   = var.max_tokens
    temperature                  = var.temperature
    conversation_history_limit   = var.conversation_history_limit
  })
}

# Archive Lambda function source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_source.filename
  output_path = "${path.module}/conversational_ai_handler.zip"
  
  depends_on = [local_file.lambda_source]
}

# Lambda function for conversational AI
resource "aws_lambda_function" "conversational_ai_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "conversational_ai_handler.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  environment {
    variables = {
      TABLE_NAME                  = aws_dynamodb_table.conversations.name
      CLAUDE_MODEL_ID            = var.claude_model_id
      MAX_TOKENS                 = var.max_tokens
      TEMPERATURE                = var.temperature
      CONVERSATION_HISTORY_LIMIT = var.conversation_history_limit
    }
  }
  
  # Enable X-Ray tracing if specified
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs,
  ]
  
  tags = merge(local.common_tags, {
    Name        = local.lambda_function_name
    Description = "Conversational AI handler using Amazon Bedrock and Claude"
  })
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "conversational_ai_api" {
  name        = local.api_gateway_name
  description = "Conversational AI API using Amazon Bedrock and Claude"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = merge(local.common_tags, {
    Name        = local.api_gateway_name
    Description = "REST API for conversational AI application"
  })
}

# API Gateway resource for /chat endpoint
resource "aws_api_gateway_resource" "chat_resource" {
  rest_api_id = aws_api_gateway_rest_api.conversational_ai_api.id
  parent_id   = aws_api_gateway_rest_api.conversational_ai_api.root_resource_id
  path_part   = "chat"
}

# API Gateway POST method for chat
resource "aws_api_gateway_method" "chat_post" {
  rest_api_id   = aws_api_gateway_rest_api.conversational_ai_api.id
  resource_id   = aws_api_gateway_resource.chat_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway OPTIONS method for CORS
resource "aws_api_gateway_method" "chat_options" {
  count         = var.enable_cors ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.conversational_ai_api.id
  resource_id   = aws_api_gateway_resource.chat_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# Lambda integration for POST method
resource "aws_api_gateway_integration" "chat_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.conversational_ai_api.id
  resource_id = aws_api_gateway_resource.chat_resource.id
  http_method = aws_api_gateway_method.chat_post.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.conversational_ai_handler.invoke_arn
}

# Mock integration for OPTIONS method (CORS)
resource "aws_api_gateway_integration" "chat_options_integration" {
  count       = var.enable_cors ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.conversational_ai_api.id
  resource_id = aws_api_gateway_resource.chat_resource.id
  http_method = aws_api_gateway_method.chat_options[0].http_method
  
  type = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# Method response for POST
resource "aws_api_gateway_method_response" "chat_post_response" {
  rest_api_id = aws_api_gateway_rest_api.conversational_ai_api.id
  resource_id = aws_api_gateway_resource.chat_resource.id
  http_method = aws_api_gateway_method.chat_post.http_method
  status_code = "200"
  
  response_parameters = var.enable_cors ? {
    "method.response.header.Access-Control-Allow-Origin" = true
  } : {}
}

# Method response for OPTIONS (CORS)
resource "aws_api_gateway_method_response" "chat_options_response" {
  count       = var.enable_cors ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.conversational_ai_api.id
  resource_id = aws_api_gateway_resource.chat_resource.id
  http_method = aws_api_gateway_method.chat_options[0].http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

# Integration response for POST
resource "aws_api_gateway_integration_response" "chat_post_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.conversational_ai_api.id
  resource_id = aws_api_gateway_resource.chat_resource.id
  http_method = aws_api_gateway_method.chat_post.http_method
  status_code = aws_api_gateway_method_response.chat_post_response.status_code
  
  response_parameters = var.enable_cors ? {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  } : {}
  
  depends_on = [aws_api_gateway_integration.chat_post_integration]
}

# Integration response for OPTIONS (CORS)
resource "aws_api_gateway_integration_response" "chat_options_integration_response" {
  count       = var.enable_cors ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.conversational_ai_api.id
  resource_id = aws_api_gateway_resource.chat_resource.id
  http_method = aws_api_gateway_method.chat_options[0].http_method
  status_code = aws_api_gateway_method_response.chat_options_response[0].status_code
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = join(",", [for origin in var.cors_allowed_origins : "'${origin}'"])
    "method.response.header.Access-Control-Allow-Methods" = join(",", [for method in var.cors_allowed_methods : "'${method}'"])
    "method.response.header.Access-Control-Allow-Headers" = join(",", [for header in var.cors_allowed_headers : "'${header}'"])
  }
  
  depends_on = [aws_api_gateway_integration.chat_options_integration[0]]
}

# Lambda permission for API Gateway to invoke the function
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.conversational_ai_handler.function_name
  principal     = "apigateway.amazonaws.com"
  
  source_arn = "${aws_api_gateway_rest_api.conversational_ai_api.execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "conversational_ai_deployment" {
  depends_on = [
    aws_api_gateway_integration.chat_post_integration,
    aws_api_gateway_integration.chat_options_integration,
    aws_api_gateway_integration_response.chat_post_integration_response,
    aws_api_gateway_integration_response.chat_options_integration_response,
  ]
  
  rest_api_id = aws_api_gateway_rest_api.conversational_ai_api.id
  stage_name  = var.api_stage_name
  
  description = "Deployment for conversational AI API"
  
  # Force new deployment on configuration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.chat_resource.id,
      aws_api_gateway_method.chat_post.id,
      aws_api_gateway_integration.chat_post_integration.id,
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage configuration
resource "aws_api_gateway_stage" "conversational_ai_stage" {
  deployment_id = aws_api_gateway_deployment.conversational_ai_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.conversational_ai_api.id
  stage_name    = var.api_stage_name
  
  # Enable X-Ray tracing for API Gateway if Lambda tracing is enabled
  xray_tracing_enabled = var.enable_xray_tracing
  
  # Enable CloudWatch logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
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
      error          = "$context.error.message"
      errorType      = "$context.error.messageString"
    })
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.api_gateway_name}-${var.api_stage_name}"
    Description = "API Gateway stage for conversational AI application"
  })
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${local.api_gateway_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "/aws/apigateway/${local.api_gateway_name}"
    Description = "CloudWatch logs for conversational AI API Gateway"
  })
}

# CloudWatch Log Group for API Gateway execution logs
resource "aws_cloudwatch_log_group" "api_gateway_execution_logs" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.conversational_ai_api.id}/${var.api_stage_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.conversational_ai_api.id}/${var.api_stage_name}"
    Description = "CloudWatch execution logs for conversational AI API Gateway"
  })
}

# Method settings for API Gateway stage (enable logging)
resource "aws_api_gateway_method_settings" "conversational_ai_method_settings" {
  rest_api_id = aws_api_gateway_rest_api.conversational_ai_api.id
  stage_name  = aws_api_gateway_stage.conversational_ai_stage.stage_name
  method_path = "*/*"
  
  settings {
    metrics_enabled = true
    logging_level   = "INFO"
    
    # Enable detailed CloudWatch metrics
    data_trace_enabled   = true
    throttling_burst_limit = 5000
    throttling_rate_limit  = 10000
  }
}