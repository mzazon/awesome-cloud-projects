# ==============================================================================
# Mobile Backend Services with AWS Amplify - Terraform Configuration
# 
# This Terraform configuration provisions a comprehensive mobile backend 
# infrastructure using AWS Amplify services including authentication,
# GraphQL APIs, storage, and analytics.
# ==============================================================================

# Data source to get current AWS region and account ID
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  project_name = "${var.project_name}-${random_id.suffix.hex}"
  
  # Common tags applied to all resources
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "mobile-backend-services-amplify"
  }
}

# ==============================================================================
# Amazon Cognito User Pool for Authentication
# ==============================================================================

# Cognito User Pool for user management and authentication
resource "aws_cognito_user_pool" "main" {
  name = "${local.project_name}-user-pool"

  # Email-based authentication configuration
  alias_attributes         = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy for enhanced security
  password_policy {
    minimum_length                   = 8
    require_lowercase               = true
    require_numbers                 = true
    require_symbols                 = true
    require_uppercase               = true
    temporary_password_validity_days = 7
  }

  # Enhanced security settings
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Multi-factor authentication configuration
  mfa_configuration = "OPTIONAL"
  
  software_token_mfa_configuration {
    enabled = true
  }

  # Email verification configuration
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your verification code"
    email_message        = "Your verification code is {####}"
  }

  # User pool schema for additional attributes
  schema {
    attribute_data_type = "String"
    name               = "email"
    required           = true
    mutable            = true
  }

  schema {
    attribute_data_type = "String"
    name               = "given_name"
    required           = false
    mutable            = true
  }

  schema {
    attribute_data_type = "String"
    name               = "family_name"
    required           = false
    mutable            = true
  }

  # Device configuration for improved security
  device_configuration {
    challenge_required_on_new_device      = false
    device_only_remembered_on_user_prompt = false
  }

  tags = local.common_tags
}

# Cognito User Pool Client for application integration
resource "aws_cognito_user_pool_client" "main" {
  name         = "${local.project_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # OAuth2 and token configuration
  generate_secret                      = false
  supported_identity_providers        = ["COGNITO"]
  callback_urls                       = ["myapp://callback"]
  logout_urls                         = ["myapp://logout"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                 = ["code", "implicit"]
  allowed_oauth_scopes                = ["email", "openid", "profile"]

  # Token validity configuration
  access_token_validity  = 60   # 60 minutes
  id_token_validity      = 60   # 60 minutes
  refresh_token_validity = 30   # 30 days

  # Read and write attributes
  read_attributes  = ["email", "given_name", "family_name"]
  write_attributes = ["email", "given_name", "family_name"]

  # Prevent user existence errors for security
  prevent_user_existence_errors = "ENABLED"

  # Explicit authentication flows
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]
}

# Cognito Identity Pool for AWS service access
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${local.project_name}-identity-pool"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.main.id
    provider_name           = aws_cognito_user_pool.main.endpoint
    server_side_token_check = false
  }

  tags = local.common_tags
}

# ==============================================================================
# IAM Roles for Cognito Identity Pool
# ==============================================================================

# IAM role for authenticated users
resource "aws_iam_role" "cognito_authenticated" {
  name = "${local.project_name}-cognito-authenticated-role"

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

# IAM policy for authenticated users - AppSync access
resource "aws_iam_role_policy" "cognito_authenticated_appsync" {
  name = "${local.project_name}-cognito-authenticated-appsync-policy"
  role = aws_iam_role.cognito_authenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "appsync:GraphQL"
        ]
        Resource = "${aws_appsync_graphql_api.main.arn}/*"
      }
    ]
  })
}

# IAM policy for authenticated users - S3 access
resource "aws_iam_role_policy" "cognito_authenticated_s3" {
  name = "${local.project_name}-cognito-authenticated-s3-policy"
  role = aws_iam_role.cognito_authenticated.id

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
        Resource = [
          "${aws_s3_bucket.user_files.arn}/public/*",
          "${aws_s3_bucket.user_files.arn}/protected/$${cognito-identity.amazonaws.com:sub}/*",
          "${aws_s3_bucket.user_files.arn}/private/$${cognito-identity.amazonaws.com:sub}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.user_files.arn
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "public/",
              "public/*",
              "protected/$${cognito-identity.amazonaws.com:sub}/",
              "protected/$${cognito-identity.amazonaws.com:sub}/*",
              "private/$${cognito-identity.amazonaws.com:sub}/",
              "private/$${cognito-identity.amazonaws.com:sub}/*"
            ]
          }
        }
      }
    ]
  })
}

# Attach the roles to the identity pool
resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    "authenticated" = aws_iam_role.cognito_authenticated.arn
  }
}

# ==============================================================================
# DynamoDB Tables for Data Storage
# ==============================================================================

# DynamoDB table for posts/content
resource "aws_dynamodb_table" "posts" {
  name           = "${local.project_name}-posts"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = local.common_tags
}

# DynamoDB table for comments
resource "aws_dynamodb_table" "comments" {
  name           = "${local.project_name}-comments"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  range_key      = "postId"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "postId"
    type = "S"
  }

  # Global secondary index for querying comments by post
  global_secondary_index {
    name     = "postId-index"
    hash_key = "postId"
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = local.common_tags
}

# ==============================================================================
# AWS AppSync GraphQL API
# ==============================================================================

# AppSync GraphQL API
resource "aws_appsync_graphql_api" "main" {
  authentication_type = "AMAZON_COGNITO_USER_POOLS"
  name                = "${local.project_name}-api"

  user_pool_config {
    aws_region     = data.aws_region.current.name
    default_action = "ALLOW"
    user_pool_id   = aws_cognito_user_pool.main.id
  }

  # Enable CloudWatch logs
  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync_logs.arn
    field_log_level          = "ERROR"
  }

  tags = local.common_tags
}

# GraphQL schema
resource "aws_appsync_graphql_schema" "main" {
  api_id = aws_appsync_graphql_api.main.id

  schema = <<EOF
type Post @aws_cognito_user_pools {
  id: ID!
  title: String!
  content: String!
  author: String!
  createdAt: String!
  updatedAt: String!
  comments: [Comment] @connection(keyName: "byPost", fields: ["id"])
}

type Comment @aws_cognito_user_pools {
  id: ID!
  postId: ID! @index(name: "byPost", queryField: "commentsByPost")
  content: String!
  author: String!
  createdAt: String!
  updatedAt: String!
  post: Post @connection(fields: ["postId"])
}

type Query {
  getPost(id: ID!): Post
  listPosts: [Post]
  getComment(id: ID!): Comment
  commentsByPost(postId: ID!): [Comment]
}

type Mutation {
  createPost(input: CreatePostInput!): Post
  updatePost(input: UpdatePostInput!): Post
  deletePost(input: DeletePostInput!): Post
  createComment(input: CreateCommentInput!): Comment
  updateComment(input: UpdateCommentInput!): Comment
  deleteComment(input: DeleteCommentInput!): Comment
}

type Subscription {
  onCreatePost: Post @aws_subscribe(mutations: ["createPost"])
  onUpdatePost: Post @aws_subscribe(mutations: ["updatePost"])
  onDeletePost: Post @aws_subscribe(mutations: ["deletePost"])
  onCreateComment: Comment @aws_subscribe(mutations: ["createComment"])
  onUpdateComment: Comment @aws_subscribe(mutations: ["updateComment"])
  onDeleteComment: Comment @aws_subscribe(mutations: ["deleteComment"])
}

input CreatePostInput {
  title: String!
  content: String!
  author: String!
}

input UpdatePostInput {
  id: ID!
  title: String
  content: String
}

input DeletePostInput {
  id: ID!
}

input CreateCommentInput {
  postId: ID!
  content: String!
  author: String!
}

input UpdateCommentInput {
  id: ID!
  content: String
}

input DeleteCommentInput {
  id: ID!
}
EOF
}

# ==============================================================================
# AppSync Data Sources
# ==============================================================================

# IAM role for AppSync to access DynamoDB
resource "aws_iam_role" "appsync_dynamodb" {
  name = "${local.project_name}-appsync-dynamodb-role"

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
resource "aws_iam_role_policy" "appsync_dynamodb" {
  name = "${local.project_name}-appsync-dynamodb-policy"
  role = aws_iam_role.appsync_dynamodb.id

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
          aws_dynamodb_table.posts.arn,
          aws_dynamodb_table.comments.arn,
          "${aws_dynamodb_table.comments.arn}/index/*"
        ]
      }
    ]
  })
}

# IAM role for AppSync logging
resource "aws_iam_role" "appsync_logs" {
  name = "${local.project_name}-appsync-logs-role"

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

# IAM policy for AppSync logging
resource "aws_iam_role_policy" "appsync_logs" {
  name = "${local.project_name}-appsync-logs-policy"
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

# AppSync data source for Posts table
resource "aws_appsync_datasource" "posts" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "PostsDataSource"
  service_role_arn = aws_iam_role.appsync_dynamodb.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = aws_dynamodb_table.posts.name
  }
}

# AppSync data source for Comments table
resource "aws_appsync_datasource" "comments" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "CommentsDataSource"
  service_role_arn = aws_iam_role.appsync_dynamodb.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = aws_dynamodb_table.comments.name
  }
}

# ==============================================================================
# AppSync Resolvers
# ==============================================================================

# Resolver for creating posts
resource "aws_appsync_resolver" "create_post" {
  api_id      = aws_appsync_graphql_api.main.id
  field       = "createPost"
  type        = "Mutation"
  data_source = aws_appsync_datasource.posts.name

  request_template = <<EOF
{
  "version": "2018-05-29",
  "operation": "PutItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($util.autoId())
  },
  "attributeValues": {
    "title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
    "content": $util.dynamodb.toDynamoDBJson($ctx.args.input.content),
    "author": $util.dynamodb.toDynamoDBJson($ctx.args.input.author),
    "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
    "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
  }
}
EOF

  response_template = "$util.toJson($ctx.result)"
}

# Resolver for getting a post
resource "aws_appsync_resolver" "get_post" {
  api_id      = aws_appsync_graphql_api.main.id
  field       = "getPost"
  type        = "Query"
  data_source = aws_appsync_datasource.posts.name

  request_template = <<EOF
{
  "version": "2018-05-29",
  "operation": "GetItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
  }
}
EOF

  response_template = "$util.toJson($ctx.result)"
}

# Resolver for listing posts
resource "aws_appsync_resolver" "list_posts" {
  api_id      = aws_appsync_graphql_api.main.id
  field       = "listPosts"
  type        = "Query"
  data_source = aws_appsync_datasource.posts.name

  request_template = <<EOF
{
  "version": "2018-05-29",
  "operation": "Scan"
}
EOF

  response_template = "$util.toJson($ctx.result.items)"
}

# Resolver for creating comments
resource "aws_appsync_resolver" "create_comment" {
  api_id      = aws_appsync_graphql_api.main.id
  field       = "createComment"
  type        = "Mutation"
  data_source = aws_appsync_datasource.comments.name

  request_template = <<EOF
{
  "version": "2018-05-29",
  "operation": "PutItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($util.autoId()),
    "postId": $util.dynamodb.toDynamoDBJson($ctx.args.input.postId)
  },
  "attributeValues": {
    "content": $util.dynamodb.toDynamoDBJson($ctx.args.input.content),
    "author": $util.dynamodb.toDynamoDBJson($ctx.args.input.author),
    "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
    "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
  }
}
EOF

  response_template = "$util.toJson($ctx.result)"
}

# ==============================================================================
# S3 Bucket for File Storage
# ==============================================================================

# S3 bucket for user file uploads
resource "aws_s3_bucket" "user_files" {
  bucket = "${local.project_name}-user-files-${random_id.suffix.hex}"

  tags = local.common_tags
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "user_files" {
  bucket = aws_s3_bucket.user_files.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "user_files" {
  bucket = aws_s3_bucket.user_files.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "user_files" {
  bucket = aws_s3_bucket.user_files.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket CORS configuration for web/mobile access
resource "aws_s3_bucket_cors_configuration" "user_files" {
  bucket = aws_s3_bucket.user_files.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# ==============================================================================
# Amazon Pinpoint for Analytics and Push Notifications
# ==============================================================================

# Pinpoint application for user analytics
resource "aws_pinpoint_app" "main" {
  name = "${local.project_name}-analytics"

  tags = local.common_tags
}

# ==============================================================================
# Lambda Function for Custom Business Logic
# ==============================================================================

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution" {
  name = "${local.project_name}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM policy for Lambda DynamoDB access
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${local.project_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_execution.id

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
          aws_dynamodb_table.posts.arn,
          aws_dynamodb_table.comments.arn
        ]
      }
    ]
  })
}

# Archive for Lambda function code
data "archive_file" "lambda_function" {
  type        = "zip"
  output_path = "/tmp/lambda_function.zip"
  
  source {
    content = <<EOF
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
    console.log('Event received:', JSON.stringify(event, null, 2));
    
    try {
        // Example: Process post creation and send notifications
        if (event.typeName === 'Mutation' && event.fieldName === 'createPost') {
            const post = event.arguments.input;
            
            // Add processing logic here
            // Example: content moderation, image processing, etc.
            
            return {
                statusCode: 200,
                body: JSON.stringify({
                    message: 'Post processed successfully',
                    postId: post.id
                })
            };
        }
        
        return {
            statusCode: 200,
            body: JSON.stringify({ message: 'Function executed successfully' })
        };
    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: 'Internal server error' })
        };
    }
};
EOF
    filename = "index.js"
  }
}

# Lambda function for post processing
resource "aws_lambda_function" "post_processor" {
  filename         = data.archive_file.lambda_function.output_path
  function_name    = "${local.project_name}-post-processor"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  source_code_hash = data.archive_file.lambda_function.output_base64sha256

  environment {
    variables = {
      POSTS_TABLE_NAME    = aws_dynamodb_table.posts.name
      COMMENTS_TABLE_NAME = aws_dynamodb_table.comments.name
    }
  }

  tags = local.common_tags
}

# ==============================================================================
# CloudWatch Dashboard for Monitoring
# ==============================================================================

# CloudWatch dashboard for monitoring the mobile backend
resource "aws_cloudwatch_dashboard" "mobile_backend" {
  dashboard_name = "${local.project_name}-mobile-backend"

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
            ["AWS/AppSync", "4XXError", "GraphQLAPIId", aws_appsync_graphql_api.main.id],
            [".", "5XXError", ".", "."],
            [".", "RequestCount", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "AppSync API Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.posts.name],
            [".", "ConsumedWriteCapacityUnits", ".", "."],
            [".", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.comments.name],
            [".", "ConsumedWriteCapacityUnits", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "DynamoDB Capacity Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.post_processor.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Lambda Function Metrics"
          period  = 300
        }
      }
    ]
  })
}