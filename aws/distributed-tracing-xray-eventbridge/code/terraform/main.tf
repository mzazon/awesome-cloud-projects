# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    CreatedBy   = "terraform"
    Recipe      = "distributed-tracing-x-ray-eventbridge"
  })
  
  # Lambda function names
  lambda_functions = {
    order        = "${local.name_prefix}-order-${local.name_suffix}"
    payment      = "${local.name_prefix}-payment-${local.name_suffix}"
    inventory    = "${local.name_prefix}-inventory-${local.name_suffix}"
    notification = "${local.name_prefix}-notification-${local.name_suffix}"
  }
}

# ===================================================================
# IAM ROLES AND POLICIES
# ===================================================================

# IAM role for Lambda functions with X-Ray and EventBridge permissions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role-${local.name_suffix}"
  
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

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach X-Ray write access policy
resource "aws_iam_role_policy_attachment" "lambda_xray_write" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Custom policy for EventBridge access
resource "aws_iam_role_policy" "lambda_eventbridge_policy" {
  name = "${local.name_prefix}-eventbridge-policy-${local.name_suffix}"
  role = aws_iam_role.lambda_execution_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = [
          aws_cloudwatch_event_bus.custom_bus.arn
        ]
      }
    ]
  })
}

# ===================================================================
# EVENTBRIDGE RESOURCES
# ===================================================================

# Custom EventBridge event bus for distributed tracing
resource "aws_cloudwatch_event_bus" "custom_bus" {
  name = "${local.name_prefix}-bus-${local.name_suffix}"
  
  tags = local.common_tags
}

# EventBridge rule for payment processing (triggered by order creation)
resource "aws_cloudwatch_event_rule" "payment_processing_rule" {
  name           = "${local.name_prefix}-payment-rule-${local.name_suffix}"
  description    = "Route order created events to payment service"
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
  
  event_pattern = jsonencode({
    source      = ["order.service"]
    detail-type = ["Order Created"]
  })
  
  tags = local.common_tags
}

# EventBridge rule for inventory updates (triggered by order creation)
resource "aws_cloudwatch_event_rule" "inventory_update_rule" {
  name           = "${local.name_prefix}-inventory-rule-${local.name_suffix}"
  description    = "Route order created events to inventory service"
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
  
  event_pattern = jsonencode({
    source      = ["order.service"]
    detail-type = ["Order Created"]
  })
  
  tags = local.common_tags
}

# EventBridge rule for notifications (triggered by payment and inventory events)
resource "aws_cloudwatch_event_rule" "notification_rule" {
  name           = "${local.name_prefix}-notification-rule-${local.name_suffix}"
  description    = "Route completion events to notification service"
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
  
  event_pattern = jsonencode({
    source      = ["payment.service", "inventory.service"]
    detail-type = ["Payment Processed", "Inventory Updated"]
  })
  
  tags = local.common_tags
}

# ===================================================================
# LAMBDA FUNCTIONS
# ===================================================================

# Lambda function source code archives
data "archive_file" "order_service" {
  type        = "zip"
  output_path = "${path.module}/order-service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/order_service.py", {
      event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "payment_service" {
  type        = "zip"
  output_path = "${path.module}/payment-service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/payment_service.py", {
      event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "inventory_service" {
  type        = "zip"
  output_path = "${path.module}/inventory-service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/inventory_service.py", {
      event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "notification_service" {
  type        = "zip"
  output_path = "${path.module}/notification-service.zip"
  
  source {
    content = file("${path.module}/lambda_functions/notification_service.py")
    filename = "lambda_function.py"
  }
}

# Order Service Lambda Function
resource "aws_lambda_function" "order_service" {
  filename         = data.archive_file.order_service.output_path
  function_name    = local.lambda_functions.order
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.order_service.output_base64sha256
  
  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.custom_bus.name
    }
  }
  
  tracing_config {
    mode = var.x_ray_tracing_mode
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_xray_write,
    aws_cloudwatch_log_group.order_service_logs
  ]
  
  tags = local.common_tags
}

# Payment Service Lambda Function
resource "aws_lambda_function" "payment_service" {
  filename         = data.archive_file.payment_service.output_path
  function_name    = local.lambda_functions.payment
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.payment_service.output_base64sha256
  
  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.custom_bus.name
    }
  }
  
  tracing_config {
    mode = var.x_ray_tracing_mode
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_xray_write,
    aws_cloudwatch_log_group.payment_service_logs
  ]
  
  tags = local.common_tags
}

# Inventory Service Lambda Function
resource "aws_lambda_function" "inventory_service" {
  filename         = data.archive_file.inventory_service.output_path
  function_name    = local.lambda_functions.inventory
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.inventory_service.output_base64sha256
  
  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.custom_bus.name
    }
  }
  
  tracing_config {
    mode = var.x_ray_tracing_mode
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_xray_write,
    aws_cloudwatch_log_group.inventory_service_logs
  ]
  
  tags = local.common_tags
}

# Notification Service Lambda Function
resource "aws_lambda_function" "notification_service" {
  filename         = data.archive_file.notification_service.output_path
  function_name    = local.lambda_functions.notification
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.notification_service.output_base64sha256
  
  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.custom_bus.name
    }
  }
  
  tracing_config {
    mode = var.x_ray_tracing_mode
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_xray_write,
    aws_cloudwatch_log_group.notification_service_logs
  ]
  
  tags = local.common_tags
}

# ===================================================================
# CLOUDWATCH LOG GROUPS
# ===================================================================

# CloudWatch log groups for Lambda functions
resource "aws_cloudwatch_log_group" "order_service_logs" {
  name              = "/aws/lambda/${local.lambda_functions.order}"
  retention_in_days = var.lambda_log_retention_days
  
  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "payment_service_logs" {
  name              = "/aws/lambda/${local.lambda_functions.payment}"
  retention_in_days = var.lambda_log_retention_days
  
  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "inventory_service_logs" {
  name              = "/aws/lambda/${local.lambda_functions.inventory}"
  retention_in_days = var.lambda_log_retention_days
  
  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "notification_service_logs" {
  name              = "/aws/lambda/${local.lambda_functions.notification}"
  retention_in_days = var.lambda_log_retention_days
  
  tags = local.common_tags
}

# ===================================================================
# EVENTBRIDGE TARGETS
# ===================================================================

# EventBridge target for payment processing
resource "aws_cloudwatch_event_target" "payment_target" {
  rule           = aws_cloudwatch_event_rule.payment_processing_rule.name
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
  target_id      = "PaymentServiceTarget"
  arn            = aws_lambda_function.payment_service.arn
}

# EventBridge target for inventory updates
resource "aws_cloudwatch_event_target" "inventory_target" {
  rule           = aws_cloudwatch_event_rule.inventory_update_rule.name
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
  target_id      = "InventoryServiceTarget"
  arn            = aws_lambda_function.inventory_service.arn
}

# EventBridge target for notifications
resource "aws_cloudwatch_event_target" "notification_target" {
  rule           = aws_cloudwatch_event_rule.notification_rule.name
  event_bus_name = aws_cloudwatch_event_bus.custom_bus.name
  target_id      = "NotificationServiceTarget"
  arn            = aws_lambda_function.notification_service.arn
}

# ===================================================================
# LAMBDA PERMISSIONS FOR EVENTBRIDGE
# ===================================================================

# Permission for EventBridge to invoke payment service
resource "aws_lambda_permission" "allow_eventbridge_payment" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.payment_service.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.payment_processing_rule.arn
}

# Permission for EventBridge to invoke inventory service
resource "aws_lambda_permission" "allow_eventbridge_inventory" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inventory_service.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.inventory_update_rule.arn
}

# Permission for EventBridge to invoke notification service
resource "aws_lambda_permission" "allow_eventbridge_notification" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification_service.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.notification_rule.arn
}

# ===================================================================
# API GATEWAY
# ===================================================================

# REST API Gateway
resource "aws_api_gateway_rest_api" "tracing_api" {
  name        = "${local.name_prefix}-api-${local.name_suffix}"
  description = "Distributed tracing demo API with X-Ray tracing"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = local.common_tags
}

# API Gateway resource for orders
resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.tracing_api.id
  parent_id   = aws_api_gateway_rest_api.tracing_api.root_resource_id
  path_part   = "orders"
}

# API Gateway resource for customer ID
resource "aws_api_gateway_resource" "customer" {
  rest_api_id = aws_api_gateway_rest_api.tracing_api.id
  parent_id   = aws_api_gateway_resource.orders.id
  path_part   = "{customerId}"
}

# POST method for order creation
resource "aws_api_gateway_method" "post_order" {
  rest_api_id   = aws_api_gateway_rest_api.tracing_api.id
  resource_id   = aws_api_gateway_resource.customer.id
  http_method   = "POST"
  authorization = "NONE"
}

# Lambda integration for order service
resource "aws_api_gateway_integration" "order_integration" {
  rest_api_id = aws_api_gateway_rest_api.tracing_api.id
  resource_id = aws_api_gateway_resource.customer.id
  http_method = aws_api_gateway_method.post_order.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.order_service.invoke_arn
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "tracing_deployment" {
  rest_api_id = aws_api_gateway_rest_api.tracing_api.id
  
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.orders.id,
      aws_api_gateway_resource.customer.id,
      aws_api_gateway_method.post_order.id,
      aws_api_gateway_integration.order_integration.id,
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage with X-Ray tracing enabled
resource "aws_api_gateway_stage" "tracing_stage" {
  deployment_id = aws_api_gateway_deployment.tracing_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.tracing_api.id
  stage_name    = var.api_gateway_stage_name
  
  # Enable X-Ray tracing
  xray_tracing_enabled = true
  
  # Enable detailed CloudWatch metrics if requested
  dynamic "access_log_settings" {
    for_each = var.enable_detailed_monitoring ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway_logs[0].arn
      format = jsonencode({
        requestId      = "$requestId"
        ip            = "$requestIP"
        caller        = "$requestUser"
        requestTime   = "$requestTime"
        httpMethod    = "$httpMethod"
        resourcePath  = "$resourcePath"
        status        = "$status"
        protocol      = "$protocol"
        responseLength = "$responseLength"
      })
    }
  }
  
  tags = local.common_tags
}

# CloudWatch log group for API Gateway (conditional)
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_detailed_monitoring ? 1 : 0
  name              = "/aws/apigateway/${aws_api_gateway_rest_api.tracing_api.name}"
  retention_in_days = var.lambda_log_retention_days
  
  tags = local.common_tags
}

# Permission for API Gateway to invoke order service
resource "aws_lambda_permission" "allow_apigateway_order" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.order_service.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.tracing_api.execution_arn}/*/*"
}