# Data Sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_password" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Common resource naming
  resource_suffix = random_password.suffix.result
  dsql_cluster_name = var.dsql_cluster_name != "" ? var.dsql_cluster_name : "${var.project_name}-cluster-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(var.resource_tags, {
    Environment   = var.environment
    Project      = var.project_name
    ManagedBy    = "terraform"
    CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
  })
}

# ================================
# Aurora DSQL Cluster
# ================================

# Aurora DSQL cluster - serverless distributed SQL database
resource "aws_dsql_cluster" "ecommerce_cluster" {
  cluster_name             = local.dsql_cluster_name
  deletion_protection      = var.enable_deletion_protection

  tags = merge(local.common_tags, {
    Name        = local.dsql_cluster_name
    Service     = "aurora-dsql"
    Description = "Global e-commerce Aurora DSQL cluster"
  })
}

# ================================
# IAM Roles and Policies
# ================================

# IAM role for Lambda functions to access Aurora DSQL
resource "aws_iam_role" "lambda_execution_role" {
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
    Service     = "iam"
    Description = "IAM role for e-commerce Lambda functions"
  })
}

# Basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Aurora DSQL access
resource "aws_iam_policy" "aurora_dsql_access" {
  name        = "${var.project_name}-aurora-dsql-access-${local.resource_suffix}"
  description = "Policy for Aurora DSQL access from Lambda functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dsql:DbConnect",
          "dsql:DbConnectAdmin"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-aurora-dsql-access-${local.resource_suffix}"
    Service     = "iam"
    Description = "Aurora DSQL access policy"
  })
}

# Attach Aurora DSQL policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_aurora_dsql_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.aurora_dsql_access.arn
}

# ================================
# CloudWatch Log Groups
# ================================

# Log group for product Lambda function
resource "aws_cloudwatch_log_group" "products_lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-products-${local.resource_suffix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-products-logs"
    Service     = "cloudwatch"
    Description = "Log group for products Lambda function"
  })
}

# Log group for orders Lambda function
resource "aws_cloudwatch_log_group" "orders_lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-orders-${local.resource_suffix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-orders-logs"
    Service     = "cloudwatch"
    Description = "Log group for orders Lambda function"
  })
}

# Log group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_api_gateway_logging ? 1 : 0
  name              = "/aws/apigateway/${var.project_name}-api-${local.resource_suffix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-api-logs"
    Service     = "cloudwatch"
    Description = "Log group for API Gateway"
  })
}

# ================================
# Lambda Functions
# ================================

# Lambda function for product operations
resource "aws_lambda_function" "products_handler" {
  filename         = "${path.module}/lambda_functions/products_handler.zip"
  function_name    = "${var.project_name}-products-${local.resource_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "products_handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      DSQL_CLUSTER_NAME = aws_dsql_cluster.ecommerce_cluster.cluster_name
      LOG_LEVEL        = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_aurora_dsql_access,
    aws_cloudwatch_log_group.products_lambda_logs,
  ]

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-products-function"
    Service     = "lambda"
    Description = "Lambda function for product operations"
  })
}

# Lambda function for order processing
resource "aws_lambda_function" "orders_handler" {
  filename         = "${path.module}/lambda_functions/orders_handler.zip"
  function_name    = "${var.project_name}-orders-${local.resource_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "orders_handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      DSQL_CLUSTER_NAME = aws_dsql_cluster.ecommerce_cluster.cluster_name
      LOG_LEVEL        = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_aurora_dsql_access,
    aws_cloudwatch_log_group.orders_lambda_logs,
  ]

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-orders-function"
    Service     = "lambda"
    Description = "Lambda function for order processing"
  })
}

# ================================
# API Gateway
# ================================

# REST API Gateway
resource "aws_api_gateway_rest_api" "ecommerce_api" {
  name        = "${var.project_name}-api-${local.resource_suffix}"
  description = "E-commerce API with Aurora DSQL backend"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-api"
    Service     = "apigateway"
    Description = "REST API for e-commerce platform"
  })
}

# Products resource
resource "aws_api_gateway_resource" "products_resource" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce_api.id
  parent_id   = aws_api_gateway_rest_api.ecommerce_api.root_resource_id
  path_part   = "products"
}

# Orders resource
resource "aws_api_gateway_resource" "orders_resource" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce_api.id
  parent_id   = aws_api_gateway_rest_api.ecommerce_api.root_resource_id
  path_part   = "orders"
}

# Products GET method
resource "aws_api_gateway_method" "products_get" {
  rest_api_id   = aws_api_gateway_rest_api.ecommerce_api.id
  resource_id   = aws_api_gateway_resource.products_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Products POST method
resource "aws_api_gateway_method" "products_post" {
  rest_api_id   = aws_api_gateway_rest_api.ecommerce_api.id
  resource_id   = aws_api_gateway_resource.products_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# Orders POST method
resource "aws_api_gateway_method" "orders_post" {
  rest_api_id   = aws_api_gateway_rest_api.ecommerce_api.id
  resource_id   = aws_api_gateway_resource.orders_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# Lambda integrations for products
resource "aws_api_gateway_integration" "products_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce_api.id
  resource_id = aws_api_gateway_resource.products_resource.id
  http_method = aws_api_gateway_method.products_get.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.products_handler.invoke_arn
}

resource "aws_api_gateway_integration" "products_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce_api.id
  resource_id = aws_api_gateway_resource.products_resource.id
  http_method = aws_api_gateway_method.products_post.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.products_handler.invoke_arn
}

# Lambda integration for orders
resource "aws_api_gateway_integration" "orders_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce_api.id
  resource_id = aws_api_gateway_resource.orders_resource.id
  http_method = aws_api_gateway_method.orders_post.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.orders_handler.invoke_arn
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "products_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.products_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.ecommerce_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "orders_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orders_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.ecommerce_api.execution_arn}/*/*"
}

# CORS configuration for products resource
resource "aws_api_gateway_method" "products_options" {
  rest_api_id   = aws_api_gateway_rest_api.ecommerce_api.id
  resource_id   = aws_api_gateway_resource.products_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "products_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce_api.id
  resource_id = aws_api_gateway_resource.products_resource.id
  http_method = aws_api_gateway_method.products_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_method_response" "products_options_200" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce_api.id
  resource_id = aws_api_gateway_resource.products_resource.id
  http_method = aws_api_gateway_method.products_options.http_method
  status_code = "200"

  response_headers = {
    "Access-Control-Allow-Headers" = true
    "Access-Control-Allow-Methods" = true
    "Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "products_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce_api.id
  resource_id = aws_api_gateway_resource.products_resource.id
  http_method = aws_api_gateway_method.products_options.http_method
  status_code = aws_api_gateway_method_response.products_options_200.status_code

  response_headers = {
    "Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "Access-Control-Allow-Origin"  = "'*'"
  }
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "ecommerce_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce_api.id

  depends_on = [
    aws_api_gateway_method.products_get,
    aws_api_gateway_method.products_post,
    aws_api_gateway_method.products_options,
    aws_api_gateway_method.orders_post,
    aws_api_gateway_integration.products_get_integration,
    aws_api_gateway_integration.products_post_integration,
    aws_api_gateway_integration.products_options_integration,
    aws_api_gateway_integration.orders_post_integration,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "ecommerce_api_stage" {
  deployment_id        = aws_api_gateway_deployment.ecommerce_api_deployment.id
  rest_api_id         = aws_api_gateway_rest_api.ecommerce_api.id
  stage_name          = var.api_gateway_stage_name
  xray_tracing_enabled = var.enable_detailed_monitoring

  # Throttling settings
  throttle_settings {
    rate_limit  = var.api_throttle_rate_limit
    burst_limit = var.api_throttle_burst_limit
  }

  # Enable access logging if configured
  dynamic "access_log_settings" {
    for_each = var.enable_api_gateway_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway_logs[0].arn
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
      })
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-api-stage"
    Service     = "apigateway"
    Description = "API Gateway stage for e-commerce platform"
  })
}

# ================================
# CloudFront Distribution
# ================================

# CloudFront distribution for global API delivery
resource "aws_cloudfront_distribution" "ecommerce_api_distribution" {
  origin {
    domain_name = "${aws_api_gateway_rest_api.ecommerce_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com"
    origin_id   = "api-origin"
    origin_path = "/${var.api_gateway_stage_name}"

    custom_origin_config {
      http_port              = 443
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled = true
  comment = "E-commerce API global distribution"

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = "api-origin"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type", "Accept", "Origin"]

      cookies {
        forward = "all"
      }
    }

    min_ttl     = var.cloudfront_min_ttl
    default_ttl = var.cloudfront_default_ttl
    max_ttl     = var.cloudfront_max_ttl
  }

  price_class = var.cloudfront_price_class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-api-distribution"
    Service     = "cloudfront"
    Description = "CloudFront distribution for global e-commerce API"
  })
}

# ================================
# Database Initialization
# ================================

# Null resource for database schema initialization
resource "null_resource" "database_initialization" {
  depends_on = [aws_dsql_cluster.ecommerce_cluster]

  provisioner "local-exec" {
    command = <<-EOF
      # Wait for cluster to be ready
      aws dsql wait cluster-available \
        --cluster-name ${aws_dsql_cluster.ecommerce_cluster.cluster_name} \
        --region ${data.aws_region.current.name}
      
      # Create database schema
      aws dsql execute-statement \
        --cluster-name ${aws_dsql_cluster.ecommerce_cluster.cluster_name} \
        --database ${var.initial_database_name} \
        --region ${data.aws_region.current.name} \
        --statement "$(cat ${path.module}/database_schema/ecommerce_schema.sql)"
    EOF
  }

  triggers = {
    cluster_id = aws_dsql_cluster.ecommerce_cluster.id
  }
}

# ================================
# CloudWatch Alarms (Optional)
# ================================

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "products_lambda_errors" {
  count               = var.enable_detailed_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-products-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors for products function"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.products_handler.function_name
  }

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-products-lambda-errors-alarm"
    Service     = "cloudwatch"
    Description = "CloudWatch alarm for products Lambda errors"
  })
}

resource "aws_cloudwatch_metric_alarm" "orders_lambda_errors" {
  count               = var.enable_detailed_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-orders-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors for orders function"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.orders_handler.function_name
  }

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-orders-lambda-errors-alarm"
    Service     = "cloudwatch"
    Description = "CloudWatch alarm for orders Lambda errors"
  })
}

# API Gateway 5XX errors alarm
resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx_errors" {
  count               = var.enable_detailed_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors API Gateway 5XX errors"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.ecommerce_api.name
    Stage   = aws_api_gateway_stage.ecommerce_api_stage.stage_name
  }

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-api-5xx-errors-alarm"
    Service     = "cloudwatch"
    Description = "CloudWatch alarm for API Gateway 5XX errors"
  })
}