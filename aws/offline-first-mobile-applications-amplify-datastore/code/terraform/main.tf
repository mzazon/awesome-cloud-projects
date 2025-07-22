# AWS Amplify DataStore - Main Terraform Configuration
# This file creates the infrastructure for offline-first mobile applications
# using AWS Amplify DataStore, AppSync, DynamoDB, and Cognito.

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  app_name            = var.amplify_app_name != "" ? var.amplify_app_name : "${var.project_name}-${random_string.suffix.result}"
  user_pool_name      = var.cognito_user_pool_name != "" ? var.cognito_user_pool_name : "${local.app_name}-users"
  resource_prefix     = "${var.project_name}-${var.environment}"
  
  # Common tags merged with user-defined tags
  common_tags = merge(var.default_tags, {
    Name        = local.app_name
    Environment = var.environment
    Region      = data.aws_region.current.name
  })
}

# =============================================================================
# COGNITO USER POOL AND IDENTITY POOL
# =============================================================================

# Cognito User Pool for authentication
resource "aws_cognito_user_pool" "user_pool" {
  name = local.user_pool_name
  
  # Username configuration
  username_attributes = ["email"]
  
  # Password policy
  password_policy {
    minimum_length                   = var.cognito_password_policy.minimum_length
    require_lowercase               = var.cognito_password_policy.require_lowercase
    require_uppercase               = var.cognito_password_policy.require_uppercase
    require_numbers                 = var.cognito_password_policy.require_numbers
    require_symbols                 = var.cognito_password_policy.require_symbols
    temporary_password_validity_days = var.cognito_password_policy.temporary_password_validity_days
  }
  
  # Account recovery settings
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
  
  # Auto-verified attributes
  auto_verified_attributes = ["email"]
  
  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  
  # User attribute schema
  schema {
    attribute_data_type = "String"
    name               = "email"
    required           = true
    mutable            = true
  }
  
  # Device configuration for better security
  device_configuration {
    challenge_required_on_new_device      = true
    device_only_remembered_on_user_prompt = false
  }
  
  # User pool add-ons
  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }
  
  tags = local.common_tags
}

# Cognito User Pool Client for mobile applications
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${local.app_name}-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  
  # Client configuration for mobile apps
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
  
  # Token validity configuration
  refresh_token_validity = 30
  access_token_validity  = 60
  id_token_validity      = 60
  
  token_validity_units {
    refresh_token = "days"
    access_token  = "minutes"
    id_token      = "minutes"
  }
  
  # Security settings
  prevent_user_existence_errors = "ENABLED"
  
  # Read and write attributes
  read_attributes = [
    "email",
    "email_verified",
    "preferred_username"
  ]
  
  write_attributes = [
    "email",
    "preferred_username"
  ]
}

# Cognito Identity Pool for AWS resource access
resource "aws_cognito_identity_pool" "identity_pool" {
  identity_pool_name               = "${local.app_name}-identity"
  allow_unauthenticated_identities = false
  
  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.user_pool_client.id
    provider_name           = aws_cognito_user_pool.user_pool.endpoint
    server_side_token_check = true
  }
  
  tags = local.common_tags
}

# =============================================================================
# IAM ROLES FOR COGNITO IDENTITY POOL
# =============================================================================

# IAM role for authenticated users
resource "aws_iam_role" "authenticated_role" {
  name = "${local.resource_prefix}-authenticated-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.identity_pool.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM policy for authenticated users (AppSync access)
resource "aws_iam_role_policy" "authenticated_policy" {
  name = "${local.resource_prefix}-authenticated-policy"
  role = aws_iam_role.authenticated_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "appsync:GraphQL"
        ]
        Resource = [
          "${aws_appsync_graphql_api.api.arn}/*"
        ]
      }
    ]
  })
}

# Attach identity pool roles
resource "aws_cognito_identity_pool_roles_attachment" "identity_pool_roles" {
  identity_pool_id = aws_cognito_identity_pool.identity_pool.id
  
  roles = {
    authenticated = aws_iam_role.authenticated_role.arn
  }
}

# =============================================================================
# APPSYNC GRAPHQL API
# =============================================================================

# CloudWatch Log Group for AppSync
resource "aws_cloudwatch_log_group" "appsync_logs" {
  name              = "/aws/appsync/apis/${local.app_name}"
  retention_in_days = 7
  
  tags = local.common_tags
}

# AppSync GraphQL API
resource "aws_appsync_graphql_api" "api" {
  name                = "${local.app_name}-api"
  authentication_type = var.appsync_authentication_type
  
  # Cognito User Pool configuration
  user_pool_config {
    aws_region     = data.aws_region.current.name
    user_pool_id   = aws_cognito_user_pool.user_pool.id
    default_action = "ALLOW"
  }
  
  # Logging configuration
  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync_logs_role.arn
    field_log_level         = var.appsync_log_level
  }
  
  # Schema definition for offline-first mobile application
  schema = file("${path.module}/graphql/schema.graphql")
  
  tags = local.common_tags
  
  depends_on = [
    aws_cloudwatch_log_group.appsync_logs
  ]
}

# IAM role for AppSync CloudWatch logging
resource "aws_iam_role" "appsync_logs_role" {
  name = "${local.resource_prefix}-appsync-logs-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "appsync.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM policy for AppSync CloudWatch logging
resource "aws_iam_role_policy_attachment" "appsync_logs_policy" {
  role       = aws_iam_role.appsync_logs_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppSyncPushToCloudWatchLogs"
}

# =============================================================================
# DYNAMODB TABLES
# =============================================================================

# DynamoDB table for Task model
resource "aws_dynamodb_table" "task_table" {
  name           = "${local.app_name}-Task-${random_string.suffix.result}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"
  
  # Capacity configuration (only used if billing_mode is PROVISIONED)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  # Primary key
  attribute {
    name = "id"
    type = "S"
  }
  
  # GSI for querying tasks by owner
  attribute {
    name = "owner"
    type = "S"
  }
  
  # GSI for querying tasks by project
  attribute {
    name = "projectId"
    type = "S"
  }
  
  # GSI for querying tasks by status
  attribute {
    name = "status"
    type = "S"
  }
  
  # Global Secondary Index for owner-based queries
  global_secondary_index {
    name               = "byOwner"
    hash_key           = "owner"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }
  
  # Global Secondary Index for project-based queries
  global_secondary_index {
    name               = "byProject"
    hash_key           = "projectId"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }
  
  # Global Secondary Index for status-based queries
  global_secondary_index {
    name               = "byStatus"
    hash_key           = "status"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }
  
  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }
  
  # Server-side encryption
  server_side_encryption {
    enabled = var.enable_server_side_encryption
  }
  
  # Deletion protection
  deletion_protection_enabled = var.enable_deletion_protection
  
  # TTL configuration for automatic cleanup
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
  
  tags = local.common_tags
}

# DynamoDB table for Project model
resource "aws_dynamodb_table" "project_table" {
  name           = "${local.app_name}-Project-${random_string.suffix.result}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"
  
  # Capacity configuration (only used if billing_mode is PROVISIONED)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  # Primary key
  attribute {
    name = "id"
    type = "S"
  }
  
  # GSI for querying projects by owner
  attribute {
    name = "owner"
    type = "S"
  }
  
  # Global Secondary Index for owner-based queries
  global_secondary_index {
    name               = "byOwner"
    hash_key           = "owner"
    projection_type    = "ALL"
    read_capacity      = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity     = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }
  
  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }
  
  # Server-side encryption
  server_side_encryption {
    enabled = var.enable_server_side_encryption
  }
  
  # Deletion protection
  deletion_protection_enabled = var.enable_deletion_protection
  
  tags = local.common_tags
}

# =============================================================================
# APPSYNC DATA SOURCES
# =============================================================================

# IAM role for AppSync DynamoDB access
resource "aws_iam_role" "appsync_dynamodb_role" {
  name = "${local.resource_prefix}-appsync-dynamodb-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "appsync.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM policy for AppSync DynamoDB access
resource "aws_iam_role_policy" "appsync_dynamodb_policy" {
  name = "${local.resource_prefix}-appsync-dynamodb-policy"
  role = aws_iam_role.appsync_dynamodb_role.id
  
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
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.task_table.arn,
          aws_dynamodb_table.project_table.arn,
          "${aws_dynamodb_table.task_table.arn}/*",
          "${aws_dynamodb_table.project_table.arn}/*"
        ]
      }
    ]
  })
}

# AppSync data source for Task table
resource "aws_appsync_datasource" "task_datasource" {
  api_id           = aws_appsync_graphql_api.api.id
  name             = "TaskDataSource"
  service_role_arn = aws_iam_role.appsync_dynamodb_role.arn
  type             = "AMAZON_DYNAMODB"
  
  dynamodb_config {
    table_name = aws_dynamodb_table.task_table.name
    region     = data.aws_region.current.name
  }
}

# AppSync data source for Project table
resource "aws_appsync_datasource" "project_datasource" {
  api_id           = aws_appsync_graphql_api.api.id
  name             = "ProjectDataSource"
  service_role_arn = aws_iam_role.appsync_dynamodb_role.arn
  type             = "AMAZON_DYNAMODB"
  
  dynamodb_config {
    table_name = aws_dynamodb_table.project_table.name
    region     = data.aws_region.current.name
  }
}

# =============================================================================
# APPSYNC RESOLVERS (Basic CRUD operations)
# =============================================================================

# Task resolvers
resource "aws_appsync_resolver" "create_task" {
  api_id      = aws_appsync_graphql_api.api.id
  field       = "createTask"
  type        = "Mutation"
  data_source = aws_appsync_datasource.task_datasource.name
  
  code = file("${path.module}/resolvers/create_task.js")
  
  runtime {
    name            = "APPSYNC_JS"
    runtime_version = "1.0.0"
  }
}

resource "aws_appsync_resolver" "update_task" {
  api_id      = aws_appsync_graphql_api.api.id
  field       = "updateTask"
  type        = "Mutation"
  data_source = aws_appsync_datasource.task_datasource.name
  
  code = file("${path.module}/resolvers/update_task.js")
  
  runtime {
    name            = "APPSYNC_JS"
    runtime_version = "1.0.0"
  }
}

resource "aws_appsync_resolver" "delete_task" {
  api_id      = aws_appsync_graphql_api.api.id
  field       = "deleteTask"
  type        = "Mutation"
  data_source = aws_appsync_datasource.task_datasource.name
  
  code = file("${path.module}/resolvers/delete_task.js")
  
  runtime {
    name            = "APPSYNC_JS"
    runtime_version = "1.0.0"
  }
}

resource "aws_appsync_resolver" "get_task" {
  api_id      = aws_appsync_graphql_api.api.id
  field       = "getTask"
  type        = "Query"
  data_source = aws_appsync_datasource.task_datasource.name
  
  code = file("${path.module}/resolvers/get_task.js")
  
  runtime {
    name            = "APPSYNC_JS"
    runtime_version = "1.0.0"
  }
}

resource "aws_appsync_resolver" "list_tasks" {
  api_id      = aws_appsync_graphql_api.api.id
  field       = "listTasks"
  type        = "Query"
  data_source = aws_appsync_datasource.task_datasource.name
  
  code = file("${path.module}/resolvers/list_tasks.js")
  
  runtime {
    name            = "APPSYNC_JS"
    runtime_version = "1.0.0"
  }
}

# Project resolvers
resource "aws_appsync_resolver" "create_project" {
  api_id      = aws_appsync_graphql_api.api.id
  field       = "createProject"
  type        = "Mutation"
  data_source = aws_appsync_datasource.project_datasource.name
  
  code = file("${path.module}/resolvers/create_project.js")
  
  runtime {
    name            = "APPSYNC_JS"
    runtime_version = "1.0.0"
  }
}

resource "aws_appsync_resolver" "update_project" {
  api_id      = aws_appsync_graphql_api.api.id
  field       = "updateProject"
  type        = "Mutation"
  data_source = aws_appsync_datasource.project_datasource.name
  
  code = file("${path.module}/resolvers/update_project.js")
  
  runtime {
    name            = "APPSYNC_JS"
    runtime_version = "1.0.0"
  }
}

resource "aws_appsync_resolver" "delete_project" {
  api_id      = aws_appsync_graphql_api.api.id
  field       = "deleteProject"
  type        = "Mutation"
  data_source = aws_appsync_datasource.project_datasource.name
  
  code = file("${path.module}/resolvers/delete_project.js")
  
  runtime {
    name            = "APPSYNC_JS"
    runtime_version = "1.0.0"
  }
}

resource "aws_appsync_resolver" "get_project" {
  api_id      = aws_appsync_graphql_api.api.id
  field       = "getProject"
  type        = "Query"
  data_source = aws_appsync_datasource.project_datasource.name
  
  code = file("${path.module}/resolvers/get_project.js")
  
  runtime {
    name            = "APPSYNC_JS"
    runtime_version = "1.0.0"
  }
}

resource "aws_appsync_resolver" "list_projects" {
  api_id      = aws_appsync_graphql_api.api.id
  field       = "listProjects"
  type        = "Query"
  data_source = aws_appsync_datasource.project_datasource.name
  
  code = file("${path.module}/resolvers/list_projects.js")
  
  runtime {
    name            = "APPSYNC_JS"
    runtime_version = "1.0.0"
  }
}

# =============================================================================
# AMPLIFY APP (Optional)
# =============================================================================

# Amplify App (only created if create_amplify_app is true)
resource "aws_amplify_app" "app" {
  count = var.create_amplify_app ? 1 : 0
  
  name        = local.app_name
  description = "Offline-first mobile application with AWS Amplify DataStore"
  
  # Repository configuration (optional)
  repository = var.amplify_repository_url != "" ? var.amplify_repository_url : null
  
  # Access token for private repositories
  access_token = var.amplify_access_token != "" ? var.amplify_access_token : null
  
  # Platform configuration
  platform = "WEB"
  
  # Build settings
  build_spec = var.enable_auto_build ? yamlencode({
    version = 1
    applications = [
      {
        frontend = {
          phases = {
            preBuild = {
              commands = [
                "npm install"
              ]
            }
            build = {
              commands = [
                "npm run build"
              ]
            }
          }
          artifacts = {
            baseDirectory = "build"
            files = [
              "**/*"
            ]
          }
          cache = {
            paths = [
              "node_modules/**/*"
            ]
          }
        }
        appRoot = "."
      }
    ]
  }) : null
  
  # Environment variables
  environment_variables = {
    AMPLIFY_DIFF_DEPLOY = "false"
    AMPLIFY_MONOREPO_APP_ROOT = "."
  }
  
  # Auto branch creation
  enable_auto_branch_creation = var.enable_auto_build
  enable_branch_auto_build   = var.enable_auto_build
  enable_branch_auto_deletion = true
  
  # Auto branch creation config
  auto_branch_creation_config {
    enable_auto_build           = var.enable_auto_build
    enable_pull_request_preview = var.enable_pull_request_preview
    environment_variables = {
      AMPLIFY_DIFF_DEPLOY = "false"
    }
  }
  
  # Custom rules for SPA routing
  custom_rule {
    source = "/<*>"
    status = "404"
    target = "/index.html"
  }
  
  tags = local.common_tags
}

# Amplify branch for main branch
resource "aws_amplify_branch" "main" {
  count = var.create_amplify_app ? 1 : 0
  
  app_id      = aws_amplify_app.app[0].id
  branch_name = "main"
  
  enable_auto_build = var.enable_auto_build
  framework         = var.amplify_framework
  stage             = var.environment == "prod" ? "PRODUCTION" : "DEVELOPMENT"
  
  # Environment variables specific to this branch
  environment_variables = {
    REACT_APP_API_URL = aws_appsync_graphql_api.api.uris["GRAPHQL"]
    REACT_APP_REGION  = data.aws_region.current.name
  }
  
  tags = local.common_tags
}

# Custom domain for Amplify app (optional)
resource "aws_amplify_domain_association" "domain" {
  count = var.create_amplify_app && var.create_custom_domain && var.custom_domain_name != "" ? 1 : 0
  
  app_id      = aws_amplify_app.app[0].id
  domain_name = var.custom_domain_name
  
  # SSL certificate configuration (automatically managed by Amplify)
  enable_auto_sub_domain = true
  
  sub_domain {
    branch_name = aws_amplify_branch.main[0].branch_name
    prefix      = var.environment == "prod" ? "" : var.environment
  }
  
  depends_on = [aws_amplify_branch.main]
}

# =============================================================================
# NOTIFICATIONS (Optional)
# =============================================================================

# SNS topic for notifications (if email is provided)
resource "aws_sns_topic" "notifications" {
  count = var.notifications_email != "" ? 1 : 0
  
  name = "${local.resource_prefix}-notifications"
  
  tags = local.common_tags
}

# SNS topic subscription
resource "aws_sns_topic_subscription" "email_notification" {
  count = var.notifications_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.notifications[0].arn
  protocol  = "email"
  endpoint  = var.notifications_email
}

# CloudWatch alarm for DynamoDB throttles
resource "aws_cloudwatch_metric_alarm" "task_table_throttles" {
  count = var.notifications_email != "" ? 1 : 0
  
  alarm_name          = "${local.resource_prefix}-task-table-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors DynamoDB throttles for Task table"
  alarm_actions       = [aws_sns_topic.notifications[0].arn]
  
  dimensions = {
    TableName = aws_dynamodb_table.task_table.name
  }
  
  tags = local.common_tags
}

# CloudWatch alarm for AppSync 4xx errors
resource "aws_cloudwatch_metric_alarm" "appsync_4xx_errors" {
  count = var.notifications_email != "" ? 1 : 0
  
  alarm_name          = "${local.resource_prefix}-appsync-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/AppSync"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors AppSync 4XX errors"
  alarm_actions       = [aws_sns_topic.notifications[0].arn]
  
  dimensions = {
    GraphQLAPIId = aws_appsync_graphql_api.api.id
  }
  
  tags = local.common_tags
}