# CQRS and Event Sourcing Infrastructure with EventBridge and DynamoDB
# This configuration implements a complete CQRS architecture with Event Sourcing
# using Amazon EventBridge, DynamoDB, and AWS Lambda

# Data Sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  name_prefix                = var.enable_random_suffix ? "${var.project_name}-${random_string.suffix.result}" : var.project_name
  event_bus_name            = "${local.name_prefix}-events"
  event_store_table_name    = "${local.name_prefix}-event-store"
  user_read_model_table     = "${local.name_prefix}-user-profiles"
  order_read_model_table    = "${local.name_prefix}-order-summaries"
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "cqrs-event-sourcing-eventbridge-dynamodb"
  }
}

# ========================================
# DynamoDB Tables
# ========================================

# Event Store Table - The authoritative source of truth for all domain events
# This table stores immutable events with optimistic concurrency control
resource "aws_dynamodb_table" "event_store" {
  name           = local.event_store_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = var.event_store_read_capacity
  write_capacity = var.event_store_write_capacity
  hash_key       = "AggregateId"
  range_key      = "Version"

  # Composite primary key for aggregate versioning and optimistic concurrency
  attribute {
    name = "AggregateId"
    type = "S"
  }

  attribute {
    name = "Version"
    type = "N"
  }

  attribute {
    name = "EventType"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "S"
  }

  # Global Secondary Index for querying events by type and time
  global_secondary_index {
    name               = "EventType-Timestamp-index"
    hash_key           = "EventType"
    range_key          = "Timestamp"
    write_capacity     = var.gsi_write_capacity
    read_capacity      = var.gsi_read_capacity
    projection_type    = "ALL"
  }

  # Enable DynamoDB Streams for real-time event propagation
  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  # Point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name        = local.event_store_table_name
    Purpose     = "Event Store"
    DataPattern = "Event Sourcing"
  })
}

# User Profiles Read Model - Optimized for user lookup operations
resource "aws_dynamodb_table" "user_read_model" {
  name           = local.user_read_model_table
  billing_mode   = "PROVISIONED"
  read_capacity  = var.read_model_read_capacity
  write_capacity = var.read_model_write_capacity
  hash_key       = "UserId"

  attribute {
    name = "UserId"
    type = "S"
  }

  attribute {
    name = "Email"
    type = "S"
  }

  # Global Secondary Index for email-based lookups
  global_secondary_index {
    name               = "Email-index"
    hash_key           = "Email"
    write_capacity     = var.gsi_write_capacity
    read_capacity      = var.gsi_read_capacity
    projection_type    = "ALL"
  }

  # Point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name        = local.user_read_model_table
    Purpose     = "User Read Model"
    DataPattern = "CQRS Query Side"
  })
}

# Order Summaries Read Model - Optimized for order queries
resource "aws_dynamodb_table" "order_read_model" {
  name           = local.order_read_model_table
  billing_mode   = "PROVISIONED"
  read_capacity  = var.read_model_read_capacity
  write_capacity = var.read_model_write_capacity
  hash_key       = "OrderId"

  attribute {
    name = "OrderId"
    type = "S"
  }

  attribute {
    name = "UserId"
    type = "S"
  }

  attribute {
    name = "Status"
    type = "S"
  }

  # Global Secondary Index for user-based order queries
  global_secondary_index {
    name               = "UserId-index"
    hash_key           = "UserId"
    write_capacity     = var.gsi_write_capacity
    read_capacity      = var.gsi_read_capacity
    projection_type    = "ALL"
  }

  # Global Secondary Index for status-based order queries
  global_secondary_index {
    name               = "Status-index"
    hash_key           = "Status"
    write_capacity     = var.gsi_write_capacity
    read_capacity      = var.gsi_read_capacity
    projection_type    = "ALL"
  }

  # Point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name        = local.order_read_model_table
    Purpose     = "Order Read Model"
    DataPattern = "CQRS Query Side"
  })
}

# ========================================
# EventBridge Configuration
# ========================================

# Custom EventBridge Bus for domain events
resource "aws_cloudwatch_event_bus" "domain_events" {
  name = local.event_bus_name

  tags = merge(local.common_tags, {
    Name    = local.event_bus_name
    Purpose = "Domain Event Distribution"
  })
}

# Event Archive for replay capabilities and debugging
resource "aws_cloudwatch_event_archive" "domain_events_archive" {
  name             = "${local.event_bus_name}-archive"
  event_source_arn = aws_cloudwatch_event_bus.domain_events.arn
  description      = "Archive for CQRS event sourcing demo - enables event replay"
  retention_days   = var.event_archive_retention_days

  tags = merge(local.common_tags, {
    Name    = "${local.event_bus_name}-archive"
    Purpose = "Event Archive and Replay"
  })
}

# ========================================
# IAM Roles and Policies
# ========================================

# IAM Role for Command Handler Lambda
resource "aws_iam_role" "command_handler_role" {
  name = "${local.name_prefix}-command-role"

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
    Name    = "${local.name_prefix}-command-role"
    Purpose = "Command Handler Execution Role"
  })
}

# Basic execution policy for command handler
resource "aws_iam_role_policy_attachment" "command_handler_basic" {
  role       = aws_iam_role.command_handler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# DynamoDB policy for event store access (command side)
resource "aws_iam_role_policy" "command_handler_dynamodb" {
  name = "DynamoDBEventStoreAccess"
  role = aws_iam_role.command_handler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Resource = [
          aws_dynamodb_table.event_store.arn,
          "${aws_dynamodb_table.event_store.arn}/*"
        ]
      }
    ]
  })
}

# EventBridge publish policy for stream processor
resource "aws_iam_role_policy" "command_handler_eventbridge" {
  name = "EventBridgePublish"
  role = aws_iam_role.command_handler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "events:PutEvents"
        Resource = aws_cloudwatch_event_bus.domain_events.arn
      }
    ]
  })
}

# IAM Role for Projection Handlers
resource "aws_iam_role" "projection_handler_role" {
  name = "${local.name_prefix}-projection-role"

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
    Name    = "${local.name_prefix}-projection-role"
    Purpose = "Projection Handler Execution Role"
  })
}

# Basic execution policy for projection handlers
resource "aws_iam_role_policy_attachment" "projection_handler_basic" {
  role       = aws_iam_role.projection_handler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# DynamoDB policy for read model access (query side)
resource "aws_iam_role_policy" "projection_handler_dynamodb" {
  name = "ReadModelAccess"
  role = aws_iam_role.projection_handler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.user_read_model.arn,
          "${aws_dynamodb_table.user_read_model.arn}/*",
          aws_dynamodb_table.order_read_model.arn,
          "${aws_dynamodb_table.order_read_model.arn}/*"
        ]
      }
    ]
  })
}

# ========================================
# Lambda Function Deployment Packages
# ========================================

# Package command handler code
data "archive_file" "command_handler_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/command_handler.zip"
  source_file = "${path.module}/lambda_functions/command_handler.py"
}

# Package stream processor code
data "archive_file" "stream_processor_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/stream_processor.zip"
  source_file = "${path.module}/lambda_functions/stream_processor.py"
}

# Package user projection code
data "archive_file" "user_projection_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/user_projection.zip"
  source_file = "${path.module}/lambda_functions/user_projection.py"
}

# Package order projection code
data "archive_file" "order_projection_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/order_projection.zip"
  source_file = "${path.module}/lambda_functions/order_projection.py"
}

# Package query handler code
data "archive_file" "query_handler_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/query_handler.zip"
  source_file = "${path.module}/lambda_functions/query_handler.py"
}

# ========================================
# Lambda Functions
# ========================================

# Command Handler Lambda - Processes business commands and generates events
resource "aws_lambda_function" "command_handler" {
  filename         = data.archive_file.command_handler_zip.output_path
  function_name    = "${local.name_prefix}-command-handler"
  role            = aws_iam_role.command_handler_role.arn
  handler         = "command_handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.command_handler_zip.output_base64sha256

  environment {
    variables = {
      EVENT_STORE_TABLE = aws_dynamodb_table.event_store.name
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-command-handler"
    Purpose = "CQRS Command Processing"
  })

  depends_on = [
    aws_iam_role_policy_attachment.command_handler_basic,
    aws_iam_role_policy.command_handler_dynamodb,
    aws_cloudwatch_log_group.command_handler_logs
  ]
}

# Stream Processor Lambda - Publishes events from DynamoDB Streams to EventBridge
resource "aws_lambda_function" "stream_processor" {
  filename         = data.archive_file.stream_processor_zip.output_path
  function_name    = "${local.name_prefix}-stream-processor"
  role            = aws_iam_role.command_handler_role.arn
  handler         = "stream_processor.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 60
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.stream_processor_zip.output_base64sha256

  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.domain_events.name
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-stream-processor"
    Purpose = "Event Stream Processing"
  })

  depends_on = [
    aws_iam_role_policy_attachment.command_handler_basic,
    aws_iam_role_policy.command_handler_eventbridge,
    aws_cloudwatch_log_group.stream_processor_logs
  ]
}

# User Projection Lambda - Maintains user read model
resource "aws_lambda_function" "user_projection" {
  filename         = data.archive_file.user_projection_zip.output_path
  function_name    = "${local.name_prefix}-user-projection"
  role            = aws_iam_role.projection_handler_role.arn
  handler         = "user_projection.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.user_projection_zip.output_base64sha256

  environment {
    variables = {
      USER_READ_MODEL_TABLE = aws_dynamodb_table.user_read_model.name
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-user-projection"
    Purpose = "User Read Model Projection"
  })

  depends_on = [
    aws_iam_role_policy_attachment.projection_handler_basic,
    aws_iam_role_policy.projection_handler_dynamodb,
    aws_cloudwatch_log_group.user_projection_logs
  ]
}

# Order Projection Lambda - Maintains order read model
resource "aws_lambda_function" "order_projection" {
  filename         = data.archive_file.order_projection_zip.output_path
  function_name    = "${local.name_prefix}-order-projection"
  role            = aws_iam_role.projection_handler_role.arn
  handler         = "order_projection.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.order_projection_zip.output_base64sha256

  environment {
    variables = {
      ORDER_READ_MODEL_TABLE = aws_dynamodb_table.order_read_model.name
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-order-projection"
    Purpose = "Order Read Model Projection"
  })

  depends_on = [
    aws_iam_role_policy_attachment.projection_handler_basic,
    aws_iam_role_policy.projection_handler_dynamodb,
    aws_cloudwatch_log_group.order_projection_logs
  ]
}

# Query Handler Lambda - Serves read requests from read models
resource "aws_lambda_function" "query_handler" {
  filename         = data.archive_file.query_handler_zip.output_path
  function_name    = "${local.name_prefix}-query-handler"
  role            = aws_iam_role.projection_handler_role.arn
  handler         = "query_handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.query_handler_zip.output_base64sha256

  environment {
    variables = {
      USER_READ_MODEL_TABLE  = aws_dynamodb_table.user_read_model.name
      ORDER_READ_MODEL_TABLE = aws_dynamodb_table.order_read_model.name
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-query-handler"
    Purpose = "CQRS Query Processing"
  })

  depends_on = [
    aws_iam_role_policy_attachment.projection_handler_basic,
    aws_iam_role_policy.projection_handler_dynamodb,
    aws_cloudwatch_log_group.query_handler_logs
  ]
}

# ========================================
# DynamoDB Stream Event Source Mapping
# ========================================

# Connect DynamoDB Stream to Stream Processor Lambda
resource "aws_lambda_event_source_mapping" "event_store_stream" {
  event_source_arn  = aws_dynamodb_table.event_store.stream_arn
  function_name     = aws_lambda_function.stream_processor.arn
  starting_position = "LATEST"
  batch_size        = var.stream_batch_size

  depends_on = [aws_lambda_function.stream_processor]
}

# ========================================
# EventBridge Rules and Targets
# ========================================

# EventBridge Rule for User Events
resource "aws_cloudwatch_event_rule" "user_events" {
  name           = "${local.name_prefix}-user-events"
  description    = "Route user-related events to user projection handler"
  event_bus_name = aws_cloudwatch_event_bus.domain_events.name

  event_pattern = jsonencode({
    source       = ["cqrs.demo"]
    detail-type  = ["UserCreated", "UserProfileUpdated"]
  })

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-user-events"
    Purpose = "User Event Routing"
  })
}

# EventBridge Rule for Order Events
resource "aws_cloudwatch_event_rule" "order_events" {
  name           = "${local.name_prefix}-order-events"
  description    = "Route order-related events to order projection handler"
  event_bus_name = aws_cloudwatch_event_bus.domain_events.name

  event_pattern = jsonencode({
    source       = ["cqrs.demo"]
    detail-type  = ["OrderCreated", "OrderStatusUpdated"]
  })

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-order-events"
    Purpose = "Order Event Routing"
  })
}

# EventBridge Target for User Events
resource "aws_cloudwatch_event_target" "user_projection_target" {
  rule           = aws_cloudwatch_event_rule.user_events.name
  event_bus_name = aws_cloudwatch_event_bus.domain_events.name
  target_id      = "UserProjectionTarget"
  arn            = aws_lambda_function.user_projection.arn

  depends_on = [aws_lambda_function.user_projection]
}

# EventBridge Target for Order Events
resource "aws_cloudwatch_event_target" "order_projection_target" {
  rule           = aws_cloudwatch_event_rule.order_events.name
  event_bus_name = aws_cloudwatch_event_bus.domain_events.name
  target_id      = "OrderProjectionTarget"
  arn            = aws_lambda_function.order_projection.arn

  depends_on = [aws_lambda_function.order_projection]
}

# ========================================
# Lambda Permissions for EventBridge
# ========================================

# Permission for EventBridge to invoke User Projection Lambda
resource "aws_lambda_permission" "user_projection_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.user_projection.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.user_events.arn
}

# Permission for EventBridge to invoke Order Projection Lambda
resource "aws_lambda_permission" "order_projection_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.order_projection.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_events.arn
}

# ========================================
# CloudWatch Log Groups
# ========================================

# CloudWatch Log Groups for Lambda Functions (conditional creation)
resource "aws_cloudwatch_log_group" "command_handler_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-command-handler"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name    = "/aws/lambda/${local.name_prefix}-command-handler"
    Purpose = "Command Handler Logs"
  })
}

resource "aws_cloudwatch_log_group" "stream_processor_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-stream-processor"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name    = "/aws/lambda/${local.name_prefix}-stream-processor"
    Purpose = "Stream Processor Logs"
  })
}

resource "aws_cloudwatch_log_group" "user_projection_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-user-projection"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name    = "/aws/lambda/${local.name_prefix}-user-projection"
    Purpose = "User Projection Logs"
  })
}

resource "aws_cloudwatch_log_group" "order_projection_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-order-projection"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name    = "/aws/lambda/${local.name_prefix}-order-projection"
    Purpose = "Order Projection Logs"
  })
}

resource "aws_cloudwatch_log_group" "query_handler_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${local.name_prefix}-query-handler"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name    = "/aws/lambda/${local.name_prefix}-query-handler"
    Purpose = "Query Handler Logs"
  })
}