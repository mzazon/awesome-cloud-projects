# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  suffix      = random_string.suffix.result
  
  # Resource names with unique suffixes
  node_id                = "eth-node-${local.suffix}"
  lambda_function_name   = "eth-contract-manager-${local.suffix}"
  api_name              = "ethereum-api-${local.suffix}"
  bucket_name           = "ethereum-artifacts-${data.aws_caller_identity.current.account_id}-${local.suffix}"
  
  # Availability zone for blockchain node
  blockchain_az = var.blockchain_node_availability_zone != "" ? var.blockchain_node_availability_zone : "${data.aws_region.current.name}a"
}

#------------------------------------------------------------------------------
# S3 Bucket for Contract Artifacts
#------------------------------------------------------------------------------

# S3 bucket for storing smart contract artifacts
resource "aws_s3_bucket" "contract_artifacts" {
  bucket = local.bucket_name
  
  tags = merge(
    {
      Name        = local.bucket_name
      Description = "Storage for Ethereum smart contract artifacts"
    },
    var.additional_tags
  )
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "contract_artifacts" {
  bucket = aws_s3_bucket.contract_artifacts.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "contract_artifacts" {
  count  = var.s3_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.contract_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "contract_artifacts" {
  bucket = aws_s3_bucket.contract_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#------------------------------------------------------------------------------
# IAM Roles and Policies
#------------------------------------------------------------------------------

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.lambda_function_name}-role"

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

  tags = merge(
    {
      Name        = "${local.lambda_function_name}-role"
      Description = "IAM role for Ethereum contract manager Lambda function"
    },
    var.additional_tags
  )
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom IAM policy for blockchain and S3 access
resource "aws_iam_policy" "lambda_blockchain_policy" {
  name        = "${local.lambda_function_name}-blockchain-policy"
  description = "Policy for Lambda function to access Managed Blockchain and S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "managedblockchain:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.contract_artifacts.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.contract_artifacts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/ethereum/${local.lambda_function_name}/*"
        ]
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

  tags = merge(
    {
      Name        = "${local.lambda_function_name}-blockchain-policy"
      Description = "Policy for blockchain and S3 access"
    },
    var.additional_tags
  )
}

# Attach blockchain policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_blockchain" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_blockchain_policy.arn
}

#------------------------------------------------------------------------------
# Managed Blockchain Node
#------------------------------------------------------------------------------

# Managed Blockchain Ethereum node
resource "aws_managedblockchain_node" "ethereum_node" {
  network_id = var.ethereum_network
  
  node_configuration {
    instance_type     = var.blockchain_node_instance_type
    availability_zone = local.blockchain_az
  }

  tags = merge(
    {
      Name        = local.node_id
      Description = "Ethereum node for smart contract interactions"
    },
    var.additional_tags
  )
}

#------------------------------------------------------------------------------
# Systems Manager Parameters
#------------------------------------------------------------------------------

# Store node HTTP endpoint in Parameter Store
resource "aws_ssm_parameter" "node_http_endpoint" {
  name  = "/ethereum/${local.lambda_function_name}/http-endpoint"
  type  = "String"
  value = aws_managedblockchain_node.ethereum_node.http_endpoint

  tags = merge(
    {
      Name        = "/ethereum/${local.lambda_function_name}/http-endpoint"
      Description = "HTTP endpoint for Ethereum node"
    },
    var.additional_tags
  )
}

# Store node WebSocket endpoint in Parameter Store
resource "aws_ssm_parameter" "node_ws_endpoint" {
  name  = "/ethereum/${local.lambda_function_name}/ws-endpoint"
  type  = "String"
  value = aws_managedblockchain_node.ethereum_node.websocket_endpoint

  tags = merge(
    {
      Name        = "/ethereum/${local.lambda_function_name}/ws-endpoint"
      Description = "WebSocket endpoint for Ethereum node"
    },
    var.additional_tags
  )
}

#------------------------------------------------------------------------------
# Lambda Function
#------------------------------------------------------------------------------

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/lambda-deployment.zip"
  
  source {
    content = templatefile("${path.module}/lambda/index.js", {
      bucket_name     = local.bucket_name
      function_name   = local.lambda_function_name
      aws_region      = data.aws_region.current.name
    })
    filename = "index.js"
  }
  
  source {
    content = templatefile("${path.module}/lambda/package.json", {
      function_name = local.lambda_function_name
    })
    filename = "package.json"
  }
  
  source {
    content = file("${path.module}/lambda/gas-optimizer.js")
    filename = "gas-optimizer.js"
  }
}

# Lambda function for contract management
resource "aws_lambda_function" "contract_manager" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME   = aws_s3_bucket.contract_artifacts.bucket
      FUNCTION_NAME = local.lambda_function_name
      AWS_REGION    = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_blockchain,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(
    {
      Name        = local.lambda_function_name
      Description = "Lambda function for Ethereum contract management"
    },
    var.additional_tags
  )
}

# CloudWatch log group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(
    {
      Name        = "/aws/lambda/${local.lambda_function_name}"
      Description = "CloudWatch log group for Lambda function"
    },
    var.additional_tags
  )
}

#------------------------------------------------------------------------------
# API Gateway
#------------------------------------------------------------------------------

# API Gateway REST API
resource "aws_api_gateway_rest_api" "ethereum_api" {
  name        = local.api_name
  description = "Ethereum Smart Contract API"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(
    {
      Name        = local.api_name
      Description = "REST API for Ethereum smart contract interactions"
    },
    var.additional_tags
  )
}

# API Gateway resource
resource "aws_api_gateway_resource" "ethereum_resource" {
  rest_api_id = aws_api_gateway_rest_api.ethereum_api.id
  parent_id   = aws_api_gateway_rest_api.ethereum_api.root_resource_id
  path_part   = "ethereum"
}

# API Gateway method
resource "aws_api_gateway_method" "ethereum_post" {
  rest_api_id   = aws_api_gateway_rest_api.ethereum_api.id
  resource_id   = aws_api_gateway_resource.ethereum_resource.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = var.enable_api_key_required
}

# API Gateway integration
resource "aws_api_gateway_integration" "ethereum_integration" {
  rest_api_id = aws_api_gateway_rest_api.ethereum_api.id
  resource_id = aws_api_gateway_resource.ethereum_resource.id
  http_method = aws_api_gateway_method.ethereum_post.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.contract_manager.invoke_arn
}

# CORS support - OPTIONS method
resource "aws_api_gateway_method" "ethereum_options" {
  rest_api_id   = aws_api_gateway_rest_api.ethereum_api.id
  resource_id   = aws_api_gateway_resource.ethereum_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# CORS integration
resource "aws_api_gateway_integration" "ethereum_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.ethereum_api.id
  resource_id = aws_api_gateway_resource.ethereum_resource.id
  http_method = aws_api_gateway_method.ethereum_options.http_method
  
  type = "MOCK"
  
  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

# CORS method response
resource "aws_api_gateway_method_response" "ethereum_options_response" {
  rest_api_id = aws_api_gateway_rest_api.ethereum_api.id
  resource_id = aws_api_gateway_resource.ethereum_resource.id
  http_method = aws_api_gateway_method.ethereum_options.http_method
  status_code = "200"
  
  response_headers = {
    "Access-Control-Allow-Headers" = true
    "Access-Control-Allow-Methods" = true
    "Access-Control-Allow-Origin"  = true
  }
}

# CORS integration response
resource "aws_api_gateway_integration_response" "ethereum_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.ethereum_api.id
  resource_id = aws_api_gateway_resource.ethereum_resource.id
  http_method = aws_api_gateway_method.ethereum_options.http_method
  status_code = aws_api_gateway_method_response.ethereum_options_response.status_code
  
  response_headers = {
    "Access-Control-Allow-Headers" = "'${join(",", var.cors_allowed_headers)}'"
    "Access-Control-Allow-Methods" = "'${join(",", var.cors_allowed_methods)}'"
    "Access-Control-Allow-Origin"  = "'${join(",", var.cors_allowed_origins)}'"
  }
}

# POST method response
resource "aws_api_gateway_method_response" "ethereum_post_response" {
  rest_api_id = aws_api_gateway_rest_api.ethereum_api.id
  resource_id = aws_api_gateway_resource.ethereum_resource.id
  http_method = aws_api_gateway_method.ethereum_post.http_method
  status_code = "200"
  
  response_headers = {
    "Access-Control-Allow-Origin" = true
  }
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contract_manager.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.ethereum_api.execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "ethereum_deployment" {
  depends_on = [
    aws_api_gateway_method.ethereum_post,
    aws_api_gateway_integration.ethereum_integration,
    aws_api_gateway_method.ethereum_options,
    aws_api_gateway_integration.ethereum_options_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.ethereum_api.id
  stage_name  = var.api_gateway_stage_name
}

# API Gateway stage settings
resource "aws_api_gateway_stage" "ethereum_stage" {
  deployment_id = aws_api_gateway_deployment.ethereum_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.ethereum_api.id
  stage_name    = var.api_gateway_stage_name
  
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
  })
  
  tags = merge(
    {
      Name        = "${local.api_name}-${var.api_gateway_stage_name}"
      Description = "API Gateway stage for Ethereum API"
    },
    var.additional_tags
  )
}

# API Gateway method settings for throttling
resource "aws_api_gateway_method_settings" "ethereum_settings" {
  rest_api_id = aws_api_gateway_rest_api.ethereum_api.id
  stage_name  = aws_api_gateway_stage.ethereum_stage.stage_name
  method_path = "*/*"
  
  settings {
    throttling_rate_limit  = var.api_throttle_rate_limit
    throttling_burst_limit = var.api_throttle_burst_limit
    logging_level          = "INFO"
    data_trace_enabled     = true
    metrics_enabled        = true
  }
}

# CloudWatch log group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${local.api_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(
    {
      Name        = "/aws/apigateway/${local.api_name}"
      Description = "CloudWatch log group for API Gateway"
    },
    var.additional_tags
  )
}

#------------------------------------------------------------------------------
# CloudWatch Monitoring
#------------------------------------------------------------------------------

# CloudWatch dashboard (optional)
resource "aws_cloudwatch_dashboard" "ethereum_dashboard" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "Ethereum-Blockchain-${local.suffix}"

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
            ["AWS/Lambda", "Duration", "FunctionName", local.lambda_function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Performance"
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
            ["AWS/ApiGateway", "Count", "ApiName", local.api_name],
            [".", "Latency", ".", "."],
            [".", "4XXError", ".", "."],
            [".", "5XXError", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "API Gateway Metrics"
        }
      }
    ]
  })
}

# CloudWatch alarm for Lambda errors (optional)
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.lambda_function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [] # Add SNS topic ARN for notifications if needed

  dimensions = {
    FunctionName = local.lambda_function_name
  }

  tags = merge(
    {
      Name        = "${local.lambda_function_name}-errors"
      Description = "CloudWatch alarm for Lambda function errors"
    },
    var.additional_tags
  )
}

# CloudWatch alarm for API Gateway errors (optional)
resource "aws_cloudwatch_metric_alarm" "api_gateway_errors" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.api_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors API Gateway 5XX errors"
  alarm_actions       = [] # Add SNS topic ARN for notifications if needed

  dimensions = {
    ApiName = local.api_name
  }

  tags = merge(
    {
      Name        = "${local.api_name}-errors"
      Description = "CloudWatch alarm for API Gateway errors"
    },
    var.additional_tags
  )
}