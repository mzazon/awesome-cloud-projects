# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "graphql-apis-appsync-dynamodb"
    ManagedBy   = "terraform"
  }
  
  # DynamoDB table names
  products_table_name  = "Products-${random_string.suffix.result}"
  users_table_name     = "Users-${random_string.suffix.result}"
  analytics_table_name = "Analytics-${random_string.suffix.result}"
  
  # OpenSearch domain name
  opensearch_domain_name = "products-search-${random_string.suffix.result}"
  
  # Lambda function name
  lambda_function_name = "ProductBusinessLogic-${random_string.suffix.result}"
}

#################################################################
# DynamoDB Tables
#################################################################

# Products table with Global Secondary Indexes
resource "aws_dynamodb_table" "products" {
  name           = local.products_table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "productId"
  
  # Stream configuration for real-time processing
  stream_enabled   = var.enable_dynamodb_streams
  stream_view_type = var.enable_dynamodb_streams ? "NEW_AND_OLD_IMAGES" : null
  
  # Enable deletion protection for production
  deletion_protection_enabled = var.enable_deletion_protection
  
  # Table attributes
  attribute {
    name = "productId"
    type = "S"
  }
  
  attribute {
    name = "category"
    type = "S"
  }
  
  attribute {
    name = "createdAt"
    type = "S"
  }
  
  attribute {
    name = "priceRange"
    type = "S"
  }
  
  # Category index for efficient category-based queries
  global_secondary_index {
    name               = "CategoryIndex"
    hash_key           = "category"
    range_key          = "createdAt"
    projection_type    = "ALL"
  }
  
  # Price range index for price-based filtering
  global_secondary_index {
    name               = "PriceRangeIndex"
    hash_key           = "priceRange"
    range_key          = "createdAt"
    projection_type    = "ALL"
  }
  
  # Server-side encryption
  server_side_encryption {
    enabled = true
  }
  
  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_backup
  }
  
  tags = merge(local.common_tags, {
    Name = local.products_table_name
    Type = "Products"
  })
}

# Users table for user management
resource "aws_dynamodb_table" "users" {
  name           = local.users_table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "userId"
  
  # Enable deletion protection for production
  deletion_protection_enabled = var.enable_deletion_protection
  
  # Table attributes
  attribute {
    name = "userId"
    type = "S"
  }
  
  attribute {
    name = "userType"
    type = "S"
  }
  
  attribute {
    name = "createdAt"
    type = "S"
  }
  
  # User type index for role-based queries
  global_secondary_index {
    name               = "UserTypeIndex"
    hash_key           = "userType"
    range_key          = "createdAt"
    projection_type    = "ALL"
  }
  
  # Server-side encryption
  server_side_encryption {
    enabled = true
  }
  
  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_backup
  }
  
  tags = merge(local.common_tags, {
    Name = local.users_table_name
    Type = "Users"
  })
}

# Analytics table for real-time metrics
resource "aws_dynamodb_table" "analytics" {
  name           = local.analytics_table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "metricId"
  range_key      = "timestamp"
  
  # Table attributes
  attribute {
    name = "metricId"
    type = "S"
  }
  
  attribute {
    name = "timestamp"
    type = "S"
  }
  
  # TTL for automatic data cleanup
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
  
  # Server-side encryption
  server_side_encryption {
    enabled = true
  }
  
  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_backup
  }
  
  tags = merge(local.common_tags, {
    Name = local.analytics_table_name
    Type = "Analytics"
  })
}

#################################################################
# OpenSearch Service Domain
#################################################################

# OpenSearch domain for advanced search capabilities
resource "aws_opensearch_domain" "products_search" {
  domain_name    = local.opensearch_domain_name
  engine_version = "OpenSearch_2.3"
  
  # Cluster configuration
  cluster_config {
    instance_type            = var.opensearch_instance_type
    instance_count           = var.opensearch_instance_count
    dedicated_master_enabled = false
  }
  
  # EBS storage configuration
  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.opensearch_ebs_volume_size
  }
  
  # Security and encryption
  encrypt_at_rest {
    enabled = var.enable_opensearch_encryption
  }
  
  node_to_node_encryption {
    enabled = var.enable_opensearch_encryption
  }
  
  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }
  
  # Access policy allowing account access
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain_name}/*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = local.opensearch_domain_name
    Type = "Search"
  })
}

#################################################################
# Cognito User Pool
#################################################################

# Cognito User Pool for authentication
resource "aws_cognito_user_pool" "main" {
  name = "${local.name_prefix}-users"
  
  # Password policy
  password_policy {
    minimum_length    = var.cognito_password_policy.minimum_length
    require_lowercase = var.cognito_password_policy.require_lowercase
    require_numbers   = var.cognito_password_policy.require_numbers
    require_symbols   = var.cognito_password_policy.require_symbols
    require_uppercase = var.cognito_password_policy.require_uppercase
  }
  
  # Username and verification configuration
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  
  # Custom attributes for user metadata
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }
  
  schema {
    name                = "user_type"
    attribute_data_type = "String"
    required            = false
    mutable             = true
  }
  
  schema {
    name                = "company"
    attribute_data_type = "String"
    required            = false
    mutable             = true
  }
  
  # Verification message template
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-users"
    Type = "Authentication"
  })
}

# User Pool Client for application access
resource "aws_cognito_user_pool_client" "main" {
  name         = "${local.name_prefix}-client"
  user_pool_id = aws_cognito_user_pool.main.id
  
  # Authentication flows
  explicit_auth_flows = [
    "ADMIN_NO_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_CUSTOM_AUTH"
  ]
  
  # Security settings
  prevent_user_existence_errors = "ENABLED"
  
  # Token validity settings
  access_token_validity  = 60  # minutes
  id_token_validity      = 60  # minutes
  refresh_token_validity = 30  # days
  
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

# User groups for role-based access control
resource "aws_cognito_user_group" "groups" {
  for_each = {
    for group in var.cognito_user_groups : group.name => group
  }
  
  name         = each.value.name
  user_pool_id = aws_cognito_user_pool.main.id
  description  = each.value.description
}

#################################################################
# Lambda Function for Business Logic
#################################################################

# Lambda function package
data "archive_file" "lambda_package" {
  type        = "zip"
  output_path = "lambda-function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.js", {
      products_table_name  = local.products_table_name
      users_table_name     = local.users_table_name
      analytics_table_name = local.analytics_table_name
      opensearch_endpoint  = aws_opensearch_domain.products_search.endpoint
    })
    filename = "index.js"
  }
  
  source {
    content  = file("${path.module}/package.json")
    filename = "package.json"
  }
}

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
  name = "LambdaExecutionRole-${random_string.suffix.result}"
  
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

# Lambda execution policy
resource "aws_iam_role_policy" "lambda_execution" {
  name = "LambdaCustomPolicy"
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
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.products.arn,
          "${aws_dynamodb_table.products.arn}/*",
          aws_dynamodb_table.users.arn,
          aws_dynamodb_table.analytics.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "es:ESHttpGet",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpDelete"
        ]
        Resource = "${aws_opensearch_domain.products_search.arn}/*"
      }
    ]
  })
}

# Attach basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function
resource "aws_lambda_function" "business_logic" {
  filename         = data.archive_file.lambda_package.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution.arn
  handler         = "index.handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  
  environment {
    variables = {
      PRODUCTS_TABLE      = local.products_table_name
      USERS_TABLE         = local.users_table_name
      ANALYTICS_TABLE     = local.analytics_table_name
      OPENSEARCH_ENDPOINT = aws_opensearch_domain.products_search.endpoint
    }
  }
  
  tags = merge(local.common_tags, {
    Name = local.lambda_function_name
    Type = "BusinessLogic"
  })
}

#################################################################
# AppSync GraphQL API
#################################################################

# AppSync CloudWatch logging role
resource "aws_iam_role" "appsync_logging" {
  count = var.enable_appsync_logging ? 1 : 0
  name  = "AppSyncLoggingRole-${random_string.suffix.result}"
  
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

resource "aws_iam_role_policy_attachment" "appsync_logging" {
  count      = var.enable_appsync_logging ? 1 : 0
  role       = aws_iam_role.appsync_logging[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AppSyncPushToCloudWatchLogs"
}

# AppSync GraphQL API
resource "aws_appsync_graphql_api" "main" {
  name                = local.name_prefix
  authentication_type = var.appsync_authentication_type
  
  # Multiple authentication providers
  additional_authentication_provider {
    authentication_type = "API_KEY"
  }
  
  additional_authentication_provider {
    authentication_type = "AWS_IAM"
  }
  
  # Cognito User Pool configuration
  user_pool_config {
    user_pool_id   = aws_cognito_user_pool.main.id
    aws_region     = data.aws_region.current.name
    default_action = "ALLOW"
  }
  
  # Enhanced logging configuration
  dynamic "log_config" {
    for_each = var.enable_appsync_logging ? [1] : []
    content {
      field_log_level               = "ALL"
      cloudwatch_logs_role_arn     = aws_iam_role.appsync_logging[0].arn
      exclude_verbose_content      = false
    }
  }
  
  # X-Ray tracing
  xray_enabled = var.enable_appsync_xray
  
  tags = merge(local.common_tags, {
    Name = local.name_prefix
    Type = "GraphQLAPI"
  })
}

# AppSync API Key for development
resource "aws_appsync_api_key" "main" {
  api_id  = aws_appsync_graphql_api.main.id
  expires = timeadd(timestamp(), "${var.api_key_expires_days * 24}h")
}

# GraphQL Schema
resource "aws_appsync_graphql_api" "schema" {
  # This would typically load from a separate file
  # For simplicity, we'll reference it as a dependency
  depends_on = [aws_appsync_graphql_api.main]
}

#################################################################
# AppSync Data Sources
#################################################################

# IAM role for AppSync to access DynamoDB
resource "aws_iam_role" "appsync_dynamodb" {
  name = "AppSyncDynamoDBRole-${random_string.suffix.result}"
  
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

# Policy for DynamoDB access
resource "aws_iam_role_policy" "appsync_dynamodb" {
  name = "DynamoDBAccess"
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
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [
          aws_dynamodb_table.products.arn,
          "${aws_dynamodb_table.products.arn}/*",
          aws_dynamodb_table.users.arn,
          aws_dynamodb_table.analytics.arn
        ]
      }
    ]
  })
}

# DynamoDB data source for products
resource "aws_appsync_datasource" "products" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "ProductsDataSource"
  service_role_arn = aws_iam_role.appsync_dynamodb.arn
  type             = "AMAZON_DYNAMODB"
  
  dynamodb_config {
    table_name = aws_dynamodb_table.products.name
    region     = data.aws_region.current.name
  }
}

# Lambda data source for business logic
resource "aws_appsync_datasource" "business_logic" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "BusinessLogicDataSource"
  service_role_arn = aws_iam_role.lambda_appsync.arn
  type             = "AWS_LAMBDA"
  
  lambda_config {
    function_arn = aws_lambda_function.business_logic.arn
  }
}

# IAM role for AppSync to invoke Lambda
resource "aws_iam_role" "lambda_appsync" {
  name = "AppSyncLambdaRole-${random_string.suffix.result}"
  
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

resource "aws_iam_role_policy" "lambda_appsync" {
  name = "LambdaInvokeAccess"
  role = aws_iam_role.lambda_appsync.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.business_logic.arn
      }
    ]
  })
}

#################################################################
# Sample Data Population
#################################################################

# Lambda function for data loading
resource "aws_lambda_function" "data_loader" {
  count = var.enable_sample_data ? 1 : 0
  
  filename         = "data-loader.zip"
  function_name    = "DataLoader-${random_string.suffix.result}"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60
  
  source_code_hash = data.archive_file.data_loader[0].output_base64sha256
  
  environment {
    variables = {
      PRODUCTS_TABLE = local.products_table_name
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "DataLoader-${random_string.suffix.result}"
    Type = "DataLoader"
  })
}

data "archive_file" "data_loader" {
  count       = var.enable_sample_data ? 1 : 0
  type        = "zip"
  output_path = "data-loader.zip"
  
  source {
    content = templatefile("${path.module}/data_loader.py", {
      products_table_name = local.products_table_name
    })
    filename = "index.py"
  }
}

# Invoke data loader to populate sample data
resource "aws_lambda_invocation" "data_loader" {
  count = var.enable_sample_data ? 1 : 0
  
  function_name = aws_lambda_function.data_loader[0].function_name
  
  input = jsonencode({
    action = "load_sample_data"
  })
  
  depends_on = [
    aws_dynamodb_table.products,
    aws_lambda_function.data_loader
  ]
}

#################################################################
# Test User Creation
#################################################################

# Create test user in Cognito
resource "aws_cognito_user" "test_user" {
  count      = var.create_test_user ? 1 : 0
  user_pool_id = aws_cognito_user_pool.main.id
  username     = var.test_user_email
  
  attributes = {
    email          = var.test_user_email
    email_verified = true
  }
  
  password = "DevUser123!"
  
  message_action = "SUPPRESS"
}