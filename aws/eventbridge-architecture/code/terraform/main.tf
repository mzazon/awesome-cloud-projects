# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for resource names to ensure uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with random suffix
  event_bus_name          = "${var.custom_event_bus_name}-${random_id.suffix.hex}"
  lambda_function_name    = "${var.lambda_function_name}-${random_id.suffix.hex}"
  sns_topic_name         = "${var.sns_topic_name}-${random_id.suffix.hex}"
  sqs_queue_name         = "${var.sqs_queue_name}-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
  })
}

# ===========================
# EventBridge Custom Event Bus
# ===========================

# Create custom EventBridge event bus for e-commerce events
resource "aws_cloudwatch_event_bus" "ecommerce_events" {
  name = local.event_bus_name

  tags = merge(local.common_tags, {
    Name        = local.event_bus_name
    Description = "Custom event bus for e-commerce events"
  })
}

# ===========================
# SNS Topic for Notifications
# ===========================

# Create SNS topic for order notifications
resource "aws_sns_topic" "order_notifications" {
  name = local.sns_topic_name

  tags = merge(local.common_tags, {
    Name        = local.sns_topic_name
    Description = "SNS topic for order notifications"
  })
}

# ===========================
# SQS Queue for Event Processing
# ===========================

# Create SQS queue for batch event processing
resource "aws_sqs_queue" "event_processing" {
  name = local.sqs_queue_name

  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention_period

  tags = merge(local.common_tags, {
    Name        = local.sqs_queue_name
    Description = "SQS queue for batch event processing"
  })
}

# ===========================
# IAM Roles and Policies
# ===========================

# IAM role for EventBridge to invoke targets
resource "aws_iam_role" "eventbridge_execution_role" {
  name = "EventBridgeExecutionRole-${random_id.suffix.hex}"

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

  tags = merge(local.common_tags, {
    Name        = "EventBridgeExecutionRole-${random_id.suffix.hex}"
    Description = "IAM role for EventBridge execution"
  })
}

# IAM policy for EventBridge to access targets
resource "aws_iam_role_policy" "eventbridge_targets_policy" {
  name = "EventBridgeTargetsPolicy"
  role = aws_iam_role.eventbridge_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.order_notifications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.event_processing.arn
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.event_processor.arn
      }
    ]
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "EventProcessorLambdaRole-${random_id.suffix.hex}"

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
    Name        = "EventProcessorLambdaRole-${random_id.suffix.hex}"
    Description = "IAM role for Lambda function execution"
  })
}

# Attach basic execution role to Lambda
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

# ===========================
# Lambda Function
# ===========================

# Create Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/event_processor.zip"
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      event_bus_name = local.event_bus_name
    })
    filename = "event_processor.py"
  }
}

# Create Lambda function for event processing
resource "aws_lambda_function" "event_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "event_processor.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  environment {
    variables = {
      EVENT_BUS_NAME = local.event_bus_name
      LOG_LEVEL      = "INFO"
    }
  }

  tags = merge(local.common_tags, {
    Name        = local.lambda_function_name
    Description = "Lambda function for processing EventBridge events"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs,
  ]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.common_tags, {
    Name        = "/aws/lambda/${local.lambda_function_name}"
    Description = "CloudWatch log group for Lambda function"
  })
}

# ===========================
# EventBridge Rules
# ===========================

# Rule 1: Route all order events to Lambda
resource "aws_cloudwatch_event_rule" "order_events_rule" {
  name           = "OrderEventsRule"
  description    = "Route order events to Lambda processor"
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_events.name

  event_pattern = jsonencode({
    source       = ["ecommerce.orders"]
    detail-type  = ["Order Created", "Order Updated", "Order Cancelled"]
  })

  tags = merge(local.common_tags, {
    Name        = "OrderEventsRule"
    Description = "EventBridge rule for order events"
  })
}

# Target for order events rule - Lambda function
resource "aws_cloudwatch_event_target" "order_events_lambda_target" {
  rule           = aws_cloudwatch_event_rule.order_events_rule.name
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_events.name
  target_id      = "OrderEventsLambdaTarget"
  arn            = aws_lambda_function.event_processor.arn
}

# Permission for EventBridge to invoke Lambda for order events
resource "aws_lambda_permission" "allow_eventbridge_order_events" {
  statement_id  = "AllowEventBridgeOrderEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.event_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_events_rule.arn
}

# Rule 2: Route high-value orders to SNS for immediate notification
resource "aws_cloudwatch_event_rule" "high_value_orders_rule" {
  name           = "HighValueOrdersRule"
  description    = "Route high-value orders to SNS for notifications"
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_events.name

  event_pattern = jsonencode({
    source      = ["ecommerce.orders"]
    detail-type = ["Order Created"]
    detail = {
      totalAmount = [
        {
          numeric = [">", var.high_value_order_threshold]
        }
      ]
    }
  })

  tags = merge(local.common_tags, {
    Name        = "HighValueOrdersRule"
    Description = "EventBridge rule for high-value orders"
  })
}

# Target for high-value orders rule - SNS topic
resource "aws_cloudwatch_event_target" "high_value_orders_sns_target" {
  rule           = aws_cloudwatch_event_rule.high_value_orders_rule.name
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_events.name
  target_id      = "HighValueOrdersSNSTarget"
  arn            = aws_sns_topic.order_notifications.arn
  role_arn       = aws_iam_role.eventbridge_execution_role.arn
}

# Rule 3: Route all events to SQS for batch processing
resource "aws_cloudwatch_event_rule" "all_events_sqs_rule" {
  name           = "AllEventsToSQSRule"
  description    = "Route all events to SQS for batch processing"
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_events.name

  event_pattern = jsonencode({
    source = ["ecommerce.orders", "ecommerce.users", "ecommerce.payments"]
  })

  tags = merge(local.common_tags, {
    Name        = "AllEventsToSQSRule"
    Description = "EventBridge rule for all events to SQS"
  })
}

# Target for all events rule - SQS queue
resource "aws_cloudwatch_event_target" "all_events_sqs_target" {
  rule           = aws_cloudwatch_event_rule.all_events_sqs_rule.name
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_events.name
  target_id      = "AllEventsSQSTarget"
  arn            = aws_sqs_queue.event_processing.arn
  role_arn       = aws_iam_role.eventbridge_execution_role.arn
}

# Rule 4: Route user registration events to Lambda
resource "aws_cloudwatch_event_rule" "user_registration_rule" {
  name           = "UserRegistrationRule"
  description    = "Route user registration events to Lambda"
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_events.name

  event_pattern = jsonencode({
    source      = ["ecommerce.users"]
    detail-type = ["User Registered"]
  })

  tags = merge(local.common_tags, {
    Name        = "UserRegistrationRule"
    Description = "EventBridge rule for user registration events"
  })
}

# Target for user registration rule - Lambda function
resource "aws_cloudwatch_event_target" "user_registration_lambda_target" {
  rule           = aws_cloudwatch_event_rule.user_registration_rule.name
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_events.name
  target_id      = "UserRegistrationLambdaTarget"
  arn            = aws_lambda_function.event_processor.arn
}

# Permission for EventBridge to invoke Lambda for user events
resource "aws_lambda_permission" "allow_eventbridge_user_events" {
  statement_id  = "AllowEventBridgeUserEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.event_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.user_registration_rule.arn
}

# ===========================
# Lambda Function Template
# ===========================

# Create Lambda function template file
resource "local_file" "lambda_function_template" {
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    event_bus_name = local.event_bus_name
  })
  filename = "${path.module}/lambda_function.py"
}