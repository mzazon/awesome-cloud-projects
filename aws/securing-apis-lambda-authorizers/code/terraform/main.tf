# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name_suffix = random_id.suffix.hex
  
  # Common tags for all resources
  common_tags = {
    Project     = "ServerlessAPIPatterns"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "serverless-api-patterns-lambda-authorizers-api-gateway"
  }
}

# Data source to get current AWS caller identity
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#------------------------------------------------------------------------------
# IAM Role for Lambda Functions
#------------------------------------------------------------------------------

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.api_name}-lambda-role-${local.name_suffix}"

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
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

#------------------------------------------------------------------------------
# CloudWatch Log Groups for Lambda Functions
#------------------------------------------------------------------------------

# Log group for token authorizer
resource "aws_cloudwatch_log_group" "token_authorizer_logs" {
  name              = "/aws/lambda/${var.token_authorizer_name}-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# Log group for request authorizer
resource "aws_cloudwatch_log_group" "request_authorizer_logs" {
  name              = "/aws/lambda/${var.request_authorizer_name}-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# Log group for protected function
resource "aws_cloudwatch_log_group" "protected_function_logs" {
  name              = "/aws/lambda/${var.protected_function_name}-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# Log group for public function
resource "aws_cloudwatch_log_group" "public_function_logs" {
  name              = "/aws/lambda/${var.public_function_name}-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

#------------------------------------------------------------------------------
# Lambda Function Source Code Archives
#------------------------------------------------------------------------------

# Archive for token authorizer function
data "archive_file" "token_authorizer_zip" {
  type        = "zip"
  output_path = "${path.module}/token_authorizer.zip"
  
  source {
    content = templatefile("${path.module}/functions/token_authorizer.py", {
      valid_tokens = jsonencode(var.valid_tokens)
    })
    filename = "token_authorizer.py"
  }
}

# Archive for request authorizer function  
data "archive_file" "request_authorizer_zip" {
  type        = "zip"
  output_path = "${path.module}/request_authorizer.zip"
  
  source {
    content = templatefile("${path.module}/functions/request_authorizer.py", {
      valid_api_keys      = jsonencode(var.valid_api_keys)
      custom_auth_values  = jsonencode(var.custom_auth_values)
    })
    filename = "request_authorizer.py"
  }
}

# Archive for protected API function
data "archive_file" "protected_api_zip" {
  type        = "zip"
  output_path = "${path.module}/protected_api.zip"
  
  source {
    content  = file("${path.module}/functions/protected_api.py")
    filename = "protected_api.py"
  }
}

# Archive for public API function
data "archive_file" "public_api_zip" {
  type        = "zip"
  output_path = "${path.module}/public_api.zip"
  
  source {
    content  = file("${path.module}/functions/public_api.py")
    filename = "public_api.py"
  }
}

#------------------------------------------------------------------------------
# Lambda Functions
#------------------------------------------------------------------------------

# Token-based authorizer Lambda function
resource "aws_lambda_function" "token_authorizer" {
  filename         = data.archive_file.token_authorizer_zip.output_path
  function_name    = "${var.token_authorizer_name}-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "token_authorizer.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.token_authorizer_zip.output_base64sha256

  description = "Token-based API Gateway authorizer function"

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.token_authorizer_logs,
  ]

  tags = local.common_tags
}

# Request-based authorizer Lambda function
resource "aws_lambda_function" "request_authorizer" {
  filename         = data.archive_file.request_authorizer_zip.output_path
  function_name    = "${var.request_authorizer_name}-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "request_authorizer.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.request_authorizer_zip.output_base64sha256

  description = "Request-based API Gateway authorizer function"

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.request_authorizer_logs,
  ]

  tags = local.common_tags
}

# Protected API Lambda function
resource "aws_lambda_function" "protected_api" {
  filename         = data.archive_file.protected_api_zip.output_path
  function_name    = "${var.protected_function_name}-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "protected_api.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.protected_api_zip.output_base64sha256

  description = "Protected API function requiring authorization"

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.protected_function_logs,
  ]

  tags = local.common_tags
}

# Public API Lambda function
resource "aws_lambda_function" "public_api" {
  filename         = data.archive_file.public_api_zip.output_path
  function_name    = "${var.public_function_name}-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "public_api.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.public_api_zip.output_base64sha256

  description = "Public API function without authorization requirements"

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.public_function_logs,
  ]

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# API Gateway REST API
#------------------------------------------------------------------------------

# REST API Gateway
resource "aws_api_gateway_rest_api" "secure_api" {
  name        = "${var.api_name}-${local.name_suffix}"
  description = "Serverless API with Lambda authorizers demonstration"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

# API Gateway CloudWatch log group
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.secure_api.id}/${var.api_stage_name}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

#------------------------------------------------------------------------------
# API Gateway Resources
#------------------------------------------------------------------------------

# /public resource
resource "aws_api_gateway_resource" "public" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  parent_id   = aws_api_gateway_rest_api.secure_api.root_resource_id
  path_part   = "public"
}

# /protected resource
resource "aws_api_gateway_resource" "protected" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  parent_id   = aws_api_gateway_rest_api.secure_api.root_resource_id
  path_part   = "protected"
}

# /protected/admin resource
resource "aws_api_gateway_resource" "admin" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  parent_id   = aws_api_gateway_resource.protected.id
  path_part   = "admin"
}

#------------------------------------------------------------------------------
# API Gateway Authorizers
#------------------------------------------------------------------------------

# Token-based authorizer
resource "aws_api_gateway_authorizer" "token_authorizer" {
  name                   = "TokenAuthorizer"
  rest_api_id           = aws_api_gateway_rest_api.secure_api.id
  authorizer_uri        = aws_lambda_function.token_authorizer.invoke_arn
  authorizer_credentials = aws_iam_role.api_gateway_authorizer_role.arn
  type                  = "TOKEN"
  identity_source       = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = var.authorizer_cache_ttl
}

# Request-based authorizer
resource "aws_api_gateway_authorizer" "request_authorizer" {
  name                   = "RequestAuthorizer"
  rest_api_id           = aws_api_gateway_rest_api.secure_api.id
  authorizer_uri        = aws_lambda_function.request_authorizer.invoke_arn
  authorizer_credentials = aws_iam_role.api_gateway_authorizer_role.arn
  type                  = "REQUEST"
  identity_source       = "method.request.header.X-Custom-Auth,method.request.querystring.api_key"
  authorizer_result_ttl_in_seconds = var.authorizer_cache_ttl
}

# IAM role for API Gateway to invoke authorizer functions
resource "aws_iam_role" "api_gateway_authorizer_role" {
  name = "${var.api_name}-authorizer-role-${local.name_suffix}"

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

# Policy for API Gateway to invoke Lambda functions
resource "aws_iam_role_policy" "api_gateway_authorizer_policy" {
  name = "${var.api_name}-authorizer-policy-${local.name_suffix}"
  role = aws_iam_role.api_gateway_authorizer_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.token_authorizer.arn,
          aws_lambda_function.request_authorizer.arn
        ]
      }
    ]
  })
}

#------------------------------------------------------------------------------
# API Gateway Methods
#------------------------------------------------------------------------------

# Public GET method (no authorization)
resource "aws_api_gateway_method" "public_get" {
  rest_api_id   = aws_api_gateway_rest_api.secure_api.id
  resource_id   = aws_api_gateway_resource.public.id
  http_method   = "GET"
  authorization = "NONE"
}

# Protected GET method (token authorization)
resource "aws_api_gateway_method" "protected_get" {
  rest_api_id   = aws_api_gateway_rest_api.secure_api.id
  resource_id   = aws_api_gateway_resource.protected.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.token_authorizer.id
}

# Admin GET method (request authorization)
resource "aws_api_gateway_method" "admin_get" {
  rest_api_id   = aws_api_gateway_rest_api.secure_api.id
  resource_id   = aws_api_gateway_resource.admin.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.request_authorizer.id
}

#------------------------------------------------------------------------------
# API Gateway Integrations
#------------------------------------------------------------------------------

# Public API integration
resource "aws_api_gateway_integration" "public_integration" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  resource_id = aws_api_gateway_resource.public.id
  http_method = aws_api_gateway_method.public_get.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.public_api.invoke_arn
}

# Protected API integration
resource "aws_api_gateway_integration" "protected_integration" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  resource_id = aws_api_gateway_resource.protected.id
  http_method = aws_api_gateway_method.protected_get.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.protected_api.invoke_arn
}

# Admin API integration
resource "aws_api_gateway_integration" "admin_integration" {
  rest_api_id = aws_api_gateway_rest_api.secure_api.id
  resource_id = aws_api_gateway_resource.admin.id
  http_method = aws_api_gateway_method.admin_get.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.protected_api.invoke_arn
}

#------------------------------------------------------------------------------
# Lambda Permissions
#------------------------------------------------------------------------------

# Permission for API Gateway to invoke public function
resource "aws_lambda_permission" "public_api_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.public_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.secure_api.execution_arn}/*/*"
}

# Permission for API Gateway to invoke protected function
resource "aws_lambda_permission" "protected_api_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.protected_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.secure_api.execution_arn}/*/*"
}

# Permission for API Gateway to invoke token authorizer
resource "aws_lambda_permission" "token_authorizer_permission" {
  statement_id  = "AllowAPIGatewayInvokeTokenAuth"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.token_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.secure_api.execution_arn}/authorizers/${aws_api_gateway_authorizer.token_authorizer.id}"
}

# Permission for API Gateway to invoke request authorizer
resource "aws_lambda_permission" "request_authorizer_permission" {
  statement_id  = "AllowAPIGatewayInvokeRequestAuth"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.request_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.secure_api.execution_arn}/authorizers/${aws_api_gateway_authorizer.request_authorizer.id}"
}

#------------------------------------------------------------------------------
# API Gateway Deployment
#------------------------------------------------------------------------------

# API Gateway deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_method.public_get,
    aws_api_gateway_method.protected_get,
    aws_api_gateway_method.admin_get,
    aws_api_gateway_integration.public_integration,
    aws_api_gateway_integration.protected_integration,
    aws_api_gateway_integration.admin_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.secure_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.public.id,
      aws_api_gateway_resource.protected.id,
      aws_api_gateway_resource.admin.id,
      aws_api_gateway_method.public_get.id,
      aws_api_gateway_method.protected_get.id,
      aws_api_gateway_method.admin_get.id,
      aws_api_gateway_integration.public_integration.id,
      aws_api_gateway_integration.protected_integration.id,
      aws_api_gateway_integration.admin_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.secure_api.id
  stage_name    = var.api_stage_name

  dynamic "access_log_settings" {
    for_each = var.enable_cloudwatch_logs ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway_logs[0].arn
      format = jsonencode({
        requestId      = "$requestId"
        ip             = "$sourceIp"
        caller         = "$caller"
        user           = "$user"
        requestTime    = "$requestTime"
        httpMethod     = "$httpMethod"
        resourcePath   = "$resourcePath"
        status         = "$status"
        protocol       = "$protocol"
        responseLength = "$responseLength"
      })
    }
  }

  tags = local.common_tags
}