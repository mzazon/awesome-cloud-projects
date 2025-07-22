# ===============================================================================
# AWS Step Functions Microservices Orchestration Infrastructure
# ===============================================================================
# This Terraform configuration creates a complete microservices orchestration 
# solution using AWS Step Functions, Lambda, and EventBridge.
#
# Components:
# - Lambda functions for each microservice (User, Order, Payment, Inventory, Notification)
# - Step Functions state machine for workflow orchestration
# - EventBridge rule for event-driven triggers
# - IAM roles and policies for service integration
# ===============================================================================

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  project_name = "${var.project_name}-${random_id.suffix.hex}"
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Project     = "Microservices Step Functions"
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# ===============================================================================
# IAM Roles and Policies
# ===============================================================================

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.project_name}-lambda-execution-role"

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
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# IAM role for Step Functions execution
resource "aws_iam_role" "stepfunctions_execution_role" {
  name = "${local.project_name}-stepfunctions-execution-role"

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

  tags = local.common_tags
}

# Policy allowing Step Functions to invoke Lambda functions
resource "aws_iam_policy" "stepfunctions_lambda_policy" {
  name        = "${local.project_name}-stepfunctions-lambda-policy"
  description = "Policy for Step Functions to invoke Lambda functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.user_service.arn,
          aws_lambda_function.order_service.arn,
          aws_lambda_function.payment_service.arn,
          aws_lambda_function.inventory_service.arn,
          aws_lambda_function.notification_service.arn
        ]
      }
    ]
  })

  tags = local.common_tags
}

# Attach Lambda invocation policy to Step Functions role
resource "aws_iam_role_policy_attachment" "stepfunctions_lambda_policy_attachment" {
  policy_arn = aws_iam_policy.stepfunctions_lambda_policy.arn
  role       = aws_iam_role.stepfunctions_execution_role.name
}

# IAM role for EventBridge to trigger Step Functions
resource "aws_iam_role" "eventbridge_stepfunctions_role" {
  name = "${local.project_name}-eventbridge-stepfunctions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Policy allowing EventBridge to start Step Functions executions
resource "aws_iam_policy" "eventbridge_stepfunctions_policy" {
  name        = "${local.project_name}-eventbridge-stepfunctions-policy"
  description = "Policy for EventBridge to start Step Functions executions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.microservices_workflow.arn
      }
    ]
  })

  tags = local.common_tags
}

# Attach Step Functions execution policy to EventBridge role
resource "aws_iam_role_policy_attachment" "eventbridge_stepfunctions_policy_attachment" {
  policy_arn = aws_iam_policy.eventbridge_stepfunctions_policy.arn
  role       = aws_iam_role.eventbridge_stepfunctions_role.name
}

# ===============================================================================
# Lambda Functions - Microservices Implementation
# ===============================================================================

# User Service Lambda Function
resource "aws_lambda_function" "user_service" {
  function_name = "${local.project_name}-user-service"
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "index.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout

  # Inline code for User Service
  filename         = data.archive_file.user_service_zip.output_path
  source_code_hash = data.archive_file.user_service_zip.output_base64sha256

  environment {
    variables = {
      LOG_LEVEL = var.log_level
    }
  }

  tags = merge(local.common_tags, {
    Service = "UserService"
  })

  depends_on = [aws_cloudwatch_log_group.user_service_logs]
}

# User Service Lambda code archive
data "archive_file" "user_service_zip" {
  type        = "zip"
  output_path = "${path.module}/user_service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/user_service.py", {
      log_level = var.log_level
    })
    filename = "index.py"
  }
}

# CloudWatch Log Group for User Service
resource "aws_cloudwatch_log_group" "user_service_logs" {
  name              = "/aws/lambda/${local.project_name}-user-service"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# Order Service Lambda Function
resource "aws_lambda_function" "order_service" {
  function_name = "${local.project_name}-order-service"
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "index.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout

  filename         = data.archive_file.order_service_zip.output_path
  source_code_hash = data.archive_file.order_service_zip.output_base64sha256

  environment {
    variables = {
      LOG_LEVEL = var.log_level
    }
  }

  tags = merge(local.common_tags, {
    Service = "OrderService"
  })

  depends_on = [aws_cloudwatch_log_group.order_service_logs]
}

# Order Service Lambda code archive
data "archive_file" "order_service_zip" {
  type        = "zip"
  output_path = "${path.module}/order_service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/order_service.py", {
      log_level = var.log_level
    })
    filename = "index.py"
  }
}

# CloudWatch Log Group for Order Service
resource "aws_cloudwatch_log_group" "order_service_logs" {
  name              = "/aws/lambda/${local.project_name}-order-service"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# Payment Service Lambda Function
resource "aws_lambda_function" "payment_service" {
  function_name = "${local.project_name}-payment-service"
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "index.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout

  filename         = data.archive_file.payment_service_zip.output_path
  source_code_hash = data.archive_file.payment_service_zip.output_base64sha256

  environment {
    variables = {
      LOG_LEVEL = var.log_level
    }
  }

  tags = merge(local.common_tags, {
    Service = "PaymentService"
  })

  depends_on = [aws_cloudwatch_log_group.payment_service_logs]
}

# Payment Service Lambda code archive
data "archive_file" "payment_service_zip" {
  type        = "zip"
  output_path = "${path.module}/payment_service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/payment_service.py", {
      log_level = var.log_level
    })
    filename = "index.py"
  }
}

# CloudWatch Log Group for Payment Service
resource "aws_cloudwatch_log_group" "payment_service_logs" {
  name              = "/aws/lambda/${local.project_name}-payment-service"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# Inventory Service Lambda Function
resource "aws_lambda_function" "inventory_service" {
  function_name = "${local.project_name}-inventory-service"
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "index.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout

  filename         = data.archive_file.inventory_service_zip.output_path
  source_code_hash = data.archive_file.inventory_service_zip.output_base64sha256

  environment {
    variables = {
      LOG_LEVEL = var.log_level
    }
  }

  tags = merge(local.common_tags, {
    Service = "InventoryService"
  })

  depends_on = [aws_cloudwatch_log_group.inventory_service_logs]
}

# Inventory Service Lambda code archive
data "archive_file" "inventory_service_zip" {
  type        = "zip"
  output_path = "${path.module}/inventory_service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/inventory_service.py", {
      log_level = var.log_level
    })
    filename = "index.py"
  }
}

# CloudWatch Log Group for Inventory Service
resource "aws_cloudwatch_log_group" "inventory_service_logs" {
  name              = "/aws/lambda/${local.project_name}-inventory-service"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# Notification Service Lambda Function
resource "aws_lambda_function" "notification_service" {
  function_name = "${local.project_name}-notification-service"
  role         = aws_iam_role.lambda_execution_role.arn
  handler      = "index.lambda_handler"
  runtime      = var.lambda_runtime
  timeout      = var.lambda_timeout

  filename         = data.archive_file.notification_service_zip.output_path
  source_code_hash = data.archive_file.notification_service_zip.output_base64sha256

  environment {
    variables = {
      LOG_LEVEL = var.log_level
    }
  }

  tags = merge(local.common_tags, {
    Service = "NotificationService"
  })

  depends_on = [aws_cloudwatch_log_group.notification_service_logs]
}

# Notification Service Lambda code archive
data "archive_file" "notification_service_zip" {
  type        = "zip"
  output_path = "${path.module}/notification_service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/notification_service.py", {
      log_level = var.log_level
    })
    filename = "index.py"
  }
}

# CloudWatch Log Group for Notification Service
resource "aws_cloudwatch_log_group" "notification_service_logs" {
  name              = "/aws/lambda/${local.project_name}-notification-service"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# ===============================================================================
# Step Functions State Machine
# ===============================================================================

# Step Functions State Machine for microservices orchestration
resource "aws_sfn_state_machine" "microservices_workflow" {
  name     = "${local.project_name}-workflow"
  role_arn = aws_iam_role.stepfunctions_execution_role.arn

  definition = templatefile("${path.module}/state_machine_definition.json", {
    user_service_arn         = aws_lambda_function.user_service.arn
    order_service_arn        = aws_lambda_function.order_service.arn
    payment_service_arn      = aws_lambda_function.payment_service.arn
    inventory_service_arn    = aws_lambda_function.inventory_service.arn
    notification_service_arn = aws_lambda_function.notification_service.arn
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.stepfunctions_logs.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = merge(local.common_tags, {
    Service = "WorkflowOrchestration"
  })

  depends_on = [
    aws_lambda_function.user_service,
    aws_lambda_function.order_service,
    aws_lambda_function.payment_service,
    aws_lambda_function.inventory_service,
    aws_lambda_function.notification_service
  ]
}

# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "stepfunctions_logs" {
  name              = "/aws/stepfunctions/${local.project_name}-workflow"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# ===============================================================================
# EventBridge Integration
# ===============================================================================

# EventBridge rule for triggering the workflow
resource "aws_cloudwatch_event_rule" "microservices_trigger" {
  name        = "${local.project_name}-trigger"
  description = "Trigger microservices workflow on order events"

  event_pattern = jsonencode({
    source      = ["microservices.orders"]
    detail-type = ["Order Submitted"]
  })

  tags = local.common_tags
}

# EventBridge target to trigger Step Functions
resource "aws_cloudwatch_event_target" "stepfunctions_target" {
  rule      = aws_cloudwatch_event_rule.microservices_trigger.name
  target_id = "StepFunctionsTarget"
  arn       = aws_sfn_state_machine.microservices_workflow.arn
  role_arn  = aws_iam_role.eventbridge_stepfunctions_role.arn

  # Transform the EventBridge event to match Step Functions input format
  input_transformer {
    input_paths = {
      userId    = "$.detail.userId"
      orderData = "$.detail.orderData"
    }
    input_template = jsonencode({
      userId    = "<userId>"
      orderData = "<orderData>"
    })
  }
}