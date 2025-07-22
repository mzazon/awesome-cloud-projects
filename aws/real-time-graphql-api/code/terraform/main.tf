# ==============================================================================
# AWS AppSync GraphQL API with DynamoDB and Cognito Authentication
# ==============================================================================
# This Terraform configuration creates a complete GraphQL API using AWS AppSync
# with DynamoDB as the data source and Cognito User Pools for authentication.
# The infrastructure supports real-time subscriptions, pagination, and 
# comprehensive CRUD operations for a blog platform.
# ==============================================================================

# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------

# Get current AWS region
data "aws_region" "current" {}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Generate random string for unique naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ------------------------------------------------------------------------------
# DynamoDB Table
# ------------------------------------------------------------------------------

# DynamoDB table for blog posts with GSI for author queries
resource "aws_dynamodb_table" "blog_posts" {
  name           = "${var.table_name}-${random_string.suffix.result}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"
  
  # Configure read/write capacity for provisioned billing mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  # Primary key attribute
  attribute {
    name = "id"
    type = "S"
  }

  # GSI attributes for author-based queries
  attribute {
    name = "author"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  # Global Secondary Index for efficient author queries
  global_secondary_index {
    name            = "AuthorIndex"
    hash_key        = "author"
    range_key       = "createdAt"
    projection_type = "ALL"
    
    # Configure capacity for provisioned billing mode
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_gsi_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_gsi_write_capacity : null
  }

  # Point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  # Server-side encryption
  server_side_encryption {
    enabled = var.enable_encryption
  }

  # Resource tags for cost tracking and management
  tags = merge(var.tags, {
    Name        = "${var.table_name}-${random_string.suffix.result}"
    Purpose     = "AppSync GraphQL API data storage"
    Component   = "DynamoDB"
  })
}

# ------------------------------------------------------------------------------
# Cognito User Pool
# ------------------------------------------------------------------------------

# Cognito User Pool for authentication
resource "aws_cognito_user_pool" "blog_users" {
  name = "${var.user_pool_name}-${random_string.suffix.result}"

  # User attributes configuration
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy configuration
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  # Account recovery settings
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # User pool schema for email verification
  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = true
    required            = true
    
    string_attribute_constraints {
      min_length = 5
      max_length = 320
    }
  }

  # Email verification settings
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your verification code"
    email_message        = "Your verification code is {####}"
  }

  # Resource tags
  tags = merge(var.tags, {
    Name      = "${var.user_pool_name}-${random_string.suffix.result}"
    Purpose   = "AppSync GraphQL API authentication"
    Component = "Cognito"
  })
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "blog_client" {
  name         = "${var.api_name}-client-${random_string.suffix.result}"
  user_pool_id = aws_cognito_user_pool.blog_users.id

  # Client configuration
  generate_secret = true
  explicit_auth_flows = [
    "ADMIN_NO_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  # Token validity configuration
  access_token_validity  = 60  # 1 hour
  id_token_validity     = 60  # 1 hour
  refresh_token_validity = 30  # 30 days

  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"

  # Token validity units
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

# ------------------------------------------------------------------------------
# IAM Role for AppSync
# ------------------------------------------------------------------------------

# IAM assume role policy for AppSync
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

# IAM role for AppSync to access DynamoDB
resource "aws_iam_role" "appsync_dynamodb_role" {
  name               = "AppSyncDynamoDBRole-${random_string.suffix.result}"
  assume_role_policy = data.aws_iam_policy_document.appsync_assume_role.json

  tags = merge(var.tags, {
    Name      = "AppSyncDynamoDBRole-${random_string.suffix.result}"
    Purpose   = "AppSync DynamoDB access"
    Component = "IAM"
  })
}

# IAM policy for DynamoDB access
data "aws_iam_policy_document" "appsync_dynamodb_policy" {
  statement {
    effect = "Allow"
    
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    
    resources = [
      aws_dynamodb_table.blog_posts.arn,
      "${aws_dynamodb_table.blog_posts.arn}/*"
    ]
  }
}

# Attach policy to role
resource "aws_iam_role_policy" "appsync_dynamodb_policy" {
  name   = "DynamoDBAccess"
  role   = aws_iam_role.appsync_dynamodb_role.id
  policy = data.aws_iam_policy_document.appsync_dynamodb_policy.json
}

# ------------------------------------------------------------------------------
# AppSync GraphQL API
# ------------------------------------------------------------------------------

# AppSync GraphQL API
resource "aws_appsync_graphql_api" "blog_api" {
  name                = "${var.api_name}-${random_string.suffix.result}"
  authentication_type = "AMAZON_COGNITO_USER_POOLS"

  # Primary authentication via Cognito User Pool
  user_pool_config {
    user_pool_id   = aws_cognito_user_pool.blog_users.id
    aws_region     = data.aws_region.current.name
    default_action = "ALLOW"
  }

  # Additional authentication providers
  dynamic "additional_authentication_provider" {
    for_each = var.enable_api_key_auth ? [1] : []
    content {
      authentication_type = "API_KEY"
    }
  }

  # GraphQL schema
  schema = file("${path.module}/schema.graphql")

  # Logging configuration
  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync_logging_role.arn
    field_log_level         = var.log_level
  }

  # X-Ray tracing
  xray_enabled = var.enable_xray_tracing

  tags = merge(var.tags, {
    Name      = "${var.api_name}-${random_string.suffix.result}"
    Purpose   = "GraphQL API for blog platform"
    Component = "AppSync"
  })
}

# API Key for testing (if enabled)
resource "aws_appsync_api_key" "blog_api_key" {
  count       = var.enable_api_key_auth ? 1 : 0
  api_id      = aws_appsync_graphql_api.blog_api.id
  description = "API Key for testing GraphQL operations"
  expires     = var.api_key_expires
}

# ------------------------------------------------------------------------------
# CloudWatch Logging Role for AppSync
# ------------------------------------------------------------------------------

# IAM role for AppSync logging
resource "aws_iam_role" "appsync_logging_role" {
  name = "AppSyncLoggingRole-${random_string.suffix.result}"

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

  tags = merge(var.tags, {
    Name      = "AppSyncLoggingRole-${random_string.suffix.result}"
    Purpose   = "AppSync CloudWatch logging"
    Component = "IAM"
  })
}

# Attach CloudWatch logs policy
resource "aws_iam_role_policy_attachment" "appsync_logging_policy" {
  role       = aws_iam_role.appsync_logging_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppSyncPushToCloudWatchLogs"
}

# ------------------------------------------------------------------------------
# AppSync Data Source
# ------------------------------------------------------------------------------

# DynamoDB data source for AppSync
resource "aws_appsync_datasource" "blog_posts_datasource" {
  api_id           = aws_appsync_graphql_api.blog_api.id
  name             = "BlogPostsDataSource"
  type             = "AMAZON_DYNAMODB"
  service_role_arn = aws_iam_role.appsync_dynamodb_role.arn

  dynamodb_config {
    table_name = aws_dynamodb_table.blog_posts.name
    region     = data.aws_region.current.name
  }
}

# ------------------------------------------------------------------------------
# AppSync Resolvers
# ------------------------------------------------------------------------------

# Resolver for getBlogPost query
resource "aws_appsync_resolver" "get_blog_post" {
  api_id      = aws_appsync_graphql_api.blog_api.id
  field       = "getBlogPost"
  type        = "Query"
  data_source = aws_appsync_datasource.blog_posts_datasource.name

  request_template = file("${path.module}/templates/get_blog_post_request.vtl")
  response_template = file("${path.module}/templates/response.vtl")
}

# Resolver for listBlogPosts query
resource "aws_appsync_resolver" "list_blog_posts" {
  api_id      = aws_appsync_graphql_api.blog_api.id
  field       = "listBlogPosts"
  type        = "Query"
  data_source = aws_appsync_datasource.blog_posts_datasource.name

  request_template = file("${path.module}/templates/list_blog_posts_request.vtl")
  response_template = file("${path.module}/templates/list_response.vtl")
}

# Resolver for listBlogPostsByAuthor query
resource "aws_appsync_resolver" "list_blog_posts_by_author" {
  api_id      = aws_appsync_graphql_api.blog_api.id
  field       = "listBlogPostsByAuthor"
  type        = "Query"
  data_source = aws_appsync_datasource.blog_posts_datasource.name

  request_template = file("${path.module}/templates/list_by_author_request.vtl")
  response_template = file("${path.module}/templates/list_response.vtl")
}

# Resolver for createBlogPost mutation
resource "aws_appsync_resolver" "create_blog_post" {
  api_id      = aws_appsync_graphql_api.blog_api.id
  field       = "createBlogPost"
  type        = "Mutation"
  data_source = aws_appsync_datasource.blog_posts_datasource.name

  request_template = file("${path.module}/templates/create_blog_post_request.vtl")
  response_template = file("${path.module}/templates/response.vtl")
}

# Resolver for updateBlogPost mutation
resource "aws_appsync_resolver" "update_blog_post" {
  api_id      = aws_appsync_graphql_api.blog_api.id
  field       = "updateBlogPost"
  type        = "Mutation"
  data_source = aws_appsync_datasource.blog_posts_datasource.name

  request_template = file("${path.module}/templates/update_blog_post_request.vtl")
  response_template = file("${path.module}/templates/response.vtl")
}

# Resolver for deleteBlogPost mutation
resource "aws_appsync_resolver" "delete_blog_post" {
  api_id      = aws_appsync_graphql_api.blog_api.id
  field       = "deleteBlogPost"
  type        = "Mutation"
  data_source = aws_appsync_datasource.blog_posts_datasource.name

  request_template = file("${path.module}/templates/delete_blog_post_request.vtl")
  response_template = file("${path.module}/templates/response.vtl")
}

# ------------------------------------------------------------------------------
# Test User Creation (Optional)
# ------------------------------------------------------------------------------

# Test user for authentication testing
resource "aws_cognito_user" "test_user" {
  count          = var.create_test_user ? 1 : 0
  user_pool_id   = aws_cognito_user_pool.blog_users.id
  username       = var.test_username
  password       = var.test_password
  message_action = "SUPPRESS"

  attributes = {
    email          = var.test_username
    email_verified = "true"
  }
}