# =============================================================================
# Enterprise API Integration with AgentCore Gateway and Step Functions
# =============================================================================
# This Terraform configuration deploys a complete enterprise API integration
# system using Amazon Bedrock AgentCore Gateway, Step Functions, Lambda, and 
# API Gateway for intelligent workflow orchestration and AI agent integration.
# =============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project       = var.project_name
      Environment   = var.environment
      Recipe        = "api-integration-agentcore-gateway"
      ManagedBy     = "terraform"
      CreatedDate   = timestamp()
    }
  }
}

# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  name_suffix = random_id.suffix.hex
  
  # Common resource names
  lambda_execution_role_name   = "${var.project_name}-lambda-execution-role-${local.name_suffix}"
  stepfunctions_role_name      = "${var.project_name}-stepfunctions-role-${local.name_suffix}"
  apigateway_role_name         = "${var.project_name}-apigateway-role-${local.name_suffix}"
  
  # Lambda function names
  api_transformer_function_name = "${var.project_name}-api-transformer-${local.name_suffix}"
  data_validator_function_name  = "${var.project_name}-data-validator-${local.name_suffix}"
  
  # Other resource names
  state_machine_name        = "${var.project_name}-orchestrator-${local.name_suffix}"
  api_gateway_name         = "${var.project_name}-integration-${local.name_suffix}"
  cloudwatch_log_group_prefix = "/aws/lambda"
  
  # Common tags for all resources
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "api-integration-agentcore-gateway"
  }
}

# =============================================================================
# CloudWatch Log Groups for Lambda Functions
# =============================================================================

# Log group for API transformer function
resource "aws_cloudwatch_log_group" "api_transformer_logs" {
  name              = "${local.cloudwatch_log_group_prefix}/${local.api_transformer_function_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.api_transformer_function_name}-logs"
  })
}

# Log group for data validator function
resource "aws_cloudwatch_log_group" "data_validator_logs" {
  name              = "${local.cloudwatch_log_group_prefix}/${local.data_validator_function_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.data_validator_function_name}-logs"
  })
}

# Log group for Step Functions execution history
resource "aws_cloudwatch_log_group" "stepfunctions_logs" {
  name              = "/aws/stepfunctions/${local.state_machine_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.state_machine_name}-logs"
  })
}

# =============================================================================
# IAM Roles and Policies
# =============================================================================

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution_role" {
  name = local.lambda_execution_role_name
  
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
    Name = local.lambda_execution_role_name
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Lambda functions to write to CloudWatch Logs
resource "aws_iam_role_policy" "lambda_logging_policy" {
  name = "${local.lambda_execution_role_name}-logging"
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
        Resource = [
          "${aws_cloudwatch_log_group.api_transformer_logs.arn}:*",
          "${aws_cloudwatch_log_group.data_validator_logs.arn}:*"
        ]
      }
    ]
  })
}

# IAM role for Step Functions execution
resource "aws_iam_role" "stepfunctions_execution_role" {
  name = local.stepfunctions_role_name
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = local.stepfunctions_role_name
  })
}

# Custom policy for Step Functions to invoke Lambda functions
resource "aws_iam_role_policy" "stepfunctions_lambda_policy" {
  name = "${local.stepfunctions_role_name}-lambda"
  role = aws_iam_role.stepfunctions_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.api_transformer.arn,
          aws_lambda_function.data_validator.arn,
          "${aws_lambda_function.api_transformer.arn}:*",
          "${aws_lambda_function.data_validator.arn}:*"
        ]
      }
    ]
  })
}

# Custom policy for Step Functions logging
resource "aws_iam_role_policy" "stepfunctions_logging_policy" {
  name = "${local.stepfunctions_role_name}-logging"
  role = aws_iam_role.stepfunctions_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups",
          "logs:GetLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role for API Gateway to invoke Step Functions
resource "aws_iam_role" "apigateway_stepfunctions_role" {
  name = local.apigateway_role_name
  
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
    Name = local.apigateway_role_name
  })
}

# Custom policy for API Gateway to execute Step Functions
resource "aws_iam_role_policy" "apigateway_stepfunctions_policy" {
  name = "${local.apigateway_role_name}-stepfunctions"
  role = aws_iam_role.apigateway_stepfunctions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.api_orchestrator.arn
      }
    ]
  })
}

# =============================================================================
# Lambda Function Deployment Packages
# =============================================================================

# Note: Lambda function source files are stored in the lambda_functions directory
# and are packaged using the archive_file data source below

# Package API transformer function
data "archive_file" "api_transformer_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/api_transformer.zip"
  
  source {
    content  = file("${path.module}/lambda_functions/api_transformer.py")
    filename = "api_transformer.py"
  }
  
}

# Package data validator function
data "archive_file" "data_validator_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/data_validator.zip"
  
  source {
    content  = file("${path.module}/lambda_functions/data_validator.py")
    filename = "data_validator.py"
  }
  
}

# =============================================================================
# Lambda Functions
# =============================================================================

# API Transformer Lambda Function
resource "aws_lambda_function" "api_transformer" {
  filename         = data.archive_file.api_transformer_zip.output_path
  function_name    = local.api_transformer_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "api_transformer.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.api_transformer_zip.output_base64sha256
  
  environment {
    variables = {
      ENVIRONMENT = var.environment
      LOG_LEVEL   = var.log_level
      PROJECT_NAME = var.project_name
    }
  }
  
  # Advanced logging configuration
  logging_config {
    log_format            = "JSON"
    application_log_level = upper(var.log_level)
    system_log_level      = "WARN"
  }
  
  # Enable X-Ray tracing for better observability
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }
  
  tags = merge(local.common_tags, {
    Name = local.api_transformer_function_name
    Type = "APITransformer"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_logging_policy,
    aws_cloudwatch_log_group.api_transformer_logs
  ]
}

# Data Validator Lambda Function
resource "aws_lambda_function" "data_validator" {
  filename         = data.archive_file.data_validator_zip.output_path
  function_name    = local.data_validator_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "data_validator.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 30  # Validator needs less time than transformer
  memory_size     = 256 # Validator needs less memory
  source_code_hash = data.archive_file.data_validator_zip.output_base64sha256
  
  environment {
    variables = {
      ENVIRONMENT = var.environment
      LOG_LEVEL   = var.log_level
      PROJECT_NAME = var.project_name
    }
  }
  
  # Advanced logging configuration
  logging_config {
    log_format            = "JSON"
    application_log_level = upper(var.log_level)
    system_log_level      = "WARN"
  }
  
  # Enable X-Ray tracing for better observability
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }
  
  tags = merge(local.common_tags, {
    Name = local.data_validator_function_name
    Type = "DataValidator"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_logging_policy,
    aws_cloudwatch_log_group.data_validator_logs
  ]
}

# =============================================================================
# Step Functions State Machine
# =============================================================================

# Step Functions state machine for API orchestration
resource "aws_sfn_state_machine" "api_orchestrator" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.stepfunctions_execution_role.arn
  type     = "STANDARD"  # Use STANDARD for better durability and audit trails
  
  definition = jsonencode({
    Comment = "Enterprise API Integration Orchestration"
    StartAt = "ValidateInput"
    States = {
      ValidateInput = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.data_validator.function_name
          "Payload.$" = "$"
        }
        ResultPath = "$.validation_result"
        Next       = "CheckValidation"
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException"]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "ValidationFailed"
            ResultPath  = "$.error"
          }
        ]
      }
      CheckValidation = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.validation_result.Payload.body"
            StringMatches = "*\"valid\":true*"
            Next          = "RouteRequest"
          }
        ]
        Default = "ValidationFailed"
      }
      RouteRequest = {
        Type = "Parallel"
        Branches = [
          {
            StartAt = "TransformForERP"
            States = {
              TransformForERP = {
                Type     = "Task"
                Resource = "arn:aws:states:::lambda:invoke"
                Parameters = {
                  FunctionName = aws_lambda_function.api_transformer.function_name
                  Payload = {
                    api_type    = "erp"
                    "payload.$" = "$"
                    target_url  = "https://example-erp.com/api/v1/process"
                  }
                }
                End = true
                Retry = [
                  {
                    ErrorEquals     = ["States.ALL"]
                    IntervalSeconds = 3
                    MaxAttempts     = 2
                    BackoffRate     = 2.0
                  }
                ]
              }
            }
          }
          {
            StartAt = "TransformForCRM"
            States = {
              TransformForCRM = {
                Type     = "Task"
                Resource = "arn:aws:states:::lambda:invoke"
                Parameters = {
                  FunctionName = aws_lambda_function.api_transformer.function_name
                  Payload = {
                    api_type    = "crm"
                    "payload.$" = "$"
                    target_url  = "https://example-crm.com/api/v2/entities"
                  }
                }
                End = true
                Retry = [
                  {
                    ErrorEquals     = ["States.ALL"]
                    IntervalSeconds = 3
                    MaxAttempts     = 2
                    BackoffRate     = 2.0
                  }
                ]
              }
            }
          }
        ]
        Next = "AggregateResults"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "ProcessingFailed"
            ResultPath  = "$.error"
          }
        ]
      }
      AggregateResults = {
        Type = "Pass"
        Parameters = {
          status          = "success"
          "results.$"     = "$"
          "timestamp.$"   = "$$.State.EnteredTime"
          "execution_arn.$" = "$$.Execution.Name"
        }
        End = true
      }
      ValidationFailed = {
        Type = "Pass"
        Parameters = {
          status        = "validation_failed"
          "errors.$"    = "$.validation_result.Payload.errors"
          "timestamp.$" = "$$.State.EnteredTime"
        }
        End = true
      }
      ProcessingFailed = {
        Type = "Pass"
        Parameters = {
          status        = "processing_failed"
          "error.$"     = "$.error"
          "timestamp.$" = "$$.State.EnteredTime"
        }
        End = true
      }
    }
  })
  
  # Enable logging for detailed execution history
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.stepfunctions_logs.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }
  
  # Enable X-Ray tracing for distributed tracing
  tracing_configuration {
    enabled = var.enable_xray_tracing
  }
  
  tags = merge(local.common_tags, {
    Name = local.state_machine_name
    Type = "APIOrchestrator"
  })
  
  depends_on = [
    aws_iam_role_policy.stepfunctions_lambda_policy,
    aws_iam_role_policy.stepfunctions_logging_policy,
    aws_cloudwatch_log_group.stepfunctions_logs
  ]
}

# =============================================================================
# API Gateway Configuration
# =============================================================================

# REST API Gateway
resource "aws_api_gateway_rest_api" "enterprise_integration" {
  name        = local.api_gateway_name
  description = "Enterprise API Integration with AgentCore Gateway"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  # Enable request validation and compression
  api_key_source               = "HEADER"
  disable_execute_api_endpoint = false
  
  tags = merge(local.common_tags, {
    Name = local.api_gateway_name
  })
}

# API Gateway resource for /integrate endpoint
resource "aws_api_gateway_resource" "integrate" {
  rest_api_id = aws_api_gateway_rest_api.enterprise_integration.id
  parent_id   = aws_api_gateway_rest_api.enterprise_integration.root_resource_id
  path_part   = "integrate"
}

# POST method for the /integrate endpoint
resource "aws_api_gateway_method" "integrate_post" {
  rest_api_id   = aws_api_gateway_rest_api.enterprise_integration.id
  resource_id   = aws_api_gateway_resource.integrate.id
  http_method   = "POST"
  authorization = "NONE"
  
  # Enable request validation
  request_validator_id = aws_api_gateway_request_validator.integration_validator.id
  
  request_models = {
    "application/json" = aws_api_gateway_model.integration_request.name
  }
}

# Request validator for input validation
resource "aws_api_gateway_request_validator" "integration_validator" {
  name                        = "${local.api_gateway_name}-validator"
  rest_api_id                = aws_api_gateway_rest_api.enterprise_integration.id
  validate_request_body      = true
  validate_request_parameters = true
}

# Request model for validation
resource "aws_api_gateway_model" "integration_request" {
  rest_api_id  = aws_api_gateway_rest_api.enterprise_integration.id
  name         = "IntegrationRequest"
  content_type = "application/json"
  
  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "Integration Request Schema"
    type      = "object"
    properties = {
      id = {
        type        = "string"
        description = "Unique request identifier"
      }
      type = {
        type        = "string"
        enum        = ["erp", "crm", "inventory"]
        description = "Target system type"
      }
      data = {
        type        = "object"
        description = "Request payload data"
        properties = {
          amount = {
            type        = "number"
            description = "Transaction amount (for financial data)"
          }
          email = {
            type        = "string"
            description = "Email address (for customer data)"
          }
        }
      }
      validation_type = {
        type        = "string"
        enum        = ["standard", "financial", "customer"]
        description = "Validation rules to apply"
      }
    }
    required = ["id", "type", "data"]
  })
}

# Integration with Step Functions
resource "aws_api_gateway_integration" "stepfunctions_integration" {
  rest_api_id = aws_api_gateway_rest_api.enterprise_integration.id
  resource_id = aws_api_gateway_resource.integrate.id
  http_method = aws_api_gateway_method.integrate_post.http_method
  
  integration_http_method = "POST"
  type                   = "AWS"
  uri                    = "arn:aws:apigateway:${data.aws_region.current.name}:states:action/StartExecution"
  credentials            = aws_iam_role.apigateway_stepfunctions_role.arn
  
  # Request template to transform API Gateway request to Step Functions format
  request_templates = {
    "application/json" = jsonencode({
      input          = "$util.escapeJavaScript($input.body)"
      stateMachineArn = aws_sfn_state_machine.api_orchestrator.arn
    })
  }
  
  # Timeout configuration
  timeout_milliseconds = 29000
}

# Method response configuration
resource "aws_api_gateway_method_response" "integrate_200" {
  rest_api_id = aws_api_gateway_rest_api.enterprise_integration.id
  resource_id = aws_api_gateway_resource.integrate.id
  http_method = aws_api_gateway_method.integrate_post.http_method
  status_code = "200"
  
  response_models = {
    "application/json" = "Empty"
  }
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Method response for errors
resource "aws_api_gateway_method_response" "integrate_400" {
  rest_api_id = aws_api_gateway_rest_api.enterprise_integration.id
  resource_id = aws_api_gateway_resource.integrate.id
  http_method = aws_api_gateway_method.integrate_post.http_method
  status_code = "400"
  
  response_models = {
    "application/json" = "Error"
  }
}

# Integration response configuration
resource "aws_api_gateway_integration_response" "integrate_200" {
  rest_api_id = aws_api_gateway_rest_api.enterprise_integration.id
  resource_id = aws_api_gateway_resource.integrate.id
  http_method = aws_api_gateway_method.integrate_post.http_method
  status_code = aws_api_gateway_method_response.integrate_200.status_code
  
  response_templates = {
    "application/json" = jsonencode({
      executionArn = "$input.path('$.executionArn')"
      startDate    = "$input.path('$.startDate')"
      status       = "STARTED"
    })
  }
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
  
  depends_on = [aws_api_gateway_integration.stepfunctions_integration]
}

# Integration response for errors
resource "aws_api_gateway_integration_response" "integrate_400" {
  rest_api_id       = aws_api_gateway_rest_api.enterprise_integration.id
  resource_id       = aws_api_gateway_resource.integrate.id
  http_method       = aws_api_gateway_method.integrate_post.http_method
  status_code       = aws_api_gateway_method_response.integrate_400.status_code
  selection_pattern = "4\\d{2}"
  
  response_templates = {
    "application/json" = jsonencode({
      error   = "Bad Request"
      message = "$input.path('$.errorMessage')"
    })
  }
  
  depends_on = [aws_api_gateway_integration.stepfunctions_integration]
}

# CORS configuration for OPTIONS method
resource "aws_api_gateway_method" "integrate_options" {
  rest_api_id   = aws_api_gateway_rest_api.enterprise_integration.id
  resource_id   = aws_api_gateway_resource.integrate.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integrate_options" {
  rest_api_id = aws_api_gateway_rest_api.enterprise_integration.id
  resource_id = aws_api_gateway_resource.integrate.id
  http_method = aws_api_gateway_method.integrate_options.http_method
  type        = "MOCK"
  
  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_method_response" "integrate_options" {
  rest_api_id = aws_api_gateway_rest_api.enterprise_integration.id
  resource_id = aws_api_gateway_resource.integrate.id
  http_method = aws_api_gateway_method.integrate_options.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "integrate_options" {
  rest_api_id = aws_api_gateway_rest_api.enterprise_integration.id
  resource_id = aws_api_gateway_resource.integrate.id
  http_method = aws_api_gateway_method.integrate_options.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  
  depends_on = [aws_api_gateway_integration.integrate_options]
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "production" {
  rest_api_id = aws_api_gateway_rest_api.enterprise_integration.id
  stage_name  = var.api_stage_name
  description = "Production deployment of enterprise API integration"
  
  # Force redeployment when integration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.integrate.id,
      aws_api_gateway_method.integrate_post.id,
      aws_api_gateway_integration.stepfunctions_integration.id,
      aws_api_gateway_method_response.integrate_200.id,
      aws_api_gateway_integration_response.integrate_200.id,
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
  
  depends_on = [
    aws_api_gateway_method.integrate_post,
    aws_api_gateway_integration.stepfunctions_integration,
    aws_api_gateway_method_response.integrate_200,
    aws_api_gateway_integration_response.integrate_200,
    aws_api_gateway_method.integrate_options,
    aws_api_gateway_integration.integrate_options,
    aws_api_gateway_integration_response.integrate_options
  ]
}

# API Gateway stage configuration
resource "aws_api_gateway_stage" "production" {
  deployment_id = aws_api_gateway_deployment.production.id
  rest_api_id   = aws_api_gateway_rest_api.enterprise_integration.id
  stage_name    = var.api_stage_name
  
  # Enable CloudWatch metrics and logging
  xray_tracing_enabled = var.enable_xray_tracing
  
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
      responseTime   = "$context.responseTime"
      error          = "$context.error.message"
      integrationError = "$context.integrationErrorMessage"
    })
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.api_gateway_name}-${var.api_stage_name}"
  })
  
  depends_on = [aws_cloudwatch_log_group.api_gateway_logs]
}

# CloudWatch log group for API Gateway access logs
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${local.api_gateway_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.api_gateway_name}-access-logs"
  })
}

# =============================================================================
# OpenAPI Specification for AgentCore Gateway Integration
# =============================================================================

# Generate OpenAPI specification for external consumption
resource "local_file" "openapi_spec" {
  filename = "${path.module}/generated/enterprise-api-spec.json"
  
  content = jsonencode({
    openapi = "3.0.3"
    info = {
      title       = "Enterprise API Integration"
      version     = "1.0.0"
      description = "Unified API for enterprise system integration with AgentCore Gateway"
    }
    servers = [
      {
        url         = "https://${aws_api_gateway_rest_api.enterprise_integration.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}"
        description = "Production API Gateway endpoint"
      }
    ]
    paths = {
      "/integrate" = {
        post = {
          summary     = "Process enterprise integration request"
          operationId = "processIntegration"
          description = "Submit data for processing through enterprise API integration workflow"
          requestBody = {
            required = true
            content = {
              "application/json" = {
                schema = {
                  type = "object"
                  properties = {
                    id = {
                      type        = "string"
                      description = "Unique request identifier"
                    }
                    type = {
                      type        = "string"
                      enum        = ["erp", "crm", "inventory"]
                      description = "Target system type"
                    }
                    data = {
                      type        = "object"
                      description = "Request payload data"
                      properties = {
                        amount = {
                          type        = "number"
                          description = "Transaction amount (for financial data)"
                        }
                        email = {
                          type        = "string"
                          description = "Email address (for customer data)"
                        }
                      }
                    }
                    validation_type = {
                      type        = "string"
                      enum        = ["standard", "financial", "customer"]
                      description = "Validation rules to apply"
                    }
                  }
                  required = ["id", "type", "data"]
                }
              }
            }
          }
          responses = {
            "200" = {
              description = "Integration request processed successfully"
              content = {
                "application/json" = {
                  schema = {
                    type = "object"
                    properties = {
                      executionArn = {
                        type        = "string"
                        description = "Step Functions execution ARN"
                      }
                      status = {
                        type        = "string"
                        description = "Execution status"
                      }
                      startDate = {
                        type        = "string"
                        description = "Execution start timestamp"
                      }
                    }
                  }
                }
              }
            }
            "400" = {
              description = "Invalid request format"
            }
            "500" = {
              description = "Internal server error"
            }
          }
        }
      }
    }
  })
}