# Generate random suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Use provided suffix or generate random one
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_string.suffix.result
  
  # Common resource names
  event_bus_name        = "event-sourcing-bus-${local.resource_suffix}"
  event_store_table     = "event-store-${local.resource_suffix}"
  read_model_table      = "read-model-${local.resource_suffix}"
  command_function_name = "command-handler-${local.resource_suffix}"
  projection_function_name = "projection-handler-${local.resource_suffix}"
  query_function_name   = "query-handler-${local.resource_suffix}"
  dlq_name             = "event-sourcing-dlq-${local.resource_suffix}"
  
  # Common tags
  common_tags = {
    Project     = "event-sourcing-architecture"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Data source for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ====================================
# IAM Role for Lambda Functions
# ====================================

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "event-sourcing-lambda-role-${local.resource_suffix}"

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

# Custom policy for EventBridge and DynamoDB access
resource "aws_iam_policy" "event_sourcing_policy" {
  name        = "EventSourcingPolicy-${local.resource_suffix}"
  description = "IAM policy for event sourcing Lambda functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents",
          "events:List*",
          "events:Describe*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [
          aws_dynamodb_table.event_store.arn,
          "${aws_dynamodb_table.event_store.arn}/*",
          aws_dynamodb_table.read_model.arn,
          "${aws_dynamodb_table.read_model.arn}/*"
        ]
      }
    ]
  })

  tags = local.common_tags
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_event_sourcing_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.event_sourcing_policy.arn
}

# ====================================
# EventBridge Custom Bus
# ====================================

# Create custom EventBridge bus
resource "aws_cloudwatch_event_bus" "event_sourcing_bus" {
  name = local.event_bus_name

  tags = merge(local.common_tags, {
    Name = local.event_bus_name
  })
}

# Create event archive for replay capability
resource "aws_cloudwatch_event_archive" "event_archive" {
  name             = "${local.event_bus_name}-archive"
  event_source_arn = aws_cloudwatch_event_bus.event_sourcing_bus.arn
  retention_days   = var.event_archive_retention_days
  description      = "Archive for event replay and audit"

  tags = local.common_tags
}

# ====================================
# DynamoDB Tables
# ====================================

# Event store table with DynamoDB Streams
resource "aws_dynamodb_table" "event_store" {
  name           = local.event_store_table
  billing_mode   = "PROVISIONED"
  read_capacity  = var.event_store_read_capacity
  write_capacity = var.event_store_write_capacity
  hash_key       = "AggregateId"
  range_key      = "EventSequence"

  # Primary key attributes
  attribute {
    name = "AggregateId"
    type = "S"
  }

  attribute {
    name = "EventSequence"
    type = "N"
  }

  # GSI attributes
  attribute {
    name = "EventType"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "S"
  }

  # Global Secondary Index for querying by event type and timestamp
  global_secondary_index {
    name            = "EventType-Timestamp-index"
    hash_key        = "EventType"
    range_key       = "Timestamp"
    read_capacity   = var.event_store_gsi_read_capacity
    write_capacity  = var.event_store_gsi_write_capacity
    projection_type = "ALL"
  }

  # Enable DynamoDB Streams for real-time processing
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = merge(local.common_tags, {
    Name = local.event_store_table
  })
}

# Read model table for CQRS projections
resource "aws_dynamodb_table" "read_model" {
  name           = local.read_model_table
  billing_mode   = "PROVISIONED"
  read_capacity  = var.read_model_read_capacity
  write_capacity = var.read_model_write_capacity
  hash_key       = "AccountId"
  range_key      = "ProjectionType"

  attribute {
    name = "AccountId"
    type = "S"
  }

  attribute {
    name = "ProjectionType"
    type = "S"
  }

  tags = merge(local.common_tags, {
    Name = local.read_model_table
  })
}

# ====================================
# Lambda Functions
# ====================================

# Create Lambda function ZIP files
data "archive_file" "command_handler_zip" {
  type        = "zip"
  output_path = "${path.module}/command-handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/command-handler.py", {
      event_store_table = local.event_store_table
      event_bus_name    = local.event_bus_name
    })
    filename = "command-handler.py"
  }
}

data "archive_file" "projection_handler_zip" {
  type        = "zip"
  output_path = "${path.module}/projection-handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/projection-handler.py", {
      read_model_table = local.read_model_table
    })
    filename = "projection-handler.py"
  }
}

data "archive_file" "query_handler_zip" {
  type        = "zip"
  output_path = "${path.module}/query-handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/query-handler.py", {
      event_store_table = local.event_store_table
      read_model_table  = local.read_model_table
    })
    filename = "query-handler.py"
  }
}

# Command Handler Lambda Function
resource "aws_lambda_function" "command_handler" {
  filename         = data.archive_file.command_handler_zip.output_path
  function_name    = local.command_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "command-handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.command_handler_zip.output_base64sha256

  environment {
    variables = {
      EVENT_STORE_TABLE = aws_dynamodb_table.event_store.name
      EVENT_BUS_NAME    = aws_cloudwatch_event_bus.event_sourcing_bus.name
    }
  }

  tags = merge(local.common_tags, {
    Name = local.command_function_name
  })
}

# Projection Handler Lambda Function
resource "aws_lambda_function" "projection_handler" {
  filename         = data.archive_file.projection_handler_zip.output_path
  function_name    = local.projection_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "projection-handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.projection_handler_zip.output_base64sha256

  environment {
    variables = {
      READ_MODEL_TABLE = aws_dynamodb_table.read_model.name
    }
  }

  tags = merge(local.common_tags, {
    Name = local.projection_function_name
  })
}

# Query Handler Lambda Function
resource "aws_lambda_function" "query_handler" {
  filename         = data.archive_file.query_handler_zip.output_path
  function_name    = local.query_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "query-handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.query_handler_zip.output_base64sha256

  environment {
    variables = {
      EVENT_STORE_TABLE = aws_dynamodb_table.event_store.name
      READ_MODEL_TABLE  = aws_dynamodb_table.read_model.name
    }
  }

  tags = merge(local.common_tags, {
    Name = local.query_function_name
  })
}

# ====================================
# EventBridge Rules and Targets
# ====================================

# EventBridge rule for financial events
resource "aws_cloudwatch_event_rule" "financial_events_rule" {
  name        = "financial-events-rule"
  description = "Route financial events to projection handler"
  event_bus_name = aws_cloudwatch_event_bus.event_sourcing_bus.name

  event_pattern = jsonencode({
    source      = ["event-sourcing.financial"]
    detail-type = ["AccountCreated", "TransactionProcessed", "AccountClosed"]
  })

  tags = local.common_tags
}

# EventBridge target for the projection handler
resource "aws_cloudwatch_event_target" "projection_handler_target" {
  rule      = aws_cloudwatch_event_rule.financial_events_rule.name
  target_id = "ProjectionHandlerTarget"
  arn       = aws_lambda_function.projection_handler.arn
  event_bus_name = aws_cloudwatch_event_bus.event_sourcing_bus.name
}

# Grant EventBridge permission to invoke the projection handler
resource "aws_lambda_permission" "allow_eventbridge_invoke_projection" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.projection_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.financial_events_rule.arn
}

# ====================================
# Dead Letter Queue
# ====================================

# SQS Dead Letter Queue for failed events
resource "aws_sqs_queue" "dead_letter_queue" {
  name                      = local.dlq_name
  message_retention_seconds = var.dlq_message_retention_seconds
  visibility_timeout_seconds = var.dlq_visibility_timeout_seconds

  tags = merge(local.common_tags, {
    Name = local.dlq_name
  })
}

# EventBridge rule for failed events
resource "aws_cloudwatch_event_rule" "failed_events_rule" {
  name        = "failed-events-rule"
  description = "Route failed events to dead letter queue"
  event_bus_name = aws_cloudwatch_event_bus.event_sourcing_bus.name

  event_pattern = jsonencode({
    source      = ["aws.events"]
    detail-type = ["Event Processing Failed"]
  })

  tags = local.common_tags
}

# EventBridge target for dead letter queue
resource "aws_cloudwatch_event_target" "dlq_target" {
  rule      = aws_cloudwatch_event_rule.failed_events_rule.name
  target_id = "DeadLetterQueueTarget"
  arn       = aws_sqs_queue.dead_letter_queue.arn
  event_bus_name = aws_cloudwatch_event_bus.event_sourcing_bus.name
}

# ====================================
# CloudWatch Monitoring
# ====================================

# CloudWatch alarm for DynamoDB write throttles
resource "aws_cloudwatch_metric_alarm" "event_store_write_throttles" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "EventStore-WriteThrottles-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "DynamoDB write throttles on event store"
  alarm_unit          = "Count"

  dimensions = {
    TableName = aws_dynamodb_table.event_store.name
  }

  tags = local.common_tags
}

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "command_handler_errors" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "CommandHandler-Errors-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "High error rate in command handler"
  alarm_unit          = "Count"

  dimensions = {
    FunctionName = aws_lambda_function.command_handler.function_name
  }

  tags = local.common_tags
}

# CloudWatch alarm for EventBridge failed invocations
resource "aws_cloudwatch_metric_alarm" "eventbridge_failed_invocations" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "EventBridge-FailedInvocations-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "High number of failed event invocations"
  alarm_unit          = "Count"

  dimensions = {
    EventBusName = aws_cloudwatch_event_bus.event_sourcing_bus.name
  }

  tags = local.common_tags
}