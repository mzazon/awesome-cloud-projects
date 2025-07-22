# Main Terraform configuration for AWS Full-Stack Real-Time Applications with Amplify and AppSync

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local variables
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_string.suffix.result
  
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "Real-time Chat Application"
  })
}

# Create Cognito User Pool for user authentication
resource "aws_cognito_user_pool" "chat_users" {
  name = "${local.name_prefix}-${var.cognito_user_pool_name}-${local.name_suffix}"
  
  # User pool configuration
  alias_attributes           = ["email", "preferred_username"]
  auto_verified_attributes   = ["email"]
  username_attributes        = ["email"]
  
  # Password policy
  password_policy {
    minimum_length                   = var.cognito_password_policy.minimum_length
    require_uppercase                = var.cognito_password_policy.require_uppercase
    require_lowercase                = var.cognito_password_policy.require_lowercase
    require_numbers                  = var.cognito_password_policy.require_numbers
    require_symbols                  = var.cognito_password_policy.require_symbols
    temporary_password_validity_days = var.cognito_password_policy.temporary_password_validity_days
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
  
  # User pool add-ons
  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }
  
  # Admin create user configuration
  admin_create_user_config {
    allow_admin_create_user_only = false
    
    invite_message_template {
      email_message = "Welcome to the Real-time Chat App! Your username is {username} and temporary password is {####}. Please change your password on first login."
      email_subject = "Welcome to Real-time Chat App"
      sms_message   = "Your username is {username} and temporary password is {####}"
    }
  }
  
  # MFA configuration
  mfa_configuration = var.enable_cognito_mfa ? "ON" : "OFF"
  
  # Schema attributes
  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "email"
    required                 = true
    
    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }
  
  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "preferred_username"
    required                 = false
    
    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }
  
  tags = local.common_tags
}

# Create Cognito User Pool Client
resource "aws_cognito_user_pool_client" "chat_client" {
  name         = "${local.name_prefix}-${var.cognito_user_pool_client_name}-${local.name_suffix}"
  user_pool_id = aws_cognito_user_pool.chat_users.id
  
  # Client configuration
  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation             = true
  enable_propagate_additional_user_context_data = false
  
  # OAuth settings
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "profile", "aws.cognito.signin.user.admin"]
  callback_urls                        = ["http://localhost:3000/", "https://localhost:3000/"]
  logout_urls                          = ["http://localhost:3000/", "https://localhost:3000/"]
  
  # Supported identity providers
  supported_identity_providers = ["COGNITO"]
  
  # Token validity
  access_token_validity  = 60    # 1 hour
  id_token_validity      = 60    # 1 hour
  refresh_token_validity = 30    # 30 days
  
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
  
  # Explicit auth flows
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
  
  # Read and write attributes
  read_attributes  = ["email", "preferred_username"]
  write_attributes = ["email", "preferred_username"]
}

# Create Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "chat_domain" {
  domain       = "${local.name_prefix}-auth-${local.name_suffix}"
  user_pool_id = aws_cognito_user_pool.chat_users.id
}

# Create user groups for role-based access control
resource "aws_cognito_user_group" "moderators" {
  name         = "Moderators"
  user_pool_id = aws_cognito_user_pool.chat_users.id
  description  = "Moderators can create, update, and delete chat rooms"
  precedence   = 1
  role_arn     = aws_iam_role.moderators_role.arn
}

resource "aws_cognito_user_group" "users" {
  name         = "Users"
  user_pool_id = aws_cognito_user_pool.chat_users.id
  description  = "Regular users can participate in chat rooms"
  precedence   = 2
  role_arn     = aws_iam_role.users_role.arn
}

resource "aws_cognito_user_group" "admins" {
  name         = "Admins"
  user_pool_id = aws_cognito_user_pool.chat_users.id
  description  = "Administrators have full access to all resources"
  precedence   = 0
  role_arn     = aws_iam_role.admins_role.arn
}

# Create Cognito Identity Pool for AWS service access
resource "aws_cognito_identity_pool" "chat_identity" {
  identity_pool_name               = "${local.name_prefix}-identity-${local.name_suffix}"
  allow_unauthenticated_identities = false
  
  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.chat_client.id
    provider_name           = aws_cognito_user_pool.chat_users.endpoint
    server_side_token_check = true
  }
  
  tags = local.common_tags
}

# Create IAM roles for different user groups
resource "aws_iam_role" "moderators_role" {
  name = "${local.name_prefix}-moderators-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.chat_identity.id
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role" "users_role" {
  name = "${local.name_prefix}-users-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.chat_identity.id
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role" "admins_role" {
  name = "${local.name_prefix}-admins-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.chat_identity.id
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Create DynamoDB tables for data storage
resource "aws_dynamodb_table" "chat_rooms" {
  name           = "${local.name_prefix}-ChatRoom-${local.name_suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"
  
  # Capacity settings (only used if billing_mode is PROVISIONED)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  attribute {
    name = "id"
    type = "S"
  }
  
  attribute {
    name = "createdAt"
    type = "S"
  }
  
  # Global Secondary Index for querying by creation time
  global_secondary_index {
    name               = "byCreatedAt"
    hash_key           = "createdAt"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }
  
  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_dynamodb_point_in_time_recovery
  }
  
  # Enable server-side encryption
  server_side_encryption {
    enabled = true
  }
  
  # Enable streams for real-time updates
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  tags = local.common_tags
}

resource "aws_dynamodb_table" "messages" {
  name           = "${local.name_prefix}-Message-${local.name_suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"
  
  # Capacity settings (only used if billing_mode is PROVISIONED)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  attribute {
    name = "id"
    type = "S"
  }
  
  attribute {
    name = "chatRoomId"
    type = "S"
  }
  
  attribute {
    name = "createdAt"
    type = "S"
  }
  
  # Global Secondary Index for querying messages by room
  global_secondary_index {
    name               = "byRoom"
    hash_key           = "chatRoomId"
    range_key          = "createdAt"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }
  
  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_dynamodb_point_in_time_recovery
  }
  
  # Enable server-side encryption
  server_side_encryption {
    enabled = true
  }
  
  # Enable streams for real-time updates
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  tags = local.common_tags
}

resource "aws_dynamodb_table" "reactions" {
  name           = "${local.name_prefix}-Reaction-${local.name_suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"
  
  # Capacity settings (only used if billing_mode is PROVISIONED)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  attribute {
    name = "id"
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
  
  # Global Secondary Index for querying reactions by message
  global_secondary_index {
    name               = "byMessage"
    hash_key           = "messageId"
    range_key          = "createdAt"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }
  
  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_dynamodb_point_in_time_recovery
  }
  
  # Enable server-side encryption
  server_side_encryption {
    enabled = true
  }
  
  # Enable streams for real-time updates
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  tags = local.common_tags
}

resource "aws_dynamodb_table" "user_presence" {
  name           = "${local.name_prefix}-UserPresence-${local.name_suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"
  
  # Capacity settings (only used if billing_mode is PROVISIONED)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  attribute {
    name = "id"
    type = "S"
  }
  
  attribute {
    name = "userId"
    type = "S"
  }
  
  # Global Secondary Index for querying presence by user
  global_secondary_index {
    name               = "byUser"
    hash_key           = "userId"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }
  
  # TTL for automatic cleanup of stale presence records
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
  
  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_dynamodb_point_in_time_recovery
  }
  
  # Enable server-side encryption
  server_side_encryption {
    enabled = true
  }
  
  # Enable streams for real-time updates
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  tags = local.common_tags
}

resource "aws_dynamodb_table" "notifications" {
  name           = "${local.name_prefix}-Notification-${local.name_suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"
  
  # Capacity settings (only used if billing_mode is PROVISIONED)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  attribute {
    name = "id"
    type = "S"
  }
  
  attribute {
    name = "userId"
    type = "S"
  }
  
  attribute {
    name = "createdAt"
    type = "S"
  }
  
  # Global Secondary Index for querying notifications by user
  global_secondary_index {
    name               = "byUser"
    hash_key           = "userId"
    range_key          = "createdAt"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }
  
  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_dynamodb_point_in_time_recovery
  }
  
  # Enable server-side encryption
  server_side_encryption {
    enabled = true
  }
  
  # Enable streams for real-time updates
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  tags = local.common_tags
}

# Create IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
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

# Attach policies to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Create IAM policy for Lambda to access DynamoDB
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${local.name_prefix}-lambda-dynamodb-policy-${local.name_suffix}"
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
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [
          aws_dynamodb_table.chat_rooms.arn,
          aws_dynamodb_table.messages.arn,
          aws_dynamodb_table.reactions.arn,
          aws_dynamodb_table.user_presence.arn,
          aws_dynamodb_table.notifications.arn,
          "${aws_dynamodb_table.chat_rooms.arn}/*",
          "${aws_dynamodb_table.messages.arn}/*",
          "${aws_dynamodb_table.reactions.arn}/*",
          "${aws_dynamodb_table.user_presence.arn}/*",
          "${aws_dynamodb_table.notifications.arn}/*"
        ]
      }
    ]
  })
}

# Create Lambda function for real-time operations
resource "aws_lambda_function" "realtime_handler" {
  filename         = "realtime_handler.zip"
  function_name    = "${local.name_prefix}-realtime-handler-${local.name_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  # Create placeholder zip file
  depends_on = [data.archive_file.realtime_handler_zip]
  
  environment {
    variables = {
      CHAT_ROOMS_TABLE    = aws_dynamodb_table.chat_rooms.name
      MESSAGES_TABLE      = aws_dynamodb_table.messages.name
      REACTIONS_TABLE     = aws_dynamodb_table.reactions.name
      USER_PRESENCE_TABLE = aws_dynamodb_table.user_presence.name
      NOTIFICATIONS_TABLE = aws_dynamodb_table.notifications.name
      REGION             = data.aws_region.current.name
    }
  }
  
  # Enable X-Ray tracing
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }
  
  tags = local.common_tags
}

# Create placeholder Lambda function code
data "archive_file" "realtime_handler_zip" {
  type        = "zip"
  output_path = "realtime_handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda_templates/realtime_handler.js", {
      chat_rooms_table    = aws_dynamodb_table.chat_rooms.name
      messages_table      = aws_dynamodb_table.messages.name
      reactions_table     = aws_dynamodb_table.reactions.name
      user_presence_table = aws_dynamodb_table.user_presence.name
      notifications_table = aws_dynamodb_table.notifications.name
      region             = data.aws_region.current.name
    })
    filename = "index.js"
  }
}

# Create CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.realtime_handler.function_name}"
  retention_in_days = var.cloudwatch_logs_retention_days
  
  tags = local.common_tags
}

# Create AppSync GraphQL API
resource "aws_appsync_graphql_api" "chat_api" {
  name                = "${local.name_prefix}-chat-api-${local.name_suffix}"
  authentication_type = var.appsync_authentication_type
  
  # Schema definition
  schema = file("${path.module}/graphql_schema/schema.graphql")
  
  # Cognito User Pool configuration
  user_pool_config {
    user_pool_id   = aws_cognito_user_pool.chat_users.id
    aws_region     = data.aws_region.current.name
    default_action = "ALLOW"
  }
  
  # Enable logging
  dynamic "log_config" {
    for_each = var.enable_cloudwatch_logs ? [1] : []
    content {
      cloudwatch_logs_role_arn = aws_iam_role.appsync_logs_role[0].arn
      field_log_level         = "ALL"
    }
  }
  
  # Enable X-Ray tracing
  xray_enabled = var.enable_xray_tracing
  
  tags = local.common_tags
}

# Create API key for public access (if enabled)
resource "aws_appsync_api_key" "chat_api_key" {
  count       = var.enable_api_key_auth ? 1 : 0
  api_id      = aws_appsync_graphql_api.chat_api.id
  description = "API key for public access to chat API"
  expires     = timeadd(timestamp(), "${var.api_key_expires_in_days * 24}h")
}

# Create additional authentication provider for API key
resource "aws_appsync_api_cache" "chat_api_cache" {
  api_id  = aws_appsync_graphql_api.chat_api.id
  type    = "SMALL"
  ttl     = 300
  
  depends_on = [aws_appsync_graphql_api.chat_api]
}

# Create IAM role for AppSync logging
resource "aws_iam_role" "appsync_logs_role" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  name  = "${local.name_prefix}-appsync-logs-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "appsync.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach CloudWatch logs policy to AppSync role
resource "aws_iam_role_policy_attachment" "appsync_logs_policy" {
  count      = var.enable_cloudwatch_logs ? 1 : 0
  role       = aws_iam_role.appsync_logs_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppSyncPushToCloudWatchLogs"
}

# Create AppSync data sources
resource "aws_appsync_datasource" "chat_rooms_datasource" {
  api_id      = aws_appsync_graphql_api.chat_api.id
  name        = "ChatRoomsDataSource"
  type        = "AMAZON_DYNAMODB"
  description = "DynamoDB data source for chat rooms"
  
  dynamodb_config {
    table_name = aws_dynamodb_table.chat_rooms.name
    region     = data.aws_region.current.name
  }
  
  service_role_arn = aws_iam_role.appsync_service_role.arn
}

resource "aws_appsync_datasource" "messages_datasource" {
  api_id      = aws_appsync_graphql_api.chat_api.id
  name        = "MessagesDataSource"
  type        = "AMAZON_DYNAMODB"
  description = "DynamoDB data source for messages"
  
  dynamodb_config {
    table_name = aws_dynamodb_table.messages.name
    region     = data.aws_region.current.name
  }
  
  service_role_arn = aws_iam_role.appsync_service_role.arn
}

resource "aws_appsync_datasource" "reactions_datasource" {
  api_id      = aws_appsync_graphql_api.chat_api.id
  name        = "ReactionsDataSource"
  type        = "AMAZON_DYNAMODB"
  description = "DynamoDB data source for reactions"
  
  dynamodb_config {
    table_name = aws_dynamodb_table.reactions.name
    region     = data.aws_region.current.name
  }
  
  service_role_arn = aws_iam_role.appsync_service_role.arn
}

resource "aws_appsync_datasource" "user_presence_datasource" {
  api_id      = aws_appsync_graphql_api.chat_api.id
  name        = "UserPresenceDataSource"
  type        = "AMAZON_DYNAMODB"
  description = "DynamoDB data source for user presence"
  
  dynamodb_config {
    table_name = aws_dynamodb_table.user_presence.name
    region     = data.aws_region.current.name
  }
  
  service_role_arn = aws_iam_role.appsync_service_role.arn
}

resource "aws_appsync_datasource" "notifications_datasource" {
  api_id      = aws_appsync_graphql_api.chat_api.id
  name        = "NotificationsDataSource"
  type        = "AMAZON_DYNAMODB"
  description = "DynamoDB data source for notifications"
  
  dynamodb_config {
    table_name = aws_dynamodb_table.notifications.name
    region     = data.aws_region.current.name
  }
  
  service_role_arn = aws_iam_role.appsync_service_role.arn
}

resource "aws_appsync_datasource" "lambda_datasource" {
  api_id      = aws_appsync_graphql_api.chat_api.id
  name        = "LambdaDataSource"
  type        = "AWS_LAMBDA"
  description = "Lambda data source for real-time operations"
  
  lambda_config {
    function_arn = aws_lambda_function.realtime_handler.arn
  }
  
  service_role_arn = aws_iam_role.appsync_service_role.arn
}

# Create IAM role for AppSync service
resource "aws_iam_role" "appsync_service_role" {
  name = "${local.name_prefix}-appsync-service-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "appsync.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Create IAM policy for AppSync to access DynamoDB
resource "aws_iam_role_policy" "appsync_dynamodb_policy" {
  name = "${local.name_prefix}-appsync-dynamodb-policy-${local.name_suffix}"
  role = aws_iam_role.appsync_service_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [
          aws_dynamodb_table.chat_rooms.arn,
          aws_dynamodb_table.messages.arn,
          aws_dynamodb_table.reactions.arn,
          aws_dynamodb_table.user_presence.arn,
          aws_dynamodb_table.notifications.arn,
          "${aws_dynamodb_table.chat_rooms.arn}/*",
          "${aws_dynamodb_table.messages.arn}/*",
          "${aws_dynamodb_table.reactions.arn}/*",
          "${aws_dynamodb_table.user_presence.arn}/*",
          "${aws_dynamodb_table.notifications.arn}/*"
        ]
      }
    ]
  })
}

# Create IAM policy for AppSync to invoke Lambda
resource "aws_iam_role_policy" "appsync_lambda_policy" {
  name = "${local.name_prefix}-appsync-lambda-policy-${local.name_suffix}"
  role = aws_iam_role.appsync_service_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.realtime_handler.arn
        ]
      }
    ]
  })
}

# Grant AppSync permission to invoke Lambda
resource "aws_lambda_permission" "appsync_lambda_permission" {
  statement_id  = "AllowExecutionFromAppSync"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.realtime_handler.function_name
  principal     = "appsync.amazonaws.com"
  source_arn    = "${aws_appsync_graphql_api.chat_api.arn}/*"
}

# Create Amplify application
resource "aws_amplify_app" "chat_app" {
  name        = "${local.name_prefix}-${var.amplify_app_name}-${local.name_suffix}"
  description = "Real-time chat application frontend"
  
  # Repository configuration (if provided)
  repository = var.amplify_repository_url != "" ? var.amplify_repository_url : null
  
  # Build settings
  build_spec = var.amplify_build_spec != "" ? var.amplify_build_spec : templatefile("${path.module}/amplify_templates/build_spec.yml", {
    appsync_graphql_endpoint = aws_appsync_graphql_api.chat_api.graphql_endpoint
    appsync_region          = data.aws_region.current.name
    cognito_user_pool_id    = aws_cognito_user_pool.chat_users.id
    cognito_user_pool_client_id = aws_cognito_user_pool_client.chat_client.id
    cognito_identity_pool_id = aws_cognito_identity_pool.chat_identity.id
  })
  
  # Environment variables
  environment_variables = merge(
    var.amplify_environment_variables,
    {
      AMPLIFY_DIFF_DEPLOY         = "false"
      AMPLIFY_MONOREPO_APP_ROOT   = "."
      REACT_APP_APPSYNC_GRAPHQL_ENDPOINT = aws_appsync_graphql_api.chat_api.graphql_endpoint
      REACT_APP_APPSYNC_REGION           = data.aws_region.current.name
      REACT_APP_COGNITO_USER_POOL_ID     = aws_cognito_user_pool.chat_users.id
      REACT_APP_COGNITO_USER_POOL_CLIENT_ID = aws_cognito_user_pool_client.chat_client.id
      REACT_APP_COGNITO_IDENTITY_POOL_ID = aws_cognito_identity_pool.chat_identity.id
    }
  )
  
  # Auto branch creation
  enable_auto_branch_creation = var.enable_amplify_auto_branch_creation
  
  # IAM service role
  iam_service_role_arn = aws_iam_role.amplify_service_role.arn
  
  # Platform
  platform = "WEB"
  
  tags = local.common_tags
}

# Create Amplify branch
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.chat_app.id
  branch_name = var.amplify_branch_name
  
  description = "Main branch for real-time chat application"
  
  # Environment variables (branch-specific)
  environment_variables = {
    AMPLIFY_DIFF_DEPLOY = "false"
    ENV                 = var.environment
  }
  
  # Enable auto build
  enable_auto_build = var.amplify_repository_url != ""
  
  tags = local.common_tags
}

# Create IAM role for Amplify service
resource "aws_iam_role" "amplify_service_role" {
  name = "${local.name_prefix}-amplify-service-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach policies to Amplify service role
resource "aws_iam_role_policy_attachment" "amplify_backend_deploy_policy" {
  role       = aws_iam_role.amplify_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmplifyBackendDeployFullAccess"
}

# Create CloudWatch Log Group for AppSync
resource "aws_cloudwatch_log_group" "appsync_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/appsync/apis/${aws_appsync_graphql_api.chat_api.id}"
  retention_in_days = var.cloudwatch_logs_retention_days
  
  tags = local.common_tags
}

# Create SNS topic for notifications (if email provided)
resource "aws_sns_topic" "notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${local.name_prefix}-notifications-${local.name_suffix}"
  
  tags = local.common_tags
}

# Create SNS topic subscription
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Create CloudWatch alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "appsync_errors" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-appsync-errors-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/AppSync"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors AppSync 4XX errors"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.notifications[0].arn] : []
  
  dimensions = {
    GraphQLAPIId = aws_appsync_graphql_api.chat_api.id
  }
  
  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-lambda-errors-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.notifications[0].arn] : []
  
  dimensions = {
    FunctionName = aws_lambda_function.realtime_handler.function_name
  }
  
  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-dynamodb-throttles-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ConsumedReadCapacityUnits"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1000"
  alarm_description   = "This metric monitors DynamoDB read capacity consumption"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.notifications[0].arn] : []
  
  dimensions = {
    TableName = aws_dynamodb_table.messages.name
  }
  
  tags = local.common_tags
}