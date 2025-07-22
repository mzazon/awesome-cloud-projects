# Main Terraform Configuration for Distributed Transaction Processing

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming
locals {
  stack_name = "${var.project_name}-${random_string.suffix.result}"
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    StackName   = local.stack_name
  }
}

# ============================================================================
# DynamoDB Tables
# ============================================================================

# Saga state table for transaction coordination
resource "aws_dynamodb_table" "saga_state" {
  name           = "${local.stack_name}-saga-state"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "TransactionId"
  
  attribute {
    name = "TransactionId"
    type = "S"
  }
  
  # Enable streams for real-time monitoring
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  # TTL for automatic cleanup
  ttl {
    attribute_name = "TTL"
    enabled        = true
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-saga-state"
    Type = "SagaState"
  })
}

# Orders table for order management
resource "aws_dynamodb_table" "orders" {
  name         = "${local.stack_name}-orders"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "OrderId"
  
  attribute {
    name = "OrderId"
    type = "S"
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-orders"
    Type = "OrderData"
  })
}

# Payments table for payment processing
resource "aws_dynamodb_table" "payments" {
  name         = "${local.stack_name}-payments"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "PaymentId"
  
  attribute {
    name = "PaymentId"
    type = "S"
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-payments"
    Type = "PaymentData"
  })
}

# Inventory table for inventory management
resource "aws_dynamodb_table" "inventory" {
  name         = "${local.stack_name}-inventory"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "ProductId"
  
  attribute {
    name = "ProductId"
    type = "S"
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-inventory"
    Type = "InventoryData"
  })
}

# Populate inventory table with sample data
resource "aws_dynamodb_table_item" "inventory_items" {
  count      = length(var.sample_inventory_data)
  table_name = aws_dynamodb_table.inventory.name
  hash_key   = aws_dynamodb_table.inventory.hash_key
  
  item = jsonencode({
    ProductId = {
      S = var.sample_inventory_data[count.index].product_id
    }
    ProductName = {
      S = var.sample_inventory_data[count.index].product_name
    }
    QuantityAvailable = {
      N = tostring(var.sample_inventory_data[count.index].quantity_available)
    }
    Price = {
      N = tostring(var.sample_inventory_data[count.index].price)
    }
    LastUpdated = {
      S = timestamp()
    }
  })
}

# ============================================================================
# SQS Queues
# ============================================================================

# Dead Letter Queue for failed messages
resource "aws_sqs_queue" "dlq" {
  name                              = "${local.stack_name}-dlq.fifo"
  fifo_queue                        = true
  content_based_deduplication       = true
  message_retention_seconds         = 1209600  # 14 days
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-dlq"
    Type = "DeadLetterQueue"
  })
}

# Order processing queue
resource "aws_sqs_queue" "order_processing" {
  name                              = "${local.stack_name}-order-processing.fifo"
  fifo_queue                        = true
  content_based_deduplication       = true
  message_retention_seconds         = 1209600  # 14 days
  visibility_timeout_seconds        = var.sqs_visibility_timeout
  
  # Configure dead letter queue
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-order-processing"
    Type = "OrderProcessingQueue"
  })
}

# Payment processing queue
resource "aws_sqs_queue" "payment_processing" {
  name                              = "${local.stack_name}-payment-processing.fifo"
  fifo_queue                        = true
  content_based_deduplication       = true
  message_retention_seconds         = 1209600  # 14 days
  visibility_timeout_seconds        = var.sqs_visibility_timeout
  
  # Configure dead letter queue
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-payment-processing"
    Type = "PaymentProcessingQueue"
  })
}

# Inventory update queue
resource "aws_sqs_queue" "inventory_update" {
  name                              = "${local.stack_name}-inventory-update.fifo"
  fifo_queue                        = true
  content_based_deduplication       = true
  message_retention_seconds         = 1209600  # 14 days
  visibility_timeout_seconds        = var.sqs_visibility_timeout
  
  # Configure dead letter queue
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-inventory-update"
    Type = "InventoryUpdateQueue"
  })
}

# Compensation queue for rollback operations
resource "aws_sqs_queue" "compensation" {
  name                              = "${local.stack_name}-compensation.fifo"
  fifo_queue                        = true
  content_based_deduplication       = true
  message_retention_seconds         = 1209600  # 14 days
  visibility_timeout_seconds        = var.sqs_visibility_timeout
  
  # Configure dead letter queue
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-compensation"
    Type = "CompensationQueue"
  })
}

# ============================================================================
# IAM Roles and Policies
# ============================================================================

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${local.stack_name}-lambda-role"
  
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
    Name = "${local.stack_name}-lambda-role"
    Type = "LambdaExecutionRole"
  })
}

# Attach basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for DynamoDB access
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${local.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [
          aws_dynamodb_table.saga_state.arn,
          aws_dynamodb_table.orders.arn,
          aws_dynamodb_table.payments.arn,
          aws_dynamodb_table.inventory.arn
        ]
      }
    ]
  })
}

# Custom policy for SQS access
resource "aws_iam_role_policy" "lambda_sqs_policy" {
  name = "${local.stack_name}-lambda-sqs-policy"
  role = aws_iam_role.lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          aws_sqs_queue.order_processing.arn,
          aws_sqs_queue.payment_processing.arn,
          aws_sqs_queue.inventory_update.arn,
          aws_sqs_queue.compensation.arn,
          aws_sqs_queue.dlq.arn
        ]
      }
    ]
  })
}

# ============================================================================
# Lambda Functions
# ============================================================================

# Archive Lambda function code
data "archive_file" "orchestrator_zip" {
  type        = "zip"
  output_path = "${path.module}/orchestrator.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/orchestrator.py", {
      saga_state_table      = aws_dynamodb_table.saga_state.name
      order_queue_url       = aws_sqs_queue.order_processing.url
      compensation_queue_url = aws_sqs_queue.compensation.url
    })
    filename = "orchestrator.py"
  }
}

# Transaction Orchestrator Lambda
resource "aws_lambda_function" "orchestrator" {
  filename         = data.archive_file.orchestrator_zip.output_path
  function_name    = "${local.stack_name}-orchestrator"
  role            = aws_iam_role.lambda_role.arn
  handler         = "orchestrator.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  environment {
    variables = {
      SAGA_STATE_TABLE        = aws_dynamodb_table.saga_state.name
      ORDER_QUEUE_URL         = aws_sqs_queue.order_processing.url
      COMPENSATION_QUEUE_URL  = aws_sqs_queue.compensation.url
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_dynamodb_policy,
    aws_iam_role_policy.lambda_sqs_policy
  ]
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-orchestrator"
    Type = "OrchestratorFunction"
  })
}

# Archive compensation handler function code
data "archive_file" "compensation_handler_zip" {
  type        = "zip"
  output_path = "${path.module}/compensation_handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/compensation_handler.py", {
      saga_state_table = aws_dynamodb_table.saga_state.name
    })
    filename = "compensation_handler.py"
  }
}

# Compensation Handler Lambda
resource "aws_lambda_function" "compensation_handler" {
  filename         = data.archive_file.compensation_handler_zip.output_path
  function_name    = "${local.stack_name}-compensation-handler"
  role            = aws_iam_role.lambda_role.arn
  handler         = "compensation_handler.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  environment {
    variables = {
      SAGA_STATE_TABLE = aws_dynamodb_table.saga_state.name
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_dynamodb_policy,
    aws_iam_role_policy.lambda_sqs_policy
  ]
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-compensation-handler"
    Type = "CompensationHandler"
  })
}

# Archive order service function code
data "archive_file" "order_service_zip" {
  type        = "zip"
  output_path = "${path.module}/order_service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/order_service.py", {
      order_table           = aws_dynamodb_table.orders.name
      saga_state_table      = aws_dynamodb_table.saga_state.name
      payment_queue_url     = aws_sqs_queue.payment_processing.url
      compensation_queue_url = aws_sqs_queue.compensation.url
    })
    filename = "order_service.py"
  }
}

# Order Service Lambda
resource "aws_lambda_function" "order_service" {
  filename         = data.archive_file.order_service_zip.output_path
  function_name    = "${local.stack_name}-order-service"
  role            = aws_iam_role.lambda_role.arn
  handler         = "order_service.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  environment {
    variables = {
      ORDER_TABLE            = aws_dynamodb_table.orders.name
      SAGA_STATE_TABLE       = aws_dynamodb_table.saga_state.name
      PAYMENT_QUEUE_URL      = aws_sqs_queue.payment_processing.url
      COMPENSATION_QUEUE_URL = aws_sqs_queue.compensation.url
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_dynamodb_policy,
    aws_iam_role_policy.lambda_sqs_policy
  ]
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-order-service"
    Type = "OrderService"
  })
}

# Archive payment service function code
data "archive_file" "payment_service_zip" {
  type        = "zip"
  output_path = "${path.module}/payment_service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/payment_service.py", {
      payment_table         = aws_dynamodb_table.payments.name
      saga_state_table      = aws_dynamodb_table.saga_state.name
      inventory_queue_url   = aws_sqs_queue.inventory_update.url
      compensation_queue_url = aws_sqs_queue.compensation.url
    })
    filename = "payment_service.py"
  }
}

# Payment Service Lambda
resource "aws_lambda_function" "payment_service" {
  filename         = data.archive_file.payment_service_zip.output_path
  function_name    = "${local.stack_name}-payment-service"
  role            = aws_iam_role.lambda_role.arn
  handler         = "payment_service.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  environment {
    variables = {
      PAYMENT_TABLE          = aws_dynamodb_table.payments.name
      SAGA_STATE_TABLE       = aws_dynamodb_table.saga_state.name
      INVENTORY_QUEUE_URL    = aws_sqs_queue.inventory_update.url
      COMPENSATION_QUEUE_URL = aws_sqs_queue.compensation.url
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_dynamodb_policy,
    aws_iam_role_policy.lambda_sqs_policy
  ]
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-payment-service"
    Type = "PaymentService"
  })
}

# Archive inventory service function code
data "archive_file" "inventory_service_zip" {
  type        = "zip"
  output_path = "${path.module}/inventory_service.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/inventory_service.py", {
      inventory_table       = aws_dynamodb_table.inventory.name
      saga_state_table      = aws_dynamodb_table.saga_state.name
      compensation_queue_url = aws_sqs_queue.compensation.url
    })
    filename = "inventory_service.py"
  }
}

# Inventory Service Lambda
resource "aws_lambda_function" "inventory_service" {
  filename         = data.archive_file.inventory_service_zip.output_path
  function_name    = "${local.stack_name}-inventory-service"
  role            = aws_iam_role.lambda_role.arn
  handler         = "inventory_service.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  environment {
    variables = {
      INVENTORY_TABLE        = aws_dynamodb_table.inventory.name
      SAGA_STATE_TABLE       = aws_dynamodb_table.saga_state.name
      COMPENSATION_QUEUE_URL = aws_sqs_queue.compensation.url
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_dynamodb_policy,
    aws_iam_role_policy.lambda_sqs_policy
  ]
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-inventory-service"
    Type = "InventoryService"
  })
}

# ============================================================================
# Lambda Event Source Mappings
# ============================================================================

# Event source mapping for order processing
resource "aws_lambda_event_source_mapping" "order_processing" {
  event_source_arn = aws_sqs_queue.order_processing.arn
  function_name    = aws_lambda_function.order_service.arn
  batch_size       = 1
  
  depends_on = [aws_lambda_function.order_service]
}

# Event source mapping for payment processing
resource "aws_lambda_event_source_mapping" "payment_processing" {
  event_source_arn = aws_sqs_queue.payment_processing.arn
  function_name    = aws_lambda_function.payment_service.arn
  batch_size       = 1
  
  depends_on = [aws_lambda_function.payment_service]
}

# Event source mapping for inventory update
resource "aws_lambda_event_source_mapping" "inventory_update" {
  event_source_arn = aws_sqs_queue.inventory_update.arn
  function_name    = aws_lambda_function.inventory_service.arn
  batch_size       = 1
  
  depends_on = [aws_lambda_function.inventory_service]
}

# Event source mapping for compensation handling
resource "aws_lambda_event_source_mapping" "compensation" {
  event_source_arn = aws_sqs_queue.compensation.arn
  function_name    = aws_lambda_function.compensation_handler.arn
  batch_size       = 1
  
  depends_on = [aws_lambda_function.compensation_handler]
}

# ============================================================================
# API Gateway
# ============================================================================

# Create API Gateway REST API
resource "aws_api_gateway_rest_api" "transaction_api" {
  name        = "${local.stack_name}-transaction-api"
  description = "Distributed Transaction Processing API"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-transaction-api"
    Type = "TransactionAPI"
  })
}

# Create transactions resource
resource "aws_api_gateway_resource" "transactions" {
  rest_api_id = aws_api_gateway_rest_api.transaction_api.id
  parent_id   = aws_api_gateway_rest_api.transaction_api.root_resource_id
  path_part   = "transactions"
}

# Create POST method for transactions
resource "aws_api_gateway_method" "transactions_post" {
  rest_api_id   = aws_api_gateway_rest_api.transaction_api.id
  resource_id   = aws_api_gateway_resource.transactions.id
  http_method   = "POST"
  authorization = "NONE"
}

# Create Lambda integration
resource "aws_api_gateway_integration" "transactions_integration" {
  rest_api_id = aws_api_gateway_rest_api.transaction_api.id
  resource_id = aws_api_gateway_resource.transactions.id
  http_method = aws_api_gateway_method.transactions_post.http_method
  
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.orchestrator.invoke_arn
}

# Grant API Gateway permission to invoke Lambda
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.transaction_api.execution_arn}/*/*"
}

# Deploy API Gateway
resource "aws_api_gateway_deployment" "transaction_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.transaction_api.id
  stage_name  = var.api_gateway_stage
  
  depends_on = [
    aws_api_gateway_method.transactions_post,
    aws_api_gateway_integration.transactions_integration
  ]
  
  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# CloudWatch Monitoring (Optional)
# ============================================================================

# CloudWatch alarm for failed transactions
resource "aws_cloudwatch_metric_alarm" "failed_transactions" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.stack_name}-failed-transactions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_threshold
  alarm_description   = "This metric monitors lambda errors"
  
  dimensions = {
    FunctionName = aws_lambda_function.orchestrator.function_name
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-failed-transactions"
    Type = "CloudWatchAlarm"
  })
}

# CloudWatch alarm for SQS message age
resource "aws_cloudwatch_metric_alarm" "sqs_message_age" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.stack_name}-sqs-message-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 600  # 10 minutes
  alarm_description   = "This metric monitors SQS message age"
  
  dimensions = {
    QueueName = aws_sqs_queue.order_processing.name
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-sqs-message-age"
    Type = "CloudWatchAlarm"
  })
}

# CloudWatch dashboard for transaction monitoring
resource "aws_cloudwatch_dashboard" "transaction_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_name = "${local.stack_name}-transactions"
  
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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.orchestrator.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Transaction Orchestrator Metrics"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", aws_sqs_queue.order_processing.name],
            [".", "NumberOfMessagesReceived", ".", "."],
            [".", "ApproximateNumberOfMessagesVisible", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "SQS Queue Metrics"
        }
      }
    ]
  })
}

# ============================================================================
# CloudWatch Log Groups (Optional)
# ============================================================================

# Log group for orchestrator function
resource "aws_cloudwatch_log_group" "orchestrator_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name              = "/aws/lambda/${aws_lambda_function.orchestrator.function_name}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-orchestrator-logs"
    Type = "CloudWatchLogGroup"
  })
}

# Log group for compensation handler
resource "aws_cloudwatch_log_group" "compensation_handler_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name              = "/aws/lambda/${aws_lambda_function.compensation_handler.function_name}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-compensation-handler-logs"
    Type = "CloudWatchLogGroup"
  })
}

# Log group for order service
resource "aws_cloudwatch_log_group" "order_service_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name              = "/aws/lambda/${aws_lambda_function.order_service.function_name}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-order-service-logs"
    Type = "CloudWatchLogGroup"
  })
}

# Log group for payment service
resource "aws_cloudwatch_log_group" "payment_service_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name              = "/aws/lambda/${aws_lambda_function.payment_service.function_name}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-payment-service-logs"
    Type = "CloudWatchLogGroup"
  })
}

# Log group for inventory service
resource "aws_cloudwatch_log_group" "inventory_service_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name              = "/aws/lambda/${aws_lambda_function.inventory_service.function_name}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name = "${local.stack_name}-inventory-service-logs"
    Type = "CloudWatchLogGroup"
  })
}