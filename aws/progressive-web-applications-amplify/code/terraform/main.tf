# Progressive Web Applications with AWS Amplify - Main Infrastructure

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common tags for all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "progressive-web-applications-aws-amplify"
    },
    var.tags
  )
  
  # Generate unique names for resources
  app_name_unique             = "${var.app_name}-${random_id.suffix.hex}"
  user_pool_name_unique       = "${var.cognito_user_pool_name}-${random_id.suffix.hex}"
  user_pool_client_name_unique = "${var.cognito_user_pool_client_name}-${random_id.suffix.hex}"
  identity_pool_name_unique   = "${var.cognito_identity_pool_name}-${random_id.suffix.hex}"
  api_name_unique             = "${var.appsync_api_name}-${random_id.suffix.hex}"
  table_name_unique           = "${var.dynamodb_table_name}-${random_id.suffix.hex}"
  bucket_name_unique          = "${var.s3_bucket_name}-${random_id.suffix.hex}"
}

# ================================================================
# COGNITO USER POOL - Authentication and User Management
# ================================================================

# Cognito User Pool for user authentication
resource "aws_cognito_user_pool" "main" {
  name                = local.user_pool_name_unique
  username_attributes = ["email"]
  
  # Password policy configuration
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  
  # User pool configuration
  auto_verified_attributes = ["email"]
  
  # Account recovery configuration
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
  
  # Verification message template
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_message        = "Your verification code is {####}"
    email_subject        = "Verify your email for ${var.app_name}"
  }
  
  # Device configuration
  device_configuration {
    challenge_required_on_new_device      = false
    device_only_remembered_on_user_prompt = false
  }
  
  # User attribute update settings
  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }
  
  tags = local.common_tags
}

# Cognito User Pool Client for application access
resource "aws_cognito_user_pool_client" "main" {
  name         = local.user_pool_client_name_unique
  user_pool_id = aws_cognito_user_pool.main.id
  
  # Client configuration
  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation             = true
  enable_propagate_additional_user_context_data = false
  
  # OAuth configuration
  supported_identity_providers = ["COGNITO"]
  
  # Token validity configuration
  access_token_validity  = 60    # 1 hour
  id_token_validity     = 60    # 1 hour
  refresh_token_validity = 30   # 30 days
  
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
  
  # Explicit authentication flows
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]
  
  # Read and write attributes
  read_attributes = [
    "email",
    "email_verified",
    "given_name",
    "family_name",
    "preferred_username"
  ]
  
  write_attributes = [
    "email",
    "given_name",
    "family_name",
    "preferred_username"
  ]
}

# Cognito Identity Pool for AWS resource access
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = local.identity_pool_name_unique
  allow_unauthenticated_identities = false
  
  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.main.id
    provider_name           = aws_cognito_user_pool.main.endpoint
    server_side_token_check = false
  }
  
  tags = local.common_tags
}

# ================================================================
# IAM ROLES - Identity Pool and Service Roles
# ================================================================

# IAM role for authenticated users
resource "aws_iam_role" "authenticated" {
  name = "${var.project_name}-authenticated-role-${random_id.suffix.hex}"
  
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
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
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

# IAM policy for authenticated users
resource "aws_iam_role_policy" "authenticated" {
  name = "${var.project_name}-authenticated-policy-${random_id.suffix.hex}"
  role = aws_iam_role.authenticated.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.storage.arn}/public/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.storage.arn}/protected/$${cognito-identity.amazonaws.com:sub}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.storage.arn}/private/$${cognito-identity.amazonaws.com:sub}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.storage.arn
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "public/",
              "public/*",
              "protected/",
              "protected/*",
              "private/$${cognito-identity.amazonaws.com:sub}/",
              "private/$${cognito-identity.amazonaws.com:sub}/*"
            ]
          }
        }
      }
    ]
  })
}

# IAM role for unauthenticated users (guest access)
resource "aws_iam_role" "unauthenticated" {
  name = "${var.project_name}-unauthenticated-role-${random_id.suffix.hex}"
  
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
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "unauthenticated"
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM policy for unauthenticated users (limited access)
resource "aws_iam_role_policy" "unauthenticated" {
  name = "${var.project_name}-unauthenticated-policy-${random_id.suffix.hex}"
  role = aws_iam_role.unauthenticated.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.storage.arn}/public/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.storage.arn
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "public/",
              "public/*"
            ]
          }
        }
      }
    ]
  })
}

# Attach roles to Identity Pool
resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id
  
  roles = {
    authenticated   = aws_iam_role.authenticated.arn
    unauthenticated = aws_iam_role.unauthenticated.arn
  }
}

# ================================================================
# DYNAMODB - Data Storage
# ================================================================

# DynamoDB table for task storage
resource "aws_dynamodb_table" "tasks" {
  name           = local.table_name_unique
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  attribute {
    name = "id"
    type = "S"
  }
  
  attribute {
    name = "owner"
    type = "S"
  }
  
  attribute {
    name = "createdAt"
    type = "S"
  }
  
  # Global Secondary Index for querying by owner
  global_secondary_index {
    name            = "byOwner"
    hash_key        = "owner"
    range_key       = "createdAt"
    projection_type = "ALL"
  }
  
  # TTL configuration for automatic cleanup
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
  
  # Point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }
  
  # Server-side encryption
  server_side_encryption {
    enabled = true
  }
  
  tags = local.common_tags
}

# ================================================================
# S3 BUCKET - File Storage
# ================================================================

# S3 bucket for file storage
resource "aws_s3_bucket" "storage" {
  bucket = local.bucket_name_unique
  
  tags = local.common_tags
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "storage" {
  bucket = aws_s3_bucket.storage.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "storage" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.storage.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "storage" {
  bucket = aws_s3_bucket.storage.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket CORS configuration
resource "aws_s3_bucket_cors_configuration" "storage" {
  bucket = aws_s3_bucket.storage.id
  
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# ================================================================
# APPSYNC - GraphQL API
# ================================================================

# IAM role for AppSync
resource "aws_iam_role" "appsync" {
  name = "${var.project_name}-appsync-role-${random_id.suffix.hex}"
  
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

# IAM policy for AppSync to access DynamoDB
resource "aws_iam_role_policy" "appsync_dynamodb" {
  name = "${var.project_name}-appsync-dynamodb-policy-${random_id.suffix.hex}"
  role = aws_iam_role.appsync.id
  
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
          aws_dynamodb_table.tasks.arn,
          "${aws_dynamodb_table.tasks.arn}/*"
        ]
      }
    ]
  })
}

# AppSync GraphQL API
resource "aws_appsync_graphql_api" "main" {
  name                = local.api_name_unique
  authentication_type = var.appsync_authentication_type
  
  user_pool_config {
    aws_region     = data.aws_region.current.name
    default_action = "ALLOW"
    user_pool_id   = aws_cognito_user_pool.main.id
  }
  
  # GraphQL schema
  schema = file("${path.module}/schema.graphql")
  
  # Enhanced logging
  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync_logs.arn
    field_log_level          = "ALL"
  }
  
  # X-Ray tracing
  xray_enabled = var.enable_xray_tracing
  
  tags = local.common_tags
}

# CloudWatch logs role for AppSync
resource "aws_iam_role" "appsync_logs" {
  name = "${var.project_name}-appsync-logs-role-${random_id.suffix.hex}"
  
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

# IAM policy for AppSync CloudWatch logs
resource "aws_iam_role_policy" "appsync_logs" {
  name = "${var.project_name}-appsync-logs-policy-${random_id.suffix.hex}"
  role = aws_iam_role.appsync_logs.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# AppSync Data Source for DynamoDB
resource "aws_appsync_datasource" "tasks_table" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "TasksTable"
  service_role_arn = aws_iam_role.appsync.arn
  type             = "AMAZON_DYNAMODB"
  
  dynamodb_config {
    table_name = aws_dynamodb_table.tasks.name
    region     = data.aws_region.current.name
  }
}

# ================================================================
# APPSYNC RESOLVERS - GraphQL Operations
# ================================================================

# Resolver for createTask mutation
resource "aws_appsync_resolver" "create_task" {
  api_id      = aws_appsync_graphql_api.main.id
  field       = "createTask"
  type        = "Mutation"
  data_source = aws_appsync_datasource.tasks_table.name
  
  # VTL request template
  request_template = <<EOF
{
  "version": "2017-02-28",
  "operation": "PutItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($util.autoId())
  },
  "attributeValues": {
    "title": $util.dynamodb.toDynamoDBJson($context.arguments.input.title),
    "description": $util.dynamodb.toDynamoDBJson($context.arguments.input.description),
    "completed": $util.dynamodb.toDynamoDBJson($context.arguments.input.completed),
    "priority": $util.dynamodb.toDynamoDBJson($context.arguments.input.priority),
    "dueDate": $util.dynamodb.toDynamoDBJson($context.arguments.input.dueDate),
    "owner": $util.dynamodb.toDynamoDBJson($context.identity.username),
    "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
    "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
  }
}
EOF
  
  # VTL response template
  response_template = <<EOF
$util.toJson($context.result)
EOF
}

# Resolver for listTasks query
resource "aws_appsync_resolver" "list_tasks" {
  api_id      = aws_appsync_graphql_api.main.id
  field       = "listTasks"
  type        = "Query"
  data_source = aws_appsync_datasource.tasks_table.name
  
  # VTL request template
  request_template = <<EOF
{
  "version": "2017-02-28",
  "operation": "Query",
  "index": "byOwner",
  "query": {
    "expression": "owner = :owner",
    "expressionValues": {
      ":owner": $util.dynamodb.toDynamoDBJson($context.identity.username)
    }
  },
  "scanIndexForward": false
}
EOF
  
  # VTL response template
  response_template = <<EOF
{
  "items": $util.toJson($context.result.items),
  "nextToken": $util.toJson($context.result.nextToken)
}
EOF
}

# Resolver for updateTask mutation
resource "aws_appsync_resolver" "update_task" {
  api_id      = aws_appsync_graphql_api.main.id
  field       = "updateTask"
  type        = "Mutation"
  data_source = aws_appsync_datasource.tasks_table.name
  
  # VTL request template
  request_template = <<EOF
{
  "version": "2017-02-28",
  "operation": "UpdateItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($context.arguments.input.id)
  },
  "update": {
    "expression": "SET #title = :title, #description = :description, #completed = :completed, #priority = :priority, #dueDate = :dueDate, #updatedAt = :updatedAt",
    "expressionNames": {
      "#title": "title",
      "#description": "description",
      "#completed": "completed",
      "#priority": "priority",
      "#dueDate": "dueDate",
      "#updatedAt": "updatedAt"
    },
    "expressionValues": {
      ":title": $util.dynamodb.toDynamoDBJson($context.arguments.input.title),
      ":description": $util.dynamodb.toDynamoDBJson($context.arguments.input.description),
      ":completed": $util.dynamodb.toDynamoDBJson($context.arguments.input.completed),
      ":priority": $util.dynamodb.toDynamoDBJson($context.arguments.input.priority),
      ":dueDate": $util.dynamodb.toDynamoDBJson($context.arguments.input.dueDate),
      ":updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
    }
  },
  "condition": {
    "expression": "owner = :owner",
    "expressionValues": {
      ":owner": $util.dynamodb.toDynamoDBJson($context.identity.username)
    }
  }
}
EOF
  
  # VTL response template
  response_template = <<EOF
$util.toJson($context.result)
EOF
}

# Resolver for deleteTask mutation
resource "aws_appsync_resolver" "delete_task" {
  api_id      = aws_appsync_graphql_api.main.id
  field       = "deleteTask"
  type        = "Mutation"
  data_source = aws_appsync_datasource.tasks_table.name
  
  # VTL request template
  request_template = <<EOF
{
  "version": "2017-02-28",
  "operation": "DeleteItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($context.arguments.input.id)
  },
  "condition": {
    "expression": "owner = :owner",
    "expressionValues": {
      ":owner": $util.dynamodb.toDynamoDBJson($context.identity.username)
    }
  }
}
EOF
  
  # VTL response template
  response_template = <<EOF
$util.toJson($context.result)
EOF
}

# ================================================================
# AMPLIFY APPLICATION - Frontend Hosting
# ================================================================

# Amplify Application
resource "aws_amplify_app" "main" {
  name       = local.app_name_unique
  repository = var.github_repository
  
  # Build settings
  build_spec = file("${path.module}/amplify.yml")
  
  # Environment variables
  environment_variables = {
    AMPLIFY_MONOREPO_APP_ROOT = "."
    AMPLIFY_DIFF_DEPLOY       = "false"
    _LIVE_UPDATES             = jsonencode([
      {
        name = "Amplify CLI"
        pkg  = "@aws-amplify/cli"
        type = "npm"
      }
    ])
  }
  
  # OAuth token for GitHub access
  access_token = var.github_access_token
  
  # Auto branch creation
  enable_auto_branch_creation = var.enable_auto_branch_creation
  enable_branch_auto_build   = var.enable_auto_build
  enable_branch_auto_deletion = true
  
  # Auto branch creation configuration
  auto_branch_creation_config {
    enable_auto_build           = var.enable_auto_build
    enable_pull_request_preview = var.enable_pull_request_preview
    environment_variables = {
      AMPLIFY_MONOREPO_APP_ROOT = "."
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

# Amplify Branch for main deployment
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  
  enable_auto_build           = var.enable_auto_build
  enable_pull_request_preview = var.enable_pull_request_preview
  
  # Environment variables specific to this branch
  environment_variables = {
    AMPLIFY_MONOREPO_APP_ROOT = "."
    _LIVE_UPDATES             = jsonencode([
      {
        name = "Amplify CLI"
        pkg  = "@aws-amplify/cli"
        type = "npm"
      }
    ])
  }
  
  tags = local.common_tags
}

# Custom domain configuration (optional)
resource "aws_amplify_domain_association" "main" {
  count       = var.amplify_domain != "" ? 1 : 0
  app_id      = aws_amplify_app.main.id
  domain_name = var.amplify_domain
  
  # Configure subdomain for branch
  sub_domain {
    branch_name = aws_amplify_branch.main.branch_name
    prefix      = ""
  }
  
  # Configure www subdomain
  sub_domain {
    branch_name = aws_amplify_branch.main.branch_name
    prefix      = "www"
  }
}

# ================================================================
# CLOUDWATCH LOGS - Monitoring and Logging
# ================================================================

# CloudWatch log group for AppSync
resource "aws_cloudwatch_log_group" "appsync" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/appsync/apis/${aws_appsync_graphql_api.main.id}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# CloudWatch log group for Amplify
resource "aws_cloudwatch_log_group" "amplify" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/amplify/${aws_amplify_app.main.name}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# ================================================================
# SNS TOPIC - Notifications (Optional)
# ================================================================

# SNS topic for notifications
resource "aws_sns_topic" "notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${var.project_name}-notifications-${random_id.suffix.hex}"
  
  tags = local.common_tags
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ================================================================
# CLOUDWATCH ALARMS - Monitoring (Optional)
# ================================================================

# CloudWatch alarm for DynamoDB throttling
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttling" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-dynamodb-throttling-${random_id.suffix.hex}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors DynamoDB throttling"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.notifications[0].arn] : []
  
  dimensions = {
    TableName = aws_dynamodb_table.tasks.name
  }
  
  tags = local.common_tags
}

# CloudWatch alarm for AppSync errors
resource "aws_cloudwatch_metric_alarm" "appsync_errors" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-appsync-errors-${random_id.suffix.hex}"
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
    GraphQLAPIId = aws_appsync_graphql_api.main.id
  }
  
  tags = local.common_tags
}

# ================================================================
# LOCAL FILES - Configuration Files
# ================================================================

# Create GraphQL schema file
resource "local_file" "schema" {
  content = <<EOF
type Task @model @auth(rules: [{allow: owner}]) {
  id: ID!
  title: String!
  description: String
  completed: Boolean!
  priority: Priority!
  dueDate: AWSDate
  owner: String!
  createdAt: AWSDateTime!
  updatedAt: AWSDateTime!
}

enum Priority {
  LOW
  MEDIUM
  HIGH
}

type Query {
  listTasks: TaskConnection
}

type Mutation {
  createTask(input: CreateTaskInput!): Task
  updateTask(input: UpdateTaskInput!): Task
  deleteTask(input: DeleteTaskInput!): Task
}

type Subscription {
  onCreateTask(owner: String!): Task
    @aws_subscribe(mutations: ["createTask"])
  onUpdateTask(owner: String!): Task
    @aws_subscribe(mutations: ["updateTask"])
  onDeleteTask(owner: String!): Task
    @aws_subscribe(mutations: ["deleteTask"])
}

input CreateTaskInput {
  title: String!
  description: String
  completed: Boolean!
  priority: Priority!
  dueDate: AWSDate
}

input UpdateTaskInput {
  id: ID!
  title: String
  description: String
  completed: Boolean
  priority: Priority
  dueDate: AWSDate
}

input DeleteTaskInput {
  id: ID!
}

type TaskConnection {
  items: [Task]
  nextToken: String
}
EOF
  
  filename = "${path.module}/schema.graphql"
}

# Create Amplify build specification
resource "local_file" "amplify_build" {
  content = <<EOF
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - npm ci
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF
  
  filename = "${path.module}/amplify.yml"
}

# Create aws-exports.js configuration file
resource "local_file" "aws_exports" {
  content = <<EOF
const awsmobile = {
  "aws_project_region": "${data.aws_region.current.name}",
  "aws_cognito_identity_pool_id": "${aws_cognito_identity_pool.main.id}",
  "aws_cognito_region": "${data.aws_region.current.name}",
  "aws_user_pools_id": "${aws_cognito_user_pool.main.id}",
  "aws_user_pools_web_client_id": "${aws_cognito_user_pool_client.main.id}",
  "oauth": {},
  "aws_cognito_username_attributes": ["EMAIL"],
  "aws_cognito_social_providers": [],
  "aws_cognito_signup_attributes": ["EMAIL"],
  "aws_cognito_mfa_configuration": "OFF",
  "aws_cognito_mfa_types": ["SMS"],
  "aws_cognito_password_protection_settings": {
    "passwordPolicyMinLength": 8,
    "passwordPolicyCharacters": []
  },
  "aws_cognito_verification_mechanisms": ["EMAIL"],
  "aws_appsync_graphqlEndpoint": "${aws_appsync_graphql_api.main.uris["GRAPHQL"]}",
  "aws_appsync_region": "${data.aws_region.current.name}",
  "aws_appsync_authenticationType": "${var.appsync_authentication_type}",
  "aws_user_files_s3_bucket": "${aws_s3_bucket.storage.bucket}",
  "aws_user_files_s3_bucket_region": "${data.aws_region.current.name}",
  "aws_content_delivery_cloudfront_distribution_id": "",
  "aws_content_delivery_cloudfront_domain_name": ""
};

export default awsmobile;
EOF
  
  filename = "${path.module}/aws-exports.js"
}