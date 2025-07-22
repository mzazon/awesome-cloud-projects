# Event-Driven Microservices with EventBridge and Step Functions
# This Terraform configuration deploys a complete event-driven microservices architecture
# using Amazon EventBridge for messaging and AWS Step Functions for workflow orchestration

# Data Sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "event-driven-microservices-eventbridge-step-functions"
  })
}

# =============================================================================
# EVENTBRIDGE CONFIGURATION
# =============================================================================

# Custom EventBridge bus for microservices communication
resource "aws_cloudwatch_event_bus" "microservices_bus" {
  name = "${local.name_prefix}-eventbus-${local.name_suffix}"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-eventbus-${local.name_suffix}"
    Description = "Custom EventBridge bus for microservices communication"
  })
}

# EventBridge rule for order created events
resource "aws_cloudwatch_event_rule" "order_created" {
  name           = "${local.name_prefix}-order-created-rule-${local.name_suffix}"
  description    = "Rule to trigger Step Functions when an order is created"
  event_bus_name = aws_cloudwatch_event_bus.microservices_bus.name

  event_pattern = jsonencode({
    source       = ["order.service"]
    detail-type  = ["Order Created"]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-order-created-rule-${local.name_suffix}"
  })
}

# EventBridge rule for payment events
resource "aws_cloudwatch_event_rule" "payment_events" {
  name           = "${local.name_prefix}-payment-events-rule-${local.name_suffix}"
  description    = "Rule to handle payment processing events"
  event_bus_name = aws_cloudwatch_event_bus.microservices_bus.name

  event_pattern = jsonencode({
    source       = ["payment.service"]
    detail-type  = ["Payment Processed", "Payment Failed"]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-payment-events-rule-${local.name_suffix}"
  })
}

# =============================================================================
# DYNAMODB CONFIGURATION
# =============================================================================

# DynamoDB table for order data
resource "aws_dynamodb_table" "orders" {
  name           = "${local.name_prefix}-orders-${local.name_suffix}"
  billing_mode   = var.dynamodb_billing_mode
  
  # Only set read/write capacity for PROVISIONED billing mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  hash_key  = "orderId"
  range_key = "customerId"

  attribute {
    name = "orderId"
    type = "S"
  }

  attribute {
    name = "customerId"
    type = "S"
  }

  # Global Secondary Index for customer-based queries
  global_secondary_index {
    name     = "CustomerId-Index"
    hash_key = "customerId"
    
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
    
    projection_type = "ALL"
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
    Name        = "${local.name_prefix}-orders-${local.name_suffix}"
    Description = "DynamoDB table for storing order data"
  })
}

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# Lambda execution role
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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-role-${local.name_suffix}"
  })
}

# Lambda execution policy
resource "aws_iam_role_policy" "lambda_execution_policy" {
  name = "${local.name_prefix}-lambda-policy-${local.name_suffix}"
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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.orders.arn,
          "${aws_dynamodb_table.orders.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = aws_cloudwatch_event_bus.microservices_bus.arn
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# Step Functions execution role
resource "aws_iam_role" "step_functions_execution_role" {
  name = "${local.name_prefix}-stepfunctions-role-${local.name_suffix}"

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
    Name = "${local.name_prefix}-stepfunctions-role-${local.name_suffix}"
  })
}

# Step Functions execution policy
resource "aws_iam_role_policy" "step_functions_execution_policy" {
  name = "${local.name_prefix}-stepfunctions-policy-${local.name_suffix}"
  role = aws_iam_role.step_functions_execution_role.id

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
          aws_lambda_function.payment_service.arn,
          aws_lambda_function.inventory_service.arn,
          aws_lambda_function.notification_service.arn
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
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# CLOUDWATCH LOG GROUPS
# =============================================================================

# CloudWatch log group for Order Service
resource "aws_cloudwatch_log_group" "order_service" {
  name              = "/aws/lambda/${local.name_prefix}-order-service-${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.name_prefix}-order-service-${local.name_suffix}"
  })
}

# CloudWatch log group for Payment Service
resource "aws_cloudwatch_log_group" "payment_service" {
  name              = "/aws/lambda/${local.name_prefix}-payment-service-${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.name_prefix}-payment-service-${local.name_suffix}"
  })
}

# CloudWatch log group for Inventory Service
resource "aws_cloudwatch_log_group" "inventory_service" {
  name              = "/aws/lambda/${local.name_prefix}-inventory-service-${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.name_prefix}-inventory-service-${local.name_suffix}"
  })
}

# CloudWatch log group for Notification Service
resource "aws_cloudwatch_log_group" "notification_service" {
  name              = "/aws/lambda/${local.name_prefix}-notification-service-${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.name_prefix}-notification-service-${local.name_suffix}"
  })
}

# CloudWatch log group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/stepfunctions/${local.name_prefix}-order-processing-${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "/aws/stepfunctions/${local.name_prefix}-order-processing-${local.name_suffix}"
  })
}

# =============================================================================
# LAMBDA FUNCTIONS
# =============================================================================

# Archive for Order Service Lambda function
data "archive_file" "order_service" {
  type        = "zip"
  output_path = "${path.module}/order-service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/order_service.py", {
      dynamodb_table_name = aws_dynamodb_table.orders.name
      eventbus_name      = aws_cloudwatch_event_bus.microservices_bus.name
    })
    filename = "order_service.py"
  }
}

# Order Service Lambda function
resource "aws_lambda_function" "order_service" {
  depends_on = [aws_cloudwatch_log_group.order_service]
  
  filename         = data.archive_file.order_service.output_path
  function_name    = "${local.name_prefix}-order-service-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "order_service.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.order_service.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.orders.name
      EVENTBUS_NAME      = aws_cloudwatch_event_bus.microservices_bus.name
      POWERTOOLS_SERVICE_NAME = "order-service"
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-order-service-${local.name_suffix}"
  })
}

# Archive for Payment Service Lambda function
data "archive_file" "payment_service" {
  type        = "zip"
  output_path = "${path.module}/payment-service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/payment_service.py", {
      dynamodb_table_name = aws_dynamodb_table.orders.name
      eventbus_name      = aws_cloudwatch_event_bus.microservices_bus.name
    })
    filename = "payment_service.py"
  }
}

# Payment Service Lambda function
resource "aws_lambda_function" "payment_service" {
  depends_on = [aws_cloudwatch_log_group.payment_service]
  
  filename         = data.archive_file.payment_service.output_path
  function_name    = "${local.name_prefix}-payment-service-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "payment_service.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.payment_service.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.orders.name
      EVENTBUS_NAME      = aws_cloudwatch_event_bus.microservices_bus.name
      POWERTOOLS_SERVICE_NAME = "payment-service"
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-payment-service-${local.name_suffix}"
  })
}

# Archive for Inventory Service Lambda function
data "archive_file" "inventory_service" {
  type        = "zip"
  output_path = "${path.module}/inventory-service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/inventory_service.py", {
      dynamodb_table_name = aws_dynamodb_table.orders.name
      eventbus_name      = aws_cloudwatch_event_bus.microservices_bus.name
    })
    filename = "inventory_service.py"
  }
}

# Inventory Service Lambda function
resource "aws_lambda_function" "inventory_service" {
  depends_on = [aws_cloudwatch_log_group.inventory_service]
  
  filename         = data.archive_file.inventory_service.output_path
  function_name    = "${local.name_prefix}-inventory-service-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "inventory_service.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.inventory_service.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.orders.name
      EVENTBUS_NAME      = aws_cloudwatch_event_bus.microservices_bus.name
      POWERTOOLS_SERVICE_NAME = "inventory-service"
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-inventory-service-${local.name_suffix}"
  })
}

# Archive for Notification Service Lambda function
data "archive_file" "notification_service" {
  type        = "zip"
  output_path = "${path.module}/notification-service.zip"
  
  source {
    content = file("${path.module}/lambda_functions/notification_service.py")
    filename = "notification_service.py"
  }
}

# Notification Service Lambda function
resource "aws_lambda_function" "notification_service" {
  depends_on = [aws_cloudwatch_log_group.notification_service]
  
  filename         = data.archive_file.notification_service.output_path
  function_name    = "${local.name_prefix}-notification-service-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "notification_service.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.notification_service.output_base64sha256

  environment {
    variables = {
      POWERTOOLS_SERVICE_NAME = "notification-service"
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-notification-service-${local.name_suffix}"
  })
}

# =============================================================================
# STEP FUNCTIONS STATE MACHINE
# =============================================================================

# Step Functions state machine for order processing workflow
resource "aws_sfn_state_machine" "order_processing" {
  name     = "${local.name_prefix}-order-processing-${local.name_suffix}"
  role_arn = aws_iam_role.step_functions_execution_role.arn
  type     = "STANDARD"

  definition = templatefile("${path.module}/step_functions/order_processing_workflow.json", {
    payment_service_arn     = aws_lambda_function.payment_service.arn
    inventory_service_arn   = aws_lambda_function.inventory_service.arn
    notification_service_arn = aws_lambda_function.notification_service.arn
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                 = var.step_functions_log_level
  }

  tracing_configuration {
    enabled = var.enable_xray_tracing
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-order-processing-${local.name_suffix}"
  })
}

# =============================================================================
# EVENTBRIDGE TARGETS
# =============================================================================

# EventBridge target for order created events -> Step Functions
resource "aws_cloudwatch_event_target" "order_created_target" {
  rule           = aws_cloudwatch_event_rule.order_created.name
  event_bus_name = aws_cloudwatch_event_bus.microservices_bus.name
  target_id      = "StepFunctionsTarget"
  arn            = aws_sfn_state_machine.order_processing.arn
  role_arn       = aws_iam_role.step_functions_execution_role.arn

  input_transformer {
    input_paths = {
      detail = "$.detail"
    }
    input_template = jsonencode({
      detail = "<detail>"
    })
  }
}

# EventBridge target for payment events -> Notification Service
resource "aws_cloudwatch_event_target" "payment_events_target" {
  rule           = aws_cloudwatch_event_rule.payment_events.name
  event_bus_name = aws_cloudwatch_event_bus.microservices_bus.name
  target_id      = "NotificationServiceTarget"
  arn            = aws_lambda_function.notification_service.arn
}

# Lambda permission for EventBridge to invoke Notification Service
resource "aws_lambda_permission" "allow_eventbridge_notification" {
  statement_id  = "AllowEventbridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification_service.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.payment_events.arn
}

# =============================================================================
# ENHANCED MONITORING (OPTIONAL)
# =============================================================================

# CloudWatch Dashboard for monitoring (optional)
resource "aws_cloudwatch_dashboard" "microservices_dashboard" {
  count          = var.enable_enhanced_monitoring ? 1 : 0
  dashboard_name = "${local.name_prefix}-microservices-dashboard-${local.name_suffix}"

  dashboard_body = templatefile("${path.module}/monitoring/dashboard.json", {
    aws_region              = data.aws_region.current.name
    order_service_name      = aws_lambda_function.order_service.function_name
    payment_service_name    = aws_lambda_function.payment_service.function_name
    inventory_service_name  = aws_lambda_function.inventory_service.function_name
    notification_service_name = aws_lambda_function.notification_service.function_name
    state_machine_arn       = aws_sfn_state_machine.order_processing.arn
    dynamodb_table_name     = aws_dynamodb_table.orders.name
  })
}

# CloudWatch Alarms for critical metrics (optional)
resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  count = var.enable_enhanced_monitoring ? 4 : 0
  
  alarm_name          = "${local.name_prefix}-${element(["order", "payment", "inventory", "notification"], count.index)}-service-error-rate-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda error rate"
  alarm_actions       = []

  dimensions = {
    FunctionName = element([
      aws_lambda_function.order_service.function_name,
      aws_lambda_function.payment_service.function_name,
      aws_lambda_function.inventory_service.function_name,
      aws_lambda_function.notification_service.function_name
    ], count.index)
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${element(["order", "payment", "inventory", "notification"], count.index)}-service-error-rate-${local.name_suffix}"
  })
}