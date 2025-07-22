# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Generate unique resource names
  resource_suffix = random_id.suffix.hex
  table_name      = "${var.project_name}-users-${local.resource_suffix}"
  api_name        = "${var.project_name}-api-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(
    var.additional_tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "serverless-api-development-sam-api-gateway"
    }
  )
  
  # Lambda function configuration
  lambda_functions = {
    list_users = {
      handler     = "app.lambda_handler"
      description = "List all users from DynamoDB"
      http_method = "GET"
      resource    = "users"
    }
    create_user = {
      handler     = "app.lambda_handler"
      description = "Create a new user in DynamoDB"
      http_method = "POST"
      resource    = "users"
    }
    get_user = {
      handler     = "app.lambda_handler"
      description = "Get a specific user from DynamoDB"
      http_method = "GET"
      resource    = "users/{id}"
    }
    update_user = {
      handler     = "app.lambda_handler"
      description = "Update a user in DynamoDB"
      http_method = "PUT"
      resource    = "users/{id}"
    }
    delete_user = {
      handler     = "app.lambda_handler"
      description = "Delete a user from DynamoDB"
      http_method = "DELETE"
      resource    = "users/{id}"
    }
  }
}

# DynamoDB table for storing user data
resource "aws_dynamodb_table" "users" {
  name           = local.table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"
  
  # Configure capacity only if using PROVISIONED billing mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "id"
    type = "S"
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name        = local.table_name
    Description = "User data storage for serverless API"
  })
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${local.resource_suffix}"

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
    Name        = "${var.project_name}-lambda-role-${local.resource_suffix}"
    Description = "IAM role for Lambda functions"
  })
}

# IAM policy for Lambda to access DynamoDB
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.project_name}-lambda-dynamodb-policy-${local.resource_suffix}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.users.arn,
          "${aws_dynamodb_table.users.arn}/*"
        ]
      }
    ]
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach X-Ray tracing policy if enabled
resource "aws_iam_role_policy_attachment" "lambda_xray_execution" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Create Lambda function source code archives
data "archive_file" "lambda_functions" {
  for_each = local.lambda_functions
  
  type        = "zip"
  output_path = "${path.module}/lambda_${each.key}.zip"
  
  source {
    content = templatefile("${path.module}/lambda_templates/${each.key}.py", {
      table_name = aws_dynamodb_table.users.name
    })
    filename = "app.py"
  }
  
  source {
    content = file("${path.module}/lambda_templates/shared/dynamodb_utils.py")
    filename = "shared/dynamodb_utils.py"
  }
  
  source {
    content = "boto3==1.26.137\nbotocore==1.29.137"
    filename = "requirements.txt"
  }
}

# Lambda functions
resource "aws_lambda_function" "api_functions" {
  for_each = local.lambda_functions

  function_name                  = "${var.project_name}-${each.key}-${local.resource_suffix}"
  role                          = aws_iam_role.lambda_role.arn
  handler                       = each.value.handler
  source_code_hash             = data.archive_file.lambda_functions[each.key].output_base64sha256
  filename                     = data.archive_file.lambda_functions[each.key].output_path
  runtime                      = var.lambda_runtime
  timeout                      = var.lambda_timeout
  memory_size                  = var.lambda_memory_size
  reserved_concurrent_executions = var.lambda_reserved_concurrency
  description                  = each.value.description

  environment {
    variables = {
      DYNAMODB_TABLE     = aws_dynamodb_table.users.name
      CORS_ALLOW_ORIGIN  = var.cors_allow_origin
    }
  }

  # Enable X-Ray tracing if configured
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs,
  ]

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-${each.key}-${local.resource_suffix}"
    Description = each.value.description
    Function    = each.key
  })
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = local.lambda_functions

  name              = "/aws/lambda/${var.project_name}-${each.key}-${local.resource_suffix}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name        = "/aws/lambda/${var.project_name}-${each.key}-${local.resource_suffix}"
    Description = "CloudWatch logs for ${each.key} Lambda function"
  })
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "users_api" {
  name        = local.api_name
  description = "Serverless API for user management"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    Name        = local.api_name
    Description = "REST API for serverless user management"
  })
}

# API Gateway Resources
resource "aws_api_gateway_resource" "users" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  parent_id   = aws_api_gateway_rest_api.users_api.root_resource_id
  path_part   = "users"
}

resource "aws_api_gateway_resource" "user_by_id" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  parent_id   = aws_api_gateway_resource.users.id
  path_part   = "{id}"
}

# CORS OPTIONS methods
resource "aws_api_gateway_method" "users_options" {
  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "user_by_id_options" {
  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  resource_id   = aws_api_gateway_resource.user_by_id.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# CORS OPTIONS integrations
resource "aws_api_gateway_integration" "users_options" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.users_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_integration" "user_by_id_options" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  resource_id = aws_api_gateway_resource.user_by_id.id
  http_method = aws_api_gateway_method.user_by_id_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

# CORS OPTIONS method responses
resource "aws_api_gateway_method_response" "users_options" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.users_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_method_response" "user_by_id_options" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  resource_id = aws_api_gateway_resource.user_by_id.id
  http_method = aws_api_gateway_method.user_by_id_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# CORS OPTIONS integration responses
resource "aws_api_gateway_integration_response" "users_options" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.users_options.http_method
  status_code = aws_api_gateway_method_response.users_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'${var.cors_allow_headers}'"
    "method.response.header.Access-Control-Allow-Methods" = "'${var.cors_allow_methods}'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.cors_allow_origin}'"
  }

  depends_on = [aws_api_gateway_integration.users_options]
}

resource "aws_api_gateway_integration_response" "user_by_id_options" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  resource_id = aws_api_gateway_resource.user_by_id.id
  http_method = aws_api_gateway_method.user_by_id_options.http_method
  status_code = aws_api_gateway_method_response.user_by_id_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'${var.cors_allow_headers}'"
    "method.response.header.Access-Control-Allow-Methods" = "'${var.cors_allow_methods}'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.cors_allow_origin}'"
  }

  depends_on = [aws_api_gateway_integration.user_by_id_options]
}

# API Gateway Methods for Lambda functions
resource "aws_api_gateway_method" "api_methods" {
  for_each = {
    for k, v in local.lambda_functions : k => v
    if k != "get_user" && k != "update_user" && k != "delete_user"
  }

  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = each.value.http_method
  authorization = "NONE"
}

resource "aws_api_gateway_method" "api_methods_with_id" {
  for_each = {
    for k, v in local.lambda_functions : k => v
    if k == "get_user" || k == "update_user" || k == "delete_user"
  }

  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  resource_id   = aws_api_gateway_resource.user_by_id.id
  http_method   = each.value.http_method
  authorization = "NONE"
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  for_each = local.lambda_functions

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_functions[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.users_api.execution_arn}/*/*"
}

# API Gateway integrations
resource "aws_api_gateway_integration" "lambda_integrations" {
  for_each = {
    for k, v in local.lambda_functions : k => v
    if k != "get_user" && k != "update_user" && k != "delete_user"
  }

  rest_api_id = aws_api_gateway_rest_api.users_api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.api_methods[each.key].http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.api_functions[each.key].invoke_arn
}

resource "aws_api_gateway_integration" "lambda_integrations_with_id" {
  for_each = {
    for k, v in local.lambda_functions : k => v
    if k == "get_user" || k == "update_user" || k == "delete_user"
  }

  rest_api_id = aws_api_gateway_rest_api.users_api.id
  resource_id = aws_api_gateway_resource.user_by_id.id
  http_method = aws_api_gateway_method.api_methods_with_id[each.key].http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.api_functions[each.key].invoke_arn
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integrations,
    aws_api_gateway_integration.lambda_integrations_with_id,
    aws_api_gateway_integration.users_options,
    aws_api_gateway_integration.user_by_id_options,
  ]

  rest_api_id = aws_api_gateway_rest_api.users_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.users.id,
      aws_api_gateway_resource.user_by_id.id,
      aws_api_gateway_method.api_methods,
      aws_api_gateway_method.api_methods_with_id,
      aws_api_gateway_integration.lambda_integrations,
      aws_api_gateway_integration.lambda_integrations_with_id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  stage_name    = var.api_stage_name

  # Enable CloudWatch logging if configured
  dynamic "access_log_settings" {
    for_each = var.enable_api_gateway_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway_logs[0].arn
      format = jsonencode({
        requestId      = "$requestId"
        ip            = "$sourceIp"
        caller        = "$caller"
        user          = "$user"
        requestTime   = "$requestTime"
        httpMethod    = "$httpMethod"
        resourcePath  = "$resourcePath"
        status        = "$status"
        protocol      = "$protocol"
        responseLength = "$responseLength"
      })
    }
  }

  # Enable X-Ray tracing if configured
  xray_tracing_enabled = var.enable_xray_tracing

  tags = merge(local.common_tags, {
    Name        = "${local.api_name}-${var.api_stage_name}"
    Description = "API Gateway stage for ${var.api_stage_name} environment"
  })
}

# CloudWatch Log Group for API Gateway (conditional)
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count = var.enable_api_gateway_logging ? 1 : 0

  name              = "/aws/apigateway/${local.api_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name        = "/aws/apigateway/${local.api_name}"
    Description = "CloudWatch logs for API Gateway"
  })
}

# API Gateway method settings for logging
resource "aws_api_gateway_method_settings" "api_settings" {
  count = var.enable_api_gateway_logging ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.users_api.id
  stage_name  = aws_api_gateway_stage.api_stage.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = var.api_gateway_log_level
  }
}

# CloudWatch Dashboard for monitoring (optional)
resource "aws_cloudwatch_dashboard" "api_dashboard" {
  dashboard_name = "${var.project_name}-api-dashboard-${local.resource_suffix}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", aws_api_gateway_rest_api.users_api.name],
            [".", "Latency", ".", "."],
            [".", "4XXError", ".", "."],
            [".", "5XXError", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "API Gateway Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            for func_name in keys(local.lambda_functions) : [
              "AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.api_functions[func_name].function_name
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Lambda Function Invocations"
          period  = 300
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-api-dashboard-${local.resource_suffix}"
    Description = "CloudWatch dashboard for API monitoring"
  })
}