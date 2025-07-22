# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Local values for computed names and configurations
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_string.suffix.result
  
  # Resource names with fallbacks
  appsync_api_name        = var.appsync_api_name != "" ? var.appsync_api_name : "${local.name_prefix}-api-${local.name_suffix}"
  cognito_user_pool_name  = var.cognito_user_pool_name != "" ? var.cognito_user_pool_name : "${local.name_prefix}-users-${local.name_suffix}"
  messages_table_name     = var.messages_table_name != "" ? var.messages_table_name : "${local.name_prefix}-messages-${local.name_suffix}"
  conversations_table_name = var.conversations_table_name != "" ? var.conversations_table_name : "${local.name_prefix}-conversations-${local.name_suffix}"
  users_table_name        = var.users_table_name != "" ? var.users_table_name : "${local.name_prefix}-users-${local.name_suffix}"
  
  # Common tags
  common_tags = var.enable_cost_tags ? {
    Project      = var.project_name
    Environment  = var.environment
    ManagedBy    = "Terraform"
    CreatedBy    = data.aws_caller_identity.current.user_id
    Recipe       = "real-time-chat-applications-appsync-graphql"
    CostCenter   = var.project_name
    Application  = "realtime-chat"
  } : {}
}

# ===================================
# Amazon Cognito User Pool
# ===================================

resource "aws_cognito_user_pool" "chat_users" {
  name = local.cognito_user_pool_name

  # Password policy configuration
  password_policy {
    minimum_length                   = var.password_minimum_length
    require_lowercase               = true
    require_numbers                 = true
    require_symbols                 = true
    require_uppercase               = true
    temporary_password_validity_days = 7
  }

  # Auto-verified attributes
  auto_verified_attributes = var.auto_verified_attributes

  # Username configuration
  username_attributes = ["email"]
  
  # Enable advanced security if specified
  dynamic "user_pool_add_ons" {
    for_each = var.enable_advanced_security ? [1] : []
    content {
      advanced_security_mode = "ENFORCED"
    }
  }

  # Account recovery settings
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Schema for additional user attributes
  schema {
    name                = "email"
    attribute_data_type = "String"
    required           = true
    mutable           = true
  }

  schema {
    name                = "username"
    attribute_data_type = "String"
    required           = true
    mutable           = false
  }

  tags = local.common_tags
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "chat_client" {
  name         = "${local.cognito_user_pool_name}-client"
  user_pool_id = aws_cognito_user_pool.chat_users.id

  # Enable explicit auth flows for password-based authentication
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  # Token validity configuration
  access_token_validity  = 1   # 1 hour
  id_token_validity     = 1   # 1 hour
  refresh_token_validity = 30  # 30 days

  # Security settings
  generate_secret                      = true
  prevent_user_existence_errors       = "ENABLED"
  enable_token_revocation             = true
  enable_propagate_additional_user_context_data = false

  # Read and write attributes
  read_attributes  = ["email", "email_verified"]
  write_attributes = ["email"]

  depends_on = [aws_cognito_user_pool.chat_users]
}

# ===================================
# DynamoDB Tables
# ===================================

# Messages Table - stores all chat messages
resource "aws_dynamodb_table" "messages" {
  name           = local.messages_table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "conversationId"
  range_key      = "messageId"

  # Capacity configuration (only used if billing_mode is PROVISIONED)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  # Attributes
  attribute {
    name = "conversationId"
    type = "S"
  }

  attribute {
    name = "messageId"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  # Global Secondary Index for querying messages by conversation and time
  global_secondary_index {
    name               = "MessagesByTime"
    hash_key           = "conversationId"
    range_key          = "createdAt"
    projection_type    = "ALL"
    
    # Capacity for GSI (only used if billing_mode is PROVISIONED)
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  # Global Secondary Index for querying messages by user
  global_secondary_index {
    name               = "MessagesByUser"
    hash_key           = "userId"
    range_key          = "createdAt"
    projection_type    = "ALL"
    
    # Capacity for GSI (only used if billing_mode is PROVISIONED)
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  # DynamoDB Streams configuration
  dynamic "stream_specification" {
    for_each = var.enable_dynamodb_streams ? [1] : []
    content {
      enabled   = true
      view_type = var.dynamodb_stream_view_type
    }
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  # Deletion protection
  deletion_protection_enabled = var.enable_deletion_protection

  tags = merge(local.common_tags, {
    Name = local.messages_table_name
    Type = "Messages"
  })
}

# Conversations Table - stores conversation metadata
resource "aws_dynamodb_table" "conversations" {
  name           = local.conversations_table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "conversationId"

  # Capacity configuration (only used if billing_mode is PROVISIONED)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  # Attributes
  attribute {
    name = "conversationId"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "lastMessageAt"
    type = "S"
  }

  # Global Secondary Index for querying conversations by user
  global_secondary_index {
    name               = "UserConversations"
    hash_key           = "userId"
    range_key          = "lastMessageAt"
    projection_type    = "ALL"
    
    # Capacity for GSI (only used if billing_mode is PROVISIONED)
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  # Deletion protection
  deletion_protection_enabled = var.enable_deletion_protection

  tags = merge(local.common_tags, {
    Name = local.conversations_table_name
    Type = "Conversations"
  })
}

# Users Table - stores user profiles and presence information
resource "aws_dynamodb_table" "users" {
  name           = local.users_table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "userId"

  # Capacity configuration (only used if billing_mode is PROVISIONED)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  # Attributes
  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  # Global Secondary Index for querying users by email
  global_secondary_index {
    name               = "UsersByEmail"
    hash_key           = "email"
    projection_type    = "ALL"
    
    # Capacity for GSI (only used if billing_mode is PROVISIONED)
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  # Deletion protection
  deletion_protection_enabled = var.enable_deletion_protection

  tags = merge(local.common_tags, {
    Name = local.users_table_name
    Type = "Users"
  })
}

# ===================================
# IAM Roles and Policies
# ===================================

# IAM role for AppSync to access DynamoDB tables
data "aws_iam_policy_document" "appsync_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["appsync.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "appsync_dynamodb_role" {
  name               = "${local.name_prefix}-appsync-dynamodb-role-${local.name_suffix}"
  assume_role_policy = data.aws_iam_policy_document.appsync_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-appsync-dynamodb-role"
    Type = "ServiceRole"
  })
}

# IAM policy for AppSync to access DynamoDB tables
data "aws_iam_policy_document" "appsync_dynamodb_policy" {
  statement {
    effect = "Allow"
    
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem"
    ]
    
    resources = [
      aws_dynamodb_table.messages.arn,
      "${aws_dynamodb_table.messages.arn}/index/*",
      aws_dynamodb_table.conversations.arn,
      "${aws_dynamodb_table.conversations.arn}/index/*",
      aws_dynamodb_table.users.arn,
      "${aws_dynamodb_table.users.arn}/index/*"
    ]
  }
}

resource "aws_iam_role_policy" "appsync_dynamodb_policy" {
  name   = "DynamoDBAccess"
  role   = aws_iam_role.appsync_dynamodb_role.id
  policy = data.aws_iam_policy_document.appsync_dynamodb_policy.json
}

# CloudWatch Logs role for AppSync (if logging is enabled)
resource "aws_iam_role" "appsync_logs_role" {
  count = var.enable_appsync_logging ? 1 : 0
  
  name               = "${local.name_prefix}-appsync-logs-role-${local.name_suffix}"
  assume_role_policy = data.aws_iam_policy_document.appsync_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-appsync-logs-role"
    Type = "ServiceRole"
  })
}

# CloudWatch Logs policy for AppSync
data "aws_iam_policy_document" "appsync_logs_policy" {
  count = var.enable_appsync_logging ? 1 : 0
  
  statement {
    effect = "Allow"
    
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

resource "aws_iam_role_policy" "appsync_logs_policy" {
  count = var.enable_appsync_logging ? 1 : 0
  
  name   = "CloudWatchLogsAccess"
  role   = aws_iam_role.appsync_logs_role[0].id
  policy = data.aws_iam_policy_document.appsync_logs_policy[0].json
}

# ===================================
# AWS AppSync GraphQL API
# ===================================

# AppSync GraphQL API
resource "aws_appsync_graphql_api" "chat_api" {
  name                = local.appsync_api_name
  authentication_type = "AMAZON_COGNITO_USER_POOLS"

  # Cognito User Pool configuration
  user_pool_config {
    aws_region     = data.aws_region.current.name
    default_action = "ALLOW"
    user_pool_id   = aws_cognito_user_pool.chat_users.id
  }

  # Enhanced metrics configuration
  dynamic "enhanced_metrics_config" {
    for_each = var.enable_enhanced_metrics ? [1] : []
    content {
      data_source_level_metrics_behavior = "PER_DATA_SOURCE_METRICS"
      operation_level_metrics_config     = "ENABLED"
      resolver_level_metrics_behavior    = "PER_RESOLVER_METRICS"
    }
  }

  # CloudWatch logging configuration
  dynamic "log_config" {
    for_each = var.enable_appsync_logging ? [1] : []
    content {
      cloudwatch_logs_role_arn = aws_iam_role.appsync_logs_role[0].arn
      field_log_level         = var.appsync_log_level
    }
  }

  # GraphQL schema
  schema = file("${path.module}/schema.graphql")

  tags = merge(local.common_tags, {
    Name = local.appsync_api_name
    Type = "GraphQL-API"
  })

  depends_on = [
    aws_cognito_user_pool.chat_users,
    aws_iam_role_policy.appsync_logs_policy
  ]
}

# ===================================
# AppSync Data Sources
# ===================================

# Data source for Messages table
resource "aws_appsync_datasource" "messages_table" {
  api_id           = aws_appsync_graphql_api.chat_api.id
  name             = "MessagesTable"
  service_role_arn = aws_iam_role.appsync_dynamodb_role.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = aws_dynamodb_table.messages.name
    region     = data.aws_region.current.name
  }
}

# Data source for Conversations table
resource "aws_appsync_datasource" "conversations_table" {
  api_id           = aws_appsync_graphql_api.chat_api.id
  name             = "ConversationsTable"
  service_role_arn = aws_iam_role.appsync_dynamodb_role.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = aws_dynamodb_table.conversations.name
    region     = data.aws_region.current.name
  }
}

# Data source for Users table
resource "aws_appsync_datasource" "users_table" {
  api_id           = aws_appsync_graphql_api.chat_api.id
  name             = "UsersTable"
  service_role_arn = aws_iam_role.appsync_dynamodb_role.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = aws_dynamodb_table.users.name
    region     = data.aws_region.current.name
  }
}

# ===================================
# AppSync Resolvers
# ===================================

# sendMessage mutation resolver
resource "aws_appsync_resolver" "send_message" {
  api_id      = aws_appsync_graphql_api.chat_api.id
  field       = "sendMessage"
  type        = "Mutation"
  data_source = aws_appsync_datasource.messages_table.name

  request_template = templatefile("${path.module}/resolvers/send_message_request.vtl", {
    table_name = aws_dynamodb_table.messages.name
  })

  response_template = file("${path.module}/resolvers/send_message_response.vtl")
}

# listMessages query resolver
resource "aws_appsync_resolver" "list_messages" {
  api_id      = aws_appsync_graphql_api.chat_api.id
  field       = "listMessages"
  type        = "Query"
  data_source = aws_appsync_datasource.messages_table.name

  request_template = templatefile("${path.module}/resolvers/list_messages_request.vtl", {
    table_name = aws_dynamodb_table.messages.name
  })

  response_template = file("${path.module}/resolvers/list_messages_response.vtl")
}

# createConversation mutation resolver
resource "aws_appsync_resolver" "create_conversation" {
  api_id      = aws_appsync_graphql_api.chat_api.id
  field       = "createConversation"
  type        = "Mutation"
  data_source = aws_appsync_datasource.conversations_table.name

  request_template = templatefile("${path.module}/resolvers/create_conversation_request.vtl", {
    table_name = aws_dynamodb_table.conversations.name
  })

  response_template = file("${path.module}/resolvers/create_conversation_response.vtl")
}

# listConversations query resolver
resource "aws_appsync_resolver" "list_conversations" {
  api_id      = aws_appsync_graphql_api.chat_api.id
  field       = "listConversations"
  type        = "Query"
  data_source = aws_appsync_datasource.conversations_table.name

  request_template = templatefile("${path.module}/resolvers/list_conversations_request.vtl", {
    table_name = aws_dynamodb_table.conversations.name
  })

  response_template = file("${path.module}/resolvers/list_conversations_response.vtl")
}

# updateUserPresence mutation resolver
resource "aws_appsync_resolver" "update_user_presence" {
  api_id      = aws_appsync_graphql_api.chat_api.id
  field       = "updateUserPresence"
  type        = "Mutation"
  data_source = aws_appsync_datasource.users_table.name

  request_template = templatefile("${path.module}/resolvers/update_user_presence_request.vtl", {
    table_name = aws_dynamodb_table.users.name
  })

  response_template = file("${path.module}/resolvers/update_user_presence_response.vtl")
}

# getUser query resolver
resource "aws_appsync_resolver" "get_user" {
  api_id      = aws_appsync_graphql_api.chat_api.id
  field       = "getUser"
  type        = "Query"
  data_source = aws_appsync_datasource.users_table.name

  request_template = templatefile("${path.module}/resolvers/get_user_request.vtl", {
    table_name = aws_dynamodb_table.users.name
  })

  response_template = file("${path.module}/resolvers/get_user_response.vtl")
}

# ===================================
# Test Users (if enabled)
# ===================================

resource "aws_cognito_user" "test_users" {
  count        = var.create_test_users ? var.test_user_count : 0
  user_pool_id = aws_cognito_user_pool.chat_users.id
  username     = "testuser${count.index + 1}"

  attributes = {
    email          = "testuser${count.index + 1}@example.com"
    email_verified = true
  }

  message_action      = "SUPPRESS"
  temporary_password  = "TempPassword123!"
  force_alias_creation = false

  lifecycle {
    ignore_changes = [
      password,
      temporary_password
    ]
  }
}

# Set permanent passwords for test users
resource "aws_cognito_user_password" "test_user_passwords" {
  count        = var.create_test_users ? var.test_user_count : 0
  user_pool_id = aws_cognito_user_pool.chat_users.id
  username     = aws_cognito_user.test_users[count.index].username
  password     = "TestPassword123!"
  permanent    = true

  depends_on = [aws_cognito_user.test_users]
}

# ===================================
# CloudWatch Monitoring (if enabled)
# ===================================

# SNS topic for CloudWatch alarms
resource "aws_sns_topic" "chat_app_alerts" {
  count = var.enable_cloudwatch_alarms && length(var.alarm_email_endpoints) > 0 ? 1 : 0
  name  = "${local.name_prefix}-alerts-${local.name_suffix}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alerts"
    Type = "SNS-Topic"
  })
}

# SNS topic subscriptions for email alerts
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.enable_cloudwatch_alarms && length(var.alarm_email_endpoints) > 0 ? length(var.alarm_email_endpoints) : 0
  topic_arn = aws_sns_topic.chat_app_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email_endpoints[count.index]
}

# CloudWatch alarm for AppSync errors
resource "aws_cloudwatch_metric_alarm" "appsync_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-appsync-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "4XXError"
  namespace           = "AWS/AppSync"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "This metric monitors AppSync 4XX errors"
  
  dimensions = {
    GraphQLAPIId = aws_appsync_graphql_api.chat_api.id
  }

  alarm_actions = length(var.alarm_email_endpoints) > 0 ? [aws_sns_topic.chat_app_alerts[0].arn] : []

  tags = local.common_tags
}

# CloudWatch alarm for DynamoDB throttling
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-dynamodb-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This metric monitors DynamoDB throttling events"
  
  dimensions = {
    TableName = aws_dynamodb_table.messages.name
  }

  alarm_actions = length(var.alarm_email_endpoints) > 0 ? [aws_sns_topic.chat_app_alerts[0].arn] : []

  tags = local.common_tags
}