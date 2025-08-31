# ================================================================
# Main Terraform Configuration for Customer Support Agent
# Recipe: Persistent Customer Support Agent with Bedrock AgentCore Memory
# Description: Infrastructure to deploy an intelligent customer support agent
#             using Amazon Bedrock AgentCore Memory for persistent context
# ================================================================

# Data sources for common AWS information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ================================================================
# BEDROCK AGENTCORE MEMORY CONFIGURATION
# ================================================================

# Create AgentCore Memory for persistent customer context
resource "aws_bedrockagent_memory" "customer_support_memory" {
  name                   = "${var.memory_name_prefix}-${random_string.suffix.result}"
  description           = "Customer support agent memory for maintaining context across sessions"
  event_expiry_duration = "P30D"

  memory_strategies = [
    {
      summarization = {
        enabled = true
      }
    },
    {
      semantic_memory = {
        enabled = true
      }
    },
    {
      user_preferences = {
        enabled = true
      }
    }
  ]

  tags = merge(var.tags, {
    Name    = "${var.memory_name_prefix}-${random_string.suffix.result}"
    Purpose = "CustomerSupport"
  })
}

# ================================================================
# DYNAMODB TABLE FOR CUSTOMER METADATA
# ================================================================

# DynamoDB table to store customer metadata and preferences
resource "aws_dynamodb_table" "customer_data" {
  name           = "${var.table_name_prefix}-${random_string.suffix.result}"
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "customerId"

  attribute {
    name = "customerId"
    type = "S"
  }

  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(var.tags, {
    Name    = "${var.table_name_prefix}-${random_string.suffix.result}"
    Purpose = "CustomerSupport"
  })
}

# ================================================================
# IAM ROLE AND POLICIES FOR LAMBDA FUNCTION
# ================================================================

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.lambda_function_name_prefix}-role-${random_string.suffix.result}"

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

  tags = merge(var.tags, {
    Name    = "${var.lambda_function_name_prefix}-role-${random_string.suffix.result}"
    Purpose = "CustomerSupport"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom IAM policy for Bedrock AgentCore, DynamoDB, and Bedrock access
resource "aws_iam_role_policy" "lambda_custom_policy" {
  name = "SupportAgentPolicy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:CreateEvent",
          "bedrock-agentcore:ListSessions",
          "bedrock-agentcore:ListEvents",
          "bedrock-agentcore:GetEvent",
          "bedrock-agentcore:RetrieveMemoryRecords"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.customer_data.arn
      }
    ]
  })
}

# ================================================================
# LAMBDA FUNCTION CODE PACKAGING
# ================================================================

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      bedrock_model_id = var.bedrock_model_id
    })
    filename = "lambda_function.py"
  }
}

# ================================================================
# LAMBDA FUNCTION
# ================================================================

# Lambda function for customer support agent logic
resource "aws_lambda_function" "support_agent" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.lambda_function_name_prefix}-${random_string.suffix.result}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.11"
  timeout         = 30
  memory_size     = 512

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      MEMORY_ID      = aws_bedrockagent_memory.customer_support_memory.id
      DDB_TABLE_NAME = aws_dynamodb_table.customer_data.name
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }

  # Dead letter queue for failed invocations
  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  tags = merge(var.tags, {
    Name    = "${var.lambda_function_name_prefix}-${random_string.suffix.result}"
    Purpose = "CustomerSupport"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_custom_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.lambda_function_name_prefix}-${random_string.suffix.result}"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(var.tags, {
    Name    = "${var.lambda_function_name_prefix}-logs-${random_string.suffix.result}"
    Purpose = "CustomerSupport"
  })
}

# Dead letter queue for Lambda function
resource "aws_sqs_queue" "lambda_dlq" {
  name                       = "${var.lambda_function_name_prefix}-dlq-${random_string.suffix.result}"
  message_retention_seconds  = 1209600 # 14 days
  receive_wait_time_seconds  = 10

  tags = merge(var.tags, {
    Name    = "${var.lambda_function_name_prefix}-dlq-${random_string.suffix.result}"
    Purpose = "CustomerSupport"
  })
}

# ================================================================
# API GATEWAY CONFIGURATION
# ================================================================

# REST API Gateway
resource "aws_api_gateway_rest_api" "support_api" {
  name        = "${var.api_name_prefix}-${random_string.suffix.result}"
  description = "Customer Support Agent API for handling support interactions"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(var.tags, {
    Name    = "${var.api_name_prefix}-${random_string.suffix.result}"
    Purpose = "CustomerSupport"
  })
}

# API Gateway resource for support endpoint
resource "aws_api_gateway_resource" "support_resource" {
  rest_api_id = aws_api_gateway_rest_api.support_api.id
  parent_id   = aws_api_gateway_rest_api.support_api.root_resource_id
  path_part   = "support"
}

# API Gateway method (POST)
resource "aws_api_gateway_method" "support_post" {
  rest_api_id   = aws_api_gateway_rest_api.support_api.id
  resource_id   = aws_api_gateway_resource.support_resource.id
  http_method   = "POST"
  authorization = "NONE"

  request_models = {
    "application/json" = aws_api_gateway_model.support_request_model.name
  }

  request_validator_id = aws_api_gateway_request_validator.support_validator.id
}

# API Gateway request model for validation
resource "aws_api_gateway_model" "support_request_model" {
  rest_api_id  = aws_api_gateway_rest_api.support_api.id
  name         = "SupportRequestModel"
  content_type = "application/json"

  schema = jsonencode({
    "$schema": "http://json-schema.org/draft-04/schema#",
    "title": "Support Request Schema",
    "type": "object",
    "properties": {
      "customerId": {
        "type": "string",
        "minLength": 1
      },
      "message": {
        "type": "string",
        "minLength": 1
      },
      "sessionId": {
        "type": "string"
      },
      "metadata": {
        "type": "object"
      }
    },
    "required": ["customerId", "message"]
  })
}

# API Gateway request validator
resource "aws_api_gateway_request_validator" "support_validator" {
  name                        = "support_request_validator"
  rest_api_id                = aws_api_gateway_rest_api.support_api.id
  validate_request_body      = true
  validate_request_parameters = true
}

# API Gateway integration with Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.support_api.id
  resource_id             = aws_api_gateway_resource.support_resource.id
  http_method             = aws_api_gateway_method.support_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.support_agent.invoke_arn
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "support_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.support_api.id
  stage_name  = var.api_stage_name

  depends_on = [
    aws_api_gateway_method.support_post,
    aws_api_gateway_integration.lambda_integration
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "support_api_stage" {
  deployment_id = aws_api_gateway_deployment.support_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.support_api.id
  stage_name    = var.api_stage_name

  # Enable CloudWatch logging
  access_log_destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
  access_log_format = jsonencode({
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
    errorMessage   = "$context.error.message"
    errorType      = "$context.error.messageString"
  })

  tags = merge(var.tags, {
    Name    = "${var.api_name_prefix}-stage-${random_string.suffix.result}"
    Purpose = "CustomerSupport"
  })
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${var.api_name_prefix}-${random_string.suffix.result}"
  retention_in_days = var.api_log_retention_days

  tags = merge(var.tags, {
    Name    = "${var.api_name_prefix}-logs-${random_string.suffix.result}"
    Purpose = "CustomerSupport"
  })
}

# Permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.support_agent.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.support_api.execution_arn}/*/*"
}

# ================================================================
# CORS CONFIGURATION FOR API GATEWAY
# ================================================================

# OPTIONS method for CORS preflight
resource "aws_api_gateway_method" "support_options" {
  rest_api_id   = aws_api_gateway_rest_api.support_api.id
  resource_id   = aws_api_gateway_resource.support_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# CORS integration for OPTIONS method
resource "aws_api_gateway_integration" "cors_integration" {
  rest_api_id = aws_api_gateway_rest_api.support_api.id
  resource_id = aws_api_gateway_resource.support_resource.id
  http_method = aws_api_gateway_method.support_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# CORS method response
resource "aws_api_gateway_method_response" "cors_method_response" {
  rest_api_id = aws_api_gateway_rest_api.support_api.id
  resource_id = aws_api_gateway_resource.support_resource.id
  http_method = aws_api_gateway_method.support_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# CORS integration response
resource "aws_api_gateway_integration_response" "cors_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.support_api.id
  resource_id = aws_api_gateway_resource.support_resource.id
  http_method = aws_api_gateway_method.support_options.http_method
  status_code = aws_api_gateway_method_response.cors_method_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.cors_integration]
}

# ================================================================
# SAMPLE CUSTOMER DATA
# ================================================================

# Sample customer data items
resource "aws_dynamodb_table_item" "sample_customer_1" {
  count      = var.create_sample_data ? 1 : 0
  table_name = aws_dynamodb_table.customer_data.name
  hash_key   = aws_dynamodb_table.customer_data.hash_key

  item = jsonencode({
    customerId = {
      S = "customer-001"
    }
    name = {
      S = "Sarah Johnson"
    }
    email = {
      S = "sarah.johnson@example.com"
    }
    preferredChannel = {
      S = "chat"
    }
    productInterests = {
      SS = ["enterprise-software", "analytics"]
    }
    supportTier = {
      S = "premium"
    }
    lastInteraction = {
      S = timestamp()
    }
  })
}

resource "aws_dynamodb_table_item" "sample_customer_2" {
  count      = var.create_sample_data ? 1 : 0
  table_name = aws_dynamodb_table.customer_data.name
  hash_key   = aws_dynamodb_table.customer_data.hash_key

  item = jsonencode({
    customerId = {
      S = "customer-002"
    }
    name = {
      S = "Michael Chen"
    }
    email = {
      S = "michael.chen@example.com"
    }
    preferredChannel = {
      S = "email"
    }
    productInterests = {
      SS = ["mobile-apps", "integration"]
    }
    supportTier = {
      S = "standard"
    }
    lastInteraction = {
      S = timestamp()
    }
  })
}

# ================================================================
# CLOUDWATCH MONITORING AND ALARMS
# ================================================================

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "${var.lambda_function_name_prefix}-errors-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = var.alarm_notification_topic != "" ? [var.alarm_notification_topic] : []

  dimensions = {
    FunctionName = aws_lambda_function.support_agent.function_name
  }

  tags = merge(var.tags, {
    Name    = "${var.lambda_function_name_prefix}-errors-${random_string.suffix.result}"
    Purpose = "CustomerSupport"
  })
}

# CloudWatch alarm for API Gateway 4XX errors
resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx_alarm" {
  alarm_name          = "${var.api_name_prefix}-4xx-errors-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors API Gateway 4XX errors"
  alarm_actions       = var.alarm_notification_topic != "" ? [var.alarm_notification_topic] : []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.support_api.name
    Stage   = aws_api_gateway_stage.support_api_stage.stage_name
  }

  tags = merge(var.tags, {
    Name    = "${var.api_name_prefix}-4xx-errors-${random_string.suffix.result}"
    Purpose = "CustomerSupport"
  })
}