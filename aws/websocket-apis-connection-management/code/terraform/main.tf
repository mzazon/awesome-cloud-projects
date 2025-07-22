# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values for resource naming and configuration
locals {
  name_prefix    = "${var.project_name}-${var.environment}"
  resource_suffix = random_string.suffix.result
  
  # DynamoDB table names
  connections_table_name = "${local.name_prefix}-connections-${local.resource_suffix}"
  rooms_table_name       = "${local.name_prefix}-rooms-${local.resource_suffix}"
  messages_table_name    = "${local.name_prefix}-messages-${local.resource_suffix}"
  
  # Lambda function names
  connect_function_name    = "${local.name_prefix}-connect-${local.resource_suffix}"
  disconnect_function_name = "${local.name_prefix}-disconnect-${local.resource_suffix}"
  message_function_name    = "${local.name_prefix}-message-${local.resource_suffix}"
  
  # API Gateway configuration
  api_name = "${var.api_name}-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# KMS key for encryption
resource "aws_kms_key" "websocket_key" {
  count = var.enable_encryption ? 1 : 0
  
  description             = "KMS key for WebSocket API encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-websocket-key"
  })
}

resource "aws_kms_alias" "websocket_key_alias" {
  count = var.enable_encryption ? 1 : 0
  
  name          = "alias/${local.name_prefix}-websocket-key"
  target_key_id = aws_kms_key.websocket_key[0].key_id
}

# DynamoDB Tables
# Connections table - stores active WebSocket connections
resource "aws_dynamodb_table" "connections" {
  name           = local.connections_table_name
  billing_mode   = var.dynamodb_billing_mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  hash_key       = "connectionId"
  table_class    = var.dynamodb_table_class

  attribute {
    name = "connectionId"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "roomId"
    type = "S"
  }

  # Global Secondary Index for querying by userId
  global_secondary_index {
    name               = "UserIndex"
    hash_key           = "userId"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  # Global Secondary Index for querying by roomId
  global_secondary_index {
    name               = "RoomIndex"
    hash_key           = "roomId"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_dynamodb_point_in_time_recovery
  }

  # Enable encryption
  dynamic "server_side_encryption" {
    for_each = var.enable_encryption ? [1] : []
    content {
      enabled     = true
      kms_key_id  = aws_kms_key.websocket_key[0].arn
    }
  }

  # Enable TTL for automatic cleanup (optional)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = merge(local.common_tags, {
    Name = local.connections_table_name
    Type = "WebSocket-Connections"
  })
}

# Rooms table - stores room information and metadata
resource "aws_dynamodb_table" "rooms" {
  name           = local.rooms_table_name
  billing_mode   = var.dynamodb_billing_mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  hash_key       = "roomId"
  table_class    = var.dynamodb_table_class

  attribute {
    name = "roomId"
    type = "S"
  }

  attribute {
    name = "ownerId"
    type = "S"
  }

  # Global Secondary Index for querying by ownerId
  global_secondary_index {
    name               = "OwnerIndex"
    hash_key           = "ownerId"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_dynamodb_point_in_time_recovery
  }

  # Enable encryption
  dynamic "server_side_encryption" {
    for_each = var.enable_encryption ? [1] : []
    content {
      enabled     = true
      kms_key_id  = aws_kms_key.websocket_key[0].arn
    }
  }

  tags = merge(local.common_tags, {
    Name = local.rooms_table_name
    Type = "WebSocket-Rooms"
  })
}

# Messages table - stores message history and metadata
resource "aws_dynamodb_table" "messages" {
  name           = local.messages_table_name
  billing_mode   = var.dynamodb_billing_mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  hash_key       = "messageId"
  table_class    = var.dynamodb_table_class

  attribute {
    name = "messageId"
    type = "S"
  }

  attribute {
    name = "roomId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  # Global Secondary Index for querying messages by room and timestamp
  global_secondary_index {
    name               = "RoomTimestampIndex"
    hash_key           = "roomId"
    range_key          = "timestamp"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_dynamodb_point_in_time_recovery
  }

  # Enable encryption
  dynamic "server_side_encryption" {
    for_each = var.enable_encryption ? [1] : []
    content {
      enabled     = true
      kms_key_id  = aws_kms_key.websocket_key[0].arn
    }
  }

  # Enable TTL for automatic message cleanup (optional)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = merge(local.common_tags, {
    Name = local.messages_table_name
    Type = "WebSocket-Messages"
  })
}

# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role-${local.resource_suffix}"

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
    Name = "${local.name_prefix}-lambda-role"
  })
}

# IAM Policy for Lambda functions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_prefix}-lambda-policy-${local.resource_suffix}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = [
          aws_dynamodb_table.connections.arn,
          "${aws_dynamodb_table.connections.arn}/index/*",
          aws_dynamodb_table.rooms.arn,
          "${aws_dynamodb_table.rooms.arn}/index/*",
          aws_dynamodb_table.messages.arn,
          "${aws_dynamodb_table.messages.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "execute-api:ManageConnections"
        ]
        Resource = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*/@connections/*"
      }
    ]
  })
}

# Attach basic execution role to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach X-Ray tracing policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_xray_execution" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "connect_logs" {
  name              = "/aws/lambda/${local.connect_function_name}"
  retention_in_days = var.log_retention_days

  dynamic "kms_key_id" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_key_id = aws_kms_key.websocket_key[0].arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.connect_function_name}-logs"
  })
}

resource "aws_cloudwatch_log_group" "disconnect_logs" {
  name              = "/aws/lambda/${local.disconnect_function_name}"
  retention_in_days = var.log_retention_days

  dynamic "kms_key_id" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_key_id = aws_kms_key.websocket_key[0].arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.disconnect_function_name}-logs"
  })
}

resource "aws_cloudwatch_log_group" "message_logs" {
  name              = "/aws/lambda/${local.message_function_name}"
  retention_in_days = var.log_retention_days

  dynamic "kms_key_id" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_key_id = aws_kms_key.websocket_key[0].arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.message_function_name}-logs"
  })
}

# Create Lambda deployment packages
data "archive_file" "connect_handler" {
  type        = "zip"
  output_path = "${path.module}/connect_handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda/connect_handler.py", {
      connections_table = local.connections_table_name
    })
    filename = "connect_handler.py"
  }
}

data "archive_file" "disconnect_handler" {
  type        = "zip"
  output_path = "${path.module}/disconnect_handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda/disconnect_handler.py", {
      connections_table = local.connections_table_name
    })
    filename = "disconnect_handler.py"
  }
}

data "archive_file" "message_handler" {
  type        = "zip"
  output_path = "${path.module}/lambda/message_handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda/message_handler.py", {
      connections_table = local.connections_table_name
      rooms_table       = local.rooms_table_name
      messages_table    = local.messages_table_name
    })
    filename = "message_handler.py"
  }
}

# Lambda function for WebSocket connection handling
resource "aws_lambda_function" "connect_handler" {
  filename      = data.archive_file.connect_handler.output_path
  function_name = local.connect_function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "connect_handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  source_code_hash = data.archive_file.connect_handler.output_base64sha256

  environment {
    variables = {
      CONNECTIONS_TABLE = aws_dynamodb_table.connections.name
      REGION           = data.aws_region.current.name
    }
  }

  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.connect_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]

  tags = merge(local.common_tags, {
    Name = local.connect_function_name
    Type = "WebSocket-Connect"
  })
}

# Lambda function for WebSocket disconnection handling
resource "aws_lambda_function" "disconnect_handler" {
  filename      = data.archive_file.disconnect_handler.output_path
  function_name = local.disconnect_function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "disconnect_handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  source_code_hash = data.archive_file.disconnect_handler.output_base64sha256

  environment {
    variables = {
      CONNECTIONS_TABLE = aws_dynamodb_table.connections.name
      REGION           = data.aws_region.current.name
    }
  }

  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.disconnect_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]

  tags = merge(local.common_tags, {
    Name = local.disconnect_function_name
    Type = "WebSocket-Disconnect"
  })
}

# Lambda function for WebSocket message handling
resource "aws_lambda_function" "message_handler" {
  filename      = data.archive_file.message_handler.output_path
  function_name = local.message_function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "message_handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_message_timeout
  memory_size   = var.lambda_message_memory_size

  source_code_hash = data.archive_file.message_handler.output_base64sha256

  environment {
    variables = {
      CONNECTIONS_TABLE = aws_dynamodb_table.connections.name
      ROOMS_TABLE       = aws_dynamodb_table.rooms.name
      MESSAGES_TABLE    = aws_dynamodb_table.messages.name
      REGION           = data.aws_region.current.name
    }
  }

  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.message_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]

  tags = merge(local.common_tags, {
    Name = local.message_function_name
    Type = "WebSocket-Message"
  })
}

# WebSocket API Gateway
resource "aws_apigatewayv2_api" "websocket_api" {
  name                       = local.api_name
  protocol_type             = "WEBSOCKET"
  route_selection_expression = var.route_selection_expression
  description               = var.api_description

  tags = merge(local.common_tags, {
    Name = local.api_name
    Type = "WebSocket-API"
  })
}

# API Gateway integrations
resource "aws_apigatewayv2_integration" "connect_integration" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.connect_handler.invoke_arn
}

resource "aws_apigatewayv2_integration" "disconnect_integration" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.disconnect_handler.invoke_arn
}

resource "aws_apigatewayv2_integration" "message_integration" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.message_handler.invoke_arn
}

# API Gateway routes
resource "aws_apigatewayv2_route" "connect_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.connect_integration.id}"
}

resource "aws_apigatewayv2_route" "disconnect_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.disconnect_integration.id}"
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.message_integration.id}"
}

# Custom routes
resource "aws_apigatewayv2_route" "custom_routes" {
  for_each = toset(var.custom_routes)
  
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.message_integration.id}"
}

# API Gateway deployment
resource "aws_apigatewayv2_deployment" "websocket_deployment" {
  api_id = aws_apigatewayv2_api.websocket_api.id

  depends_on = [
    aws_apigatewayv2_route.connect_route,
    aws_apigatewayv2_route.disconnect_route,
    aws_apigatewayv2_route.default_route,
    aws_apigatewayv2_route.custom_routes,
  ]

  lifecycle {
    create_before_destroy = true
  }

  triggers = {
    redeployment = sha1(jsonencode([
      aws_apigatewayv2_route.connect_route.id,
      aws_apigatewayv2_route.disconnect_route.id,
      aws_apigatewayv2_route.default_route.id,
      aws_apigatewayv2_integration.connect_integration.id,
      aws_apigatewayv2_integration.disconnect_integration.id,
      aws_apigatewayv2_integration.message_integration.id,
    ]))
  }
}

# API Gateway stage
resource "aws_apigatewayv2_stage" "websocket_stage" {
  api_id        = aws_apigatewayv2_api.websocket_api.id
  name          = var.stage_name
  deployment_id = aws_apigatewayv2_deployment.websocket_deployment.id
  description   = "${title(var.stage_name)} stage for WebSocket API"

  default_route_settings {
    detailed_metrics_enabled = var.enable_detailed_metrics
    logging_level            = var.logging_level
    data_trace_enabled       = var.enable_data_trace
    throttling_burst_limit   = var.throttling_burst_limit
    throttling_rate_limit    = var.throttling_rate_limit
  }

  tags = merge(local.common_tags, {
    Name = "${local.api_name}-${var.stage_name}"
    Type = "WebSocket-Stage"
  })
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "connect_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.connect_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "disconnect_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.disconnect_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "message_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.message_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}