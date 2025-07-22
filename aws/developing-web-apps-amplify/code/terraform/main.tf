# Main Terraform configuration for serverless web applications with Amplify and Lambda
# This file creates all the infrastructure resources needed for the recipe

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention for all resources
  name_prefix = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "serverless-web-applications-amplify-lambda"
    ManagedBy   = "terraform"
  })
}

# Data source to get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

###########################################
# DynamoDB Table for Todo Storage
###########################################

resource "aws_dynamodb_table" "todos" {
  name           = "${local.name_prefix}-todos"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"

  # Only set capacity if using PROVISIONED billing mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "id"
    type = "S"
  }

  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption using AWS managed key
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-todos"
    Type = "DynamoDB"
  })
}

###########################################
# Cognito User Pool for Authentication
###########################################

resource "aws_cognito_user_pool" "users" {
  name = "${local.name_prefix}-users"

  # User pool policies
  password_policy {
    minimum_length    = var.cognito_password_policy.minimum_length
    require_lowercase = var.cognito_password_policy.require_lowercase
    require_numbers   = var.cognito_password_policy.require_numbers
    require_symbols   = var.cognito_password_policy.require_symbols
    require_uppercase = var.cognito_password_policy.require_uppercase
  }

  # MFA configuration
  mfa_configuration = var.cognito_mfa_configuration

  # Account recovery settings
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Auto-verified attributes
  auto_verified_attributes = ["email"]

  # User attributes
  schema {
    attribute_data_type = "String"
    name               = "email"
    required           = true
    mutable            = true
  }

  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Admin create user configuration
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-users"
    Type = "CognitoUserPool"
  })
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "web_client" {
  name         = "${local.name_prefix}-web-client"
  user_pool_id = aws_cognito_user_pool.users.id

  # OAuth configuration for web applications
  generate_secret = false
  
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  # Supported identity providers
  supported_identity_providers = ["COGNITO"]

  # OAuth settings
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  
  # Callback URLs for localhost development and Amplify hosting
  callback_urls = [
    "http://localhost:3000",
    "https://*.amplifyapp.com"
  ]
  
  logout_urls = [
    "http://localhost:3000",
    "https://*.amplifyapp.com"
  ]

  # Token validity periods
  access_token_validity  = 60  # 1 hour
  id_token_validity     = 60  # 1 hour
  refresh_token_validity = 30  # 30 days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

# Cognito Identity Pool for AWS resource access
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${local.name_prefix}-identity-pool"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.web_client.id
    provider_name           = aws_cognito_user_pool.users.endpoint
    server_side_token_check = false
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-identity-pool"
    Type = "CognitoIdentityPool"
  })
}

###########################################
# IAM Roles for Lambda Functions
###########################################

# Lambda execution role
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-execution-role"

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
    Type = "IAMRole"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach X-Ray tracing policy if enabled
resource "aws_iam_role_policy_attachment" "lambda_xray_execution" {
  count      = var.enable_x_ray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# DynamoDB access policy for Lambda
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${local.name_prefix}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_execution_role.id

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
        Resource = aws_dynamodb_table.todos.arn
      }
    ]
  })
}

###########################################
# Lambda Function for API Backend
###########################################

# Create ZIP archive for Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda-function.zip"
  
  source {
    content = templatefile("${path.module}/lambda-function.js", {
      table_name = aws_dynamodb_table.todos.name
    })
    filename = "index.js"
  }
}

# Lambda function for Todo API
resource "aws_lambda_function" "todo_api" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-todo-api"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Environment variables
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todos.name
      CORS_ORIGIN        = join(",", var.cors_allowed_origins)
    }
  }

  # Enable X-Ray tracing if configured
  tracing_config {
    mode = var.enable_x_ray_tracing ? "Active" : "PassThrough"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_dynamodb_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-todo-api"
    Type = "LambdaFunction"
  })
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-todo-api"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-logs"
    Type = "CloudWatchLogGroup"
  })
}

###########################################
# API Gateway for REST API
###########################################

# API Gateway REST API
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${local.name_prefix}-todo-api"
  description = "REST API for Todo application built with Amplify and Lambda"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  # Binary media types for file uploads (if needed)
  binary_media_types = ["multipart/form-data"]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-todo-api"
    Type = "APIGateway"
  })
}

# API Gateway resource for /todos
resource "aws_api_gateway_resource" "todos" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "todos"
}

# API Gateway resource for /todos/{id}
resource "aws_api_gateway_resource" "todo_id" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_resource.todos.id
  path_part   = "{id}"
}

# CORS support for /todos resource
resource "aws_api_gateway_method" "todos_options" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.todos.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "todos_options" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todos.id
  http_method = aws_api_gateway_method.todos_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "todos_options" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todos.id
  http_method = aws_api_gateway_method.todos_options.http_method
  status_code = "200"

  response_headers = {
    "Access-Control-Allow-Headers" = true
    "Access-Control-Allow-Methods" = true
    "Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "todos_options" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todos.id
  http_method = aws_api_gateway_method.todos_options.http_method
  status_code = aws_api_gateway_method_response.todos_options.status_code

  response_headers = {
    "Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "Access-Control-Allow-Origin"  = "'${join(",", var.cors_allowed_origins)}'"
  }
}

# GET method for /todos
resource "aws_api_gateway_method" "todos_get" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.todos.id
  http_method   = "GET"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "todos_get" {
  rest_api_id             = aws_api_gateway_rest_api.todo_api.id
  resource_id             = aws_api_gateway_resource.todos.id
  http_method             = aws_api_gateway_method.todos_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.todo_api.invoke_arn
}

# POST method for /todos
resource "aws_api_gateway_method" "todos_post" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.todos.id
  http_method   = "POST"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "todos_post" {
  rest_api_id             = aws_api_gateway_rest_api.todo_api.id
  resource_id             = aws_api_gateway_resource.todos.id
  http_method             = aws_api_gateway_method.todos_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.todo_api.invoke_arn
}

# PUT method for /todos/{id}
resource "aws_api_gateway_method" "todo_put" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.todo_id.id
  http_method   = "PUT"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "todo_put" {
  rest_api_id             = aws_api_gateway_rest_api.todo_api.id
  resource_id             = aws_api_gateway_resource.todo_id.id
  http_method             = aws_api_gateway_method.todo_put.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.todo_api.invoke_arn
}

# DELETE method for /todos/{id}
resource "aws_api_gateway_method" "todo_delete" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.todo_id.id
  http_method   = "DELETE"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "todo_delete" {
  rest_api_id             = aws_api_gateway_rest_api.todo_api.id
  resource_id             = aws_api_gateway_resource.todo_id.id
  http_method             = aws_api_gateway_method.todo_delete.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.todo_api.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.todo_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "todo_api" {
  depends_on = [
    aws_api_gateway_method.todos_get,
    aws_api_gateway_method.todos_post,
    aws_api_gateway_method.todo_put,
    aws_api_gateway_method.todo_delete,
    aws_api_gateway_integration.todos_get,
    aws_api_gateway_integration.todos_post,
    aws_api_gateway_integration.todo_put,
    aws_api_gateway_integration.todo_delete
  ]

  rest_api_id = aws_api_gateway_rest_api.todo_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.todos.id,
      aws_api_gateway_resource.todo_id.id,
      aws_api_gateway_method.todos_get.id,
      aws_api_gateway_method.todos_post.id,
      aws_api_gateway_method.todo_put.id,
      aws_api_gateway_method.todo_delete.id,
      aws_api_gateway_integration.todos_get.id,
      aws_api_gateway_integration.todos_post.id,
      aws_api_gateway_integration.todo_put.id,
      aws_api_gateway_integration.todo_delete.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "todo_api" {
  deployment_id = aws_api_gateway_deployment.todo_api.id
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  stage_name    = var.api_gateway_stage_name

  # Enable caching if configured
  cache_cluster_enabled = var.enable_api_caching
  cache_cluster_size    = var.enable_api_caching ? "0.5" : null

  # Cache settings
  dynamic "cache_key_parameters" {
    for_each = var.enable_api_caching ? ["*"] : []
    content {
      # Cache all query parameters
    }
  }

  # Method settings for caching and logging
  method_settings {
    method_path = "*/*"
    
    # Caching settings
    caching_enabled      = var.enable_api_caching
    cache_ttl_in_seconds = var.enable_api_caching ? var.api_cache_ttl : null
    cache_data_encrypted = var.enable_api_caching ? true : null
    
    # Logging settings
    logging_level   = var.enable_cloudwatch_logs ? "INFO" : "OFF"
    data_trace_enabled = var.enable_cloudwatch_logs
    metrics_enabled    = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-stage"
    Type = "APIGatewayStage"
  })
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.todo_api.id}/${var.api_gateway_stage_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-gateway-logs"
    Type = "CloudWatchLogGroup"
  })
}

###########################################
# AWS Amplify App for Frontend Hosting
###########################################

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name       = "${local.name_prefix}-app"
  repository = var.amplify_repository != "" ? var.amplify_repository : null

  # Build settings for React application
  build_spec = yamlencode({
    version = 1
    applications = [{
      frontend = {
        phases = {
          preBuild = {
            commands = [
              "npm ci"
            ]
          }
          build = {
            commands = [
              "npm run build"
            ]
          }
        }
        artifacts = {
          baseDirectory = "build"
          files = ["**/*"]
        }
        cache = {
          paths = ["node_modules/**/*"]
        }
      }
    }]
  })

  # Environment variables for React app
  environment_variables = {
    REACT_APP_REGION            = data.aws_region.current.name
    REACT_APP_USER_POOL_ID      = aws_cognito_user_pool.users.id
    REACT_APP_USER_POOL_WEB_CLIENT_ID = aws_cognito_user_pool_client.web_client.id
    REACT_APP_IDENTITY_POOL_ID  = aws_cognito_identity_pool.main.id
    REACT_APP_API_ENDPOINT      = aws_api_gateway_stage.todo_api.invoke_url
  }

  # Enable auto branch creation and deletion
  enable_auto_branch_creation = false
  enable_auto_branch_deletion = false
  enable_branch_auto_build    = var.amplify_repository != "" ? true : false

  # Custom rules for SPA routing
  custom_rule {
    source = "/<*>"
    status = "404"
    target = "/index.html"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-amplify-app"
    Type = "AmplifyApp"
  })
}

# Amplify Branch
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.amplify_branch

  # Frontend framework detection
  framework = "React"
  stage     = var.environment == "prod" ? "PRODUCTION" : "DEVELOPMENT"

  # Environment variables specific to this branch
  environment_variables = {
    USER_BRANCH = var.amplify_branch
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-amplify-branch-${var.amplify_branch}"
    Type = "AmplifyBranch"
  })
}

###########################################
# IAM Roles for Cognito Identity Pool
###########################################

# Authenticated users role
resource "aws_iam_role" "cognito_authenticated_role" {
  name = "${local.name_prefix}-cognito-authenticated-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cognito-authenticated-role"
    Type = "IAMRole"
  })
}

# Policy for authenticated users to access API Gateway
resource "aws_iam_role_policy" "cognito_authenticated_policy" {
  name = "${local.name_prefix}-cognito-authenticated-policy"
  role = aws_iam_role.cognito_authenticated_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "execute-api:Invoke"
        ]
        Resource = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*"
      }
    ]
  })
}

# Attach the roles to the identity pool
resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    "authenticated" = aws_iam_role.cognito_authenticated_role.arn
  }
}

###########################################
# CloudWatch Dashboard for Monitoring
###########################################

resource "aws_cloudwatch_dashboard" "todo_app_dashboard" {
  dashboard_name = "${local.name_prefix}-dashboard"

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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.todo_api.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.todo_api.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.todo_api.function_name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Lambda Function Metrics"
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
            ["AWS/ApiGateway", "Count", "ApiName", aws_api_gateway_rest_api.todo_api.name],
            ["AWS/ApiGateway", "Latency", "ApiName", aws_api_gateway_rest_api.todo_api.name],
            ["AWS/ApiGateway", "4XXError", "ApiName", aws_api_gateway_rest_api.todo_api.name],
            ["AWS/ApiGateway", "5XXError", "ApiName", aws_api_gateway_rest_api.todo_api.name]
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
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.todos.name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.todos.name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "DynamoDB Metrics"
          period  = 300
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dashboard"
    Type = "CloudWatchDashboard"
  })
}