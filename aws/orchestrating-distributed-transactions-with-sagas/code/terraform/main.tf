# main.tf - Main infrastructure configuration for Saga Patterns with Step Functions

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  upper   = false
  special = false
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values for resource naming and configuration
locals {
  resource_suffix = random_string.suffix.result
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# ============================================================================
# DynamoDB Tables for Business Services
# ============================================================================

# Order Service DynamoDB Table
resource "aws_dynamodb_table" "orders" {
  name           = "saga-orders-${local.resource_suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "orderId"
  
  attribute {
    name = "orderId"
    type = "S"
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name = "saga-orders-${local.resource_suffix}"
    Purpose = "Order management for saga pattern"
  })
}

# Inventory Service DynamoDB Table
resource "aws_dynamodb_table" "inventory" {
  name           = "saga-inventory-${local.resource_suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "productId"
  
  attribute {
    name = "productId"
    type = "S"
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name = "saga-inventory-${local.resource_suffix}"
    Purpose = "Inventory management for saga pattern"
  })
}

# Payment Service DynamoDB Table
resource "aws_dynamodb_table" "payments" {
  name           = "saga-payments-${local.resource_suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "paymentId"
  
  attribute {
    name = "paymentId"
    type = "S"
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name = "saga-payments-${local.resource_suffix}"
    Purpose = "Payment management for saga pattern"
  })
}

# Populate initial inventory data
resource "aws_dynamodb_table_item" "inventory_items" {
  for_each = {
    for item in var.initial_inventory_data : item.product_id => item
  }
  
  table_name = aws_dynamodb_table.inventory.name
  hash_key   = aws_dynamodb_table.inventory.hash_key
  
  item = jsonencode({
    productId = {
      S = each.value.product_id
    }
    quantity = {
      N = tostring(each.value.quantity)
    }
    price = {
      N = tostring(each.value.price)
    }
    reserved = {
      N = "0"
    }
  })
  
  depends_on = [aws_dynamodb_table.inventory]
}

# ============================================================================
# SNS Topic for Notifications
# ============================================================================

resource "aws_sns_topic" "notifications" {
  name = "saga-notifications-${local.resource_suffix}"
  
  tags = merge(local.common_tags, {
    Name = "saga-notifications-${local.resource_suffix}"
    Purpose = "Notifications for saga pattern"
  })
}

# ============================================================================
# CloudWatch Log Groups
# ============================================================================

# Log group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/stepfunctions/saga-logs-${local.resource_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "saga-stepfunctions-logs"
    Purpose = "Step Functions logging for saga pattern"
  })
}

# Log groups for Lambda functions
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = toset([
    "order-service",
    "inventory-service", 
    "payment-service",
    "notification-service",
    "cancel-order",
    "revert-inventory",
    "refund-payment"
  ])
  
  name              = "/aws/lambda/saga-${each.key}-${local.resource_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "saga-${each.key}-logs"
    Purpose = "Lambda logging for saga pattern"
  })
}

# ============================================================================
# IAM Roles and Policies
# ============================================================================

# Lambda execution role
resource "aws_iam_role" "lambda_execution_role" {
  name = "saga-lambda-role-${local.resource_suffix}"
  
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
    Name = "saga-lambda-execution-role"
    Purpose = "Lambda execution role for saga pattern"
  })
}

# Lambda execution policy
resource "aws_iam_role_policy" "lambda_execution_policy" {
  name = "saga-lambda-policy"
  role = aws_iam_role.lambda_execution_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.orders.arn,
          aws_dynamodb_table.inventory.arn,
          aws_dynamodb_table.payments.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.notifications.arn
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

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Step Functions execution role
resource "aws_iam_role" "step_functions_role" {
  name = "saga-stepfunctions-role-${local.resource_suffix}"
  
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
    Name = "saga-stepfunctions-execution-role"
    Purpose = "Step Functions execution role for saga pattern"
  })
}

# Step Functions execution policy
resource "aws_iam_role_policy" "step_functions_policy" {
  name = "saga-stepfunctions-policy"
  role = aws_iam_role.step_functions_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.order_service.arn,
          aws_lambda_function.inventory_service.arn,
          aws_lambda_function.payment_service.arn,
          aws_lambda_function.notification_service.arn,
          aws_lambda_function.cancel_order.arn,
          aws_lambda_function.revert_inventory.arn,
          aws_lambda_function.refund_payment.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# API Gateway execution role
resource "aws_iam_role" "api_gateway_role" {
  name = "saga-apigateway-role-${local.resource_suffix}"
  
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
    Name = "saga-apigateway-execution-role"
    Purpose = "API Gateway execution role for saga pattern"
  })
}

# API Gateway execution policy
resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "saga-apigateway-policy"
  role = aws_iam_role.api_gateway_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.saga_orchestrator.arn
      }
    ]
  })
}

# ============================================================================
# Lambda Functions
# ============================================================================

# Archive Lambda function code
data "archive_file" "lambda_code" {
  for_each = {
    order-service = {
      filename = "order-service.py"
      content = templatefile("${path.module}/lambda-code/order-service.py.tpl", {
        failure_rate = 0.0
      })
    }
    inventory-service = {
      filename = "inventory-service.py"
      content = templatefile("${path.module}/lambda-code/inventory-service.py.tpl", {
        failure_rate = 0.0
      })
    }
    payment-service = {
      filename = "payment-service.py"
      content = templatefile("${path.module}/lambda-code/payment-service.py.tpl", {
        failure_rate = var.payment_failure_rate
      })
    }
    notification-service = {
      filename = "notification-service.py"
      content = file("${path.module}/lambda-code/notification-service.py")
    }
    cancel-order = {
      filename = "cancel-order.py"
      content = file("${path.module}/lambda-code/cancel-order.py")
    }
    revert-inventory = {
      filename = "revert-inventory.py"
      content = file("${path.module}/lambda-code/revert-inventory.py")
    }
    refund-payment = {
      filename = "refund-payment.py"
      content = file("${path.module}/lambda-code/refund-payment.py")
    }
  }
  
  type        = "zip"
  output_path = "${path.module}/.terraform/tmp/${each.key}.zip"
  
  source {
    content  = each.value.content
    filename = each.value.filename
  }
}

# Order Service Lambda
resource "aws_lambda_function" "order_service" {
  function_name = "saga-order-service-${local.resource_suffix}"
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "order-service.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  
  filename      = data.archive_file.lambda_code["order-service"].output_path
  source_code_hash = data.archive_file.lambda_code["order-service"].output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.orders.name
    }
  }
  
  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = merge(local.common_tags, {
    Name = "saga-order-service"
    Purpose = "Order service for saga pattern"
  })
}

# Inventory Service Lambda
resource "aws_lambda_function" "inventory_service" {
  function_name = "saga-inventory-service-${local.resource_suffix}"
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "inventory-service.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  
  filename      = data.archive_file.lambda_code["inventory-service"].output_path
  source_code_hash = data.archive_file.lambda_code["inventory-service"].output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.inventory.name
    }
  }
  
  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = merge(local.common_tags, {
    Name = "saga-inventory-service"
    Purpose = "Inventory service for saga pattern"
  })
}

# Payment Service Lambda
resource "aws_lambda_function" "payment_service" {
  function_name = "saga-payment-service-${local.resource_suffix}"
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "payment-service.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  
  filename      = data.archive_file.lambda_code["payment-service"].output_path
  source_code_hash = data.archive_file.lambda_code["payment-service"].output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.payments.name
      FAILURE_RATE = tostring(var.payment_failure_rate)
    }
  }
  
  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = merge(local.common_tags, {
    Name = "saga-payment-service"
    Purpose = "Payment service for saga pattern"
  })
}

# Notification Service Lambda
resource "aws_lambda_function" "notification_service" {
  function_name = "saga-notification-service-${local.resource_suffix}"
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "notification-service.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  
  filename      = data.archive_file.lambda_code["notification-service"].output_path
  source_code_hash = data.archive_file.lambda_code["notification-service"].output_base64sha256
  
  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.notifications.arn
    }
  }
  
  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = merge(local.common_tags, {
    Name = "saga-notification-service"
    Purpose = "Notification service for saga pattern"
  })
}

# Cancel Order Compensation Lambda
resource "aws_lambda_function" "cancel_order" {
  function_name = "saga-cancel-order-${local.resource_suffix}"
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "cancel-order.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  
  filename      = data.archive_file.lambda_code["cancel-order"].output_path
  source_code_hash = data.archive_file.lambda_code["cancel-order"].output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.orders.name
    }
  }
  
  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = merge(local.common_tags, {
    Name = "saga-cancel-order"
    Purpose = "Order cancellation compensation for saga pattern"
  })
}

# Revert Inventory Compensation Lambda
resource "aws_lambda_function" "revert_inventory" {
  function_name = "saga-revert-inventory-${local.resource_suffix}"
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "revert-inventory.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  
  filename      = data.archive_file.lambda_code["revert-inventory"].output_path
  source_code_hash = data.archive_file.lambda_code["revert-inventory"].output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.inventory.name
    }
  }
  
  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = merge(local.common_tags, {
    Name = "saga-revert-inventory"
    Purpose = "Inventory reversion compensation for saga pattern"
  })
}

# Refund Payment Compensation Lambda
resource "aws_lambda_function" "refund_payment" {
  function_name = "saga-refund-payment-${local.resource_suffix}"
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "refund-payment.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout
  
  filename      = data.archive_file.lambda_code["refund-payment"].output_path
  source_code_hash = data.archive_file.lambda_code["refund-payment"].output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.payments.name
    }
  }
  
  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = merge(local.common_tags, {
    Name = "saga-refund-payment"
    Purpose = "Payment refund compensation for saga pattern"
  })
}

# ============================================================================
# Step Functions State Machine
# ============================================================================

resource "aws_sfn_state_machine" "saga_orchestrator" {
  name       = "saga-orchestrator-${local.resource_suffix}"
  role_arn   = aws_iam_role.step_functions_role.arn
  type       = "STANDARD"
  
  definition = templatefile("${path.module}/state-machine/saga-definition.json.tpl", {
    order_function_arn        = aws_lambda_function.order_service.arn
    inventory_function_arn    = aws_lambda_function.inventory_service.arn
    payment_function_arn      = aws_lambda_function.payment_service.arn
    notification_function_arn = aws_lambda_function.notification_service.arn
    cancel_order_arn          = aws_lambda_function.cancel_order.arn
    revert_inventory_arn      = aws_lambda_function.revert_inventory.arn
    refund_payment_arn        = aws_lambda_function.refund_payment.arn
    order_table_name          = aws_dynamodb_table.orders.name
    inventory_table_name      = aws_dynamodb_table.inventory.name
    payment_table_name        = aws_dynamodb_table.payments.name
    sns_topic_arn             = aws_sns_topic.notifications.arn
  })
  
  logging_configuration {
    level                  = var.step_functions_logging_level
    include_execution_data = true
    
    log_destination = "${aws_cloudwatch_log_group.step_functions.arn}:*"
  }
  
  tags = merge(local.common_tags, {
    Name = "saga-orchestrator"
    Purpose = "Step Functions orchestrator for saga pattern"
  })
}

# ============================================================================
# API Gateway
# ============================================================================

# REST API
resource "aws_api_gateway_rest_api" "saga_api" {
  name        = "saga-api-${local.resource_suffix}"
  description = "API for initiating saga transactions"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = merge(local.common_tags, {
    Name = "saga-api"
    Purpose = "API Gateway for saga pattern"
  })
}

# Orders resource
resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.saga_api.id
  parent_id   = aws_api_gateway_rest_api.saga_api.root_resource_id
  path_part   = "orders"
}

# POST method for orders
resource "aws_api_gateway_method" "orders_post" {
  rest_api_id   = aws_api_gateway_rest_api.saga_api.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "POST"
  authorization = "NONE"
  
  request_validator_id = aws_api_gateway_request_validator.orders_validator.id
  request_models = {
    "application/json" = aws_api_gateway_model.order_model.name
  }
}

# Request validator
resource "aws_api_gateway_request_validator" "orders_validator" {
  name                        = "orders-validator"
  rest_api_id                 = aws_api_gateway_rest_api.saga_api.id
  validate_request_body       = true
  validate_request_parameters = false
}

# Request model
resource "aws_api_gateway_model" "order_model" {
  rest_api_id  = aws_api_gateway_rest_api.saga_api.id
  name         = "OrderModel"
  content_type = "application/json"
  
  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "Order Request Schema"
    type      = "object"
    properties = {
      customerId = {
        type = "string"
      }
      productId = {
        type = "string"
      }
      quantity = {
        type = "integer"
        minimum = 1
      }
      amount = {
        type = "number"
        minimum = 0
      }
    }
    required = ["customerId", "productId", "quantity", "amount"]
  })
}

# Step Functions integration
resource "aws_api_gateway_integration" "step_functions_integration" {
  rest_api_id = aws_api_gateway_rest_api.saga_api.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.orders_post.http_method
  
  integration_http_method = "POST"
  type                   = "AWS"
  uri                    = "arn:aws:apigateway:${data.aws_region.current.name}:states:action/StartExecution"
  credentials           = aws_iam_role.api_gateway_role.arn
  
  request_templates = {
    "application/json" = jsonencode({
      stateMachineArn = aws_sfn_state_machine.saga_orchestrator.arn
      input           = "$util.escapeJavaScript($input.body)"
    })
  }
}

# Method response
resource "aws_api_gateway_method_response" "orders_response" {
  rest_api_id = aws_api_gateway_rest_api.saga_api.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.orders_post.http_method
  status_code = "200"
  
  response_models = {
    "application/json" = "Empty"
  }
}

# Integration response
resource "aws_api_gateway_integration_response" "step_functions_response" {
  rest_api_id = aws_api_gateway_rest_api.saga_api.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.orders_post.http_method
  status_code = aws_api_gateway_method_response.orders_response.status_code
  
  response_templates = {
    "application/json" = jsonencode({
      executionArn = "$input.path('$.executionArn')"
      startDate    = "$input.path('$.startDate')"
    })
  }
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "saga_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.step_functions_integration,
    aws_api_gateway_integration_response.step_functions_response
  ]
  
  rest_api_id = aws_api_gateway_rest_api.saga_api.id
  stage_name  = var.api_gateway_stage_name
  
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.orders.id,
      aws_api_gateway_method.orders_post.id,
      aws_api_gateway_integration.step_functions_integration.id,
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage (managed separately for better control)
resource "aws_api_gateway_stage" "saga_api_stage" {
  deployment_id = aws_api_gateway_deployment.saga_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.saga_api.id
  stage_name    = var.api_gateway_stage_name
  
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
    Name = "saga-api-${var.api_gateway_stage_name}"
    Purpose = "API Gateway stage for saga pattern"
  })
}

# API Gateway CloudWatch log group
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_api_gateway_logging ? 1 : 0
  name              = "/aws/apigateway/saga-api-${local.resource_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "saga-api-gateway-logs"
    Purpose = "API Gateway logging for saga pattern"
  })
}