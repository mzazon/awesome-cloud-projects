# Generate unique resource identifiers
resource "random_id" "suffix" {
  byte_length = 4
}

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Common naming conventions
  name_prefix = "${var.project_name}-${var.environment}"
  suffix      = random_id.suffix.hex
  
  # Common tags
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "multi-tenant-saas-amplify"
  })
}

# ==========================================
# KMS Key for Encryption
# ==========================================

resource "aws_kms_key" "main" {
  description             = "KMS key for ${local.name_prefix} multi-tenant SaaS encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowServiceAccess"
        Effect = "Allow"
        Principal = {
          Service = [
            "dynamodb.amazonaws.com",
            "s3.amazonaws.com",
            "logs.amazonaws.com",
            "lambda.amazonaws.com"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kms-key"
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name_prefix}-key"
  target_key_id = aws_kms_key.main.key_id
}

# ==========================================
# DynamoDB Tables for Multi-Tenant Data
# ==========================================

# Tenant table
resource "aws_dynamodb_table" "tenant" {
  name           = "${local.name_prefix}-tenant-${local.suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "domain"
    type = "S"
  }

  attribute {
    name = "subdomain"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name     = "DomainIndex"
    hash_key = "domain"
    projection_type = "ALL"
  }

  global_secondary_index {
    name     = "SubdomainIndex"
    hash_key = "subdomain"
    projection_type = "ALL"
  }

  global_secondary_index {
    name     = "StatusIndex"
    hash_key = "status"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled     = var.enable_dynamodb_encryption
    kms_key_arn = var.enable_dynamodb_encryption ? aws_kms_key.main.arn : null
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-tenant-table"
    Type = "TenantData"
  })
}

# User table
resource "aws_dynamodb_table" "user" {
  name           = "${local.name_prefix}-user-${local.suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "tenantId"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  global_secondary_index {
    name            = "UserIdIndex"
    hash_key        = "userId"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "byTenant"
    hash_key        = "tenantId"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "EmailIndex"
    hash_key        = "email"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled     = var.enable_dynamodb_encryption
    kms_key_arn = var.enable_dynamodb_encryption ? aws_kms_key.main.arn : null
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-user-table"
    Type = "UserData"
  })
}

# Project table
resource "aws_dynamodb_table" "project" {
  name           = "${local.name_prefix}-project-${local.suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "tenantId"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  attribute {
    name = "createdBy"
    type = "S"
  }

  global_secondary_index {
    name            = "byTenant"
    hash_key        = "tenantId"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "byCreatedBy"
    hash_key        = "createdBy"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled     = var.enable_dynamodb_encryption
    kms_key_arn = var.enable_dynamodb_encryption ? aws_kms_key.main.arn : null
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-project-table"
    Type = "ProjectData"
  })
}

# Task table
resource "aws_dynamodb_table" "task" {
  name           = "${local.name_prefix}-task-${local.suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "tenantId"
    type = "S"
  }

  attribute {
    name = "projectId"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  attribute {
    name = "assignedTo"
    type = "S"
  }

  global_secondary_index {
    name            = "byTenantAndStatus"
    hash_key        = "tenantId"
    range_key       = "status"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "byProject"
    hash_key        = "projectId"
    range_key       = "status"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "byAssignedTo"
    hash_key        = "assignedTo"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled     = var.enable_dynamodb_encryption
    kms_key_arn = var.enable_dynamodb_encryption ? aws_kms_key.main.arn : null
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-task-table"
    Type = "TaskData"
  })
}

# Activity Log table
resource "aws_dynamodb_table" "activity_log" {
  name           = "${local.name_prefix}-activity-log-${local.suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "tenantId"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "action"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  global_secondary_index {
    name            = "byTenantAndAction"
    hash_key        = "tenantId"
    range_key       = "action"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "byUser"
    hash_key        = "userId"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  # TTL for automatic log cleanup (90 days)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled     = var.enable_dynamodb_encryption
    kms_key_arn = var.enable_dynamodb_encryption ? aws_kms_key.main.arn : null
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-activity-log-table"
    Type = "AuditData"
  })
}

# Billing Info table
resource "aws_dynamodb_table" "billing_info" {
  name           = "${local.name_prefix}-billing-info-${local.suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "tenantId"
    type = "S"
  }

  global_secondary_index {
    name            = "byTenant"
    hash_key        = "tenantId"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled     = var.enable_dynamodb_encryption
    kms_key_arn = var.enable_dynamodb_encryption ? aws_kms_key.main.arn : null
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-billing-info-table"
    Type = "BillingData"
  })
}

# Tenant Usage table
resource "aws_dynamodb_table" "tenant_usage" {
  name           = "${local.name_prefix}-tenant-usage-${local.suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "tenantId"
    type = "S"
  }

  attribute {
    name = "month"
    type = "S"
  }

  global_secondary_index {
    name            = "byMonth"
    hash_key        = "month"
    range_key       = "tenantId"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled     = var.enable_dynamodb_encryption
    kms_key_arn = var.enable_dynamodb_encryption ? aws_kms_key.main.arn : null
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-tenant-usage-table"
    Type = "UsageData"
  })
}

# ==========================================
# S3 Buckets for Multi-Tenant Storage
# ==========================================

# Main application bucket for tenant assets
resource "aws_s3_bucket" "tenant_assets" {
  bucket = "${local.name_prefix}-tenant-assets-${local.suffix}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-tenant-assets"
    Type = "TenantAssets"
  })
}

resource "aws_s3_bucket_versioning" "tenant_assets" {
  bucket = aws_s3_bucket.tenant_assets.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tenant_assets" {
  bucket = aws_s3_bucket.tenant_assets.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tenant_assets" {
  bucket = aws_s3_bucket.tenant_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tenant_assets" {
  count  = var.enable_cost_optimization ? 1 : 0
  bucket = aws_s3_bucket.tenant_assets.id

  rule {
    id     = "optimize_storage"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_lifecycle_transition_days * 2
      storage_class = "GLACIER"
    }

    expiration {
      days = var.s3_lifecycle_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# CloudWatch Logs bucket for log archiving
resource "aws_s3_bucket" "logs" {
  bucket = "${local.name_prefix}-logs-${local.suffix}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-logs"
    Type = "LogArchive"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==========================================
# IAM Roles and Policies
# ==========================================

# Lambda execution role for tenant resolver
resource "aws_iam_role" "tenant_resolver_lambda_role" {
  name = "${local.name_prefix}-tenant-resolver-lambda-role-${local.suffix}"

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

resource "aws_iam_role_policy" "tenant_resolver_lambda_policy" {
  name = "${local.name_prefix}-tenant-resolver-lambda-policy"
  role = aws_iam_role.tenant_resolver_lambda_role.id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
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
          aws_dynamodb_table.tenant.arn,
          aws_dynamodb_table.user.arn,
          aws_dynamodb_table.project.arn,
          aws_dynamodb_table.activity_log.arn,
          aws_dynamodb_table.billing_info.arn,
          "${aws_dynamodb_table.tenant.arn}/index/*",
          "${aws_dynamodb_table.user.arn}/index/*",
          "${aws_dynamodb_table.project.arn}/index/*",
          "${aws_dynamodb_table.activity_log.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminSetUserPassword",
          "cognito-idp:AdminAddUserToGroup",
          "cognito-idp:AdminRemoveUserFromGroup",
          "cognito-idp:AdminListGroupsForUser",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminUpdateUserAttributes"
        ]
        Resource = aws_cognito_user_pool.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*"
        ]
        Resource = aws_kms_key.main.arn
      }
    ]
  })
}

# Lambda execution role for auth triggers
resource "aws_iam_role" "auth_triggers_lambda_role" {
  name = "${local.name_prefix}-auth-triggers-lambda-role-${local.suffix}"

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

resource "aws_iam_role_policy" "auth_triggers_lambda_policy" {
  name = "${local.name_prefix}-auth-triggers-lambda-policy"
  role = aws_iam_role.auth_triggers_lambda_role.id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
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
          aws_dynamodb_table.tenant.arn,
          aws_dynamodb_table.user.arn,
          aws_dynamodb_table.activity_log.arn,
          "${aws_dynamodb_table.tenant.arn}/index/*",
          "${aws_dynamodb_table.user.arn}/index/*",
          "${aws_dynamodb_table.activity_log.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminListGroupsForUser",
          "cognito-idp:AdminAddUserToGroup"
        ]
        Resource = aws_cognito_user_pool.main.arn
      }
    ]
  })
}

# AppSync service role
resource "aws_iam_role" "appsync_service_role" {
  name = "${local.name_prefix}-appsync-service-role-${local.suffix}"

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

resource "aws_iam_role_policy" "appsync_service_policy" {
  name = "${local.name_prefix}-appsync-service-policy"
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
          aws_dynamodb_table.tenant.arn,
          aws_dynamodb_table.user.arn,
          aws_dynamodb_table.project.arn,
          aws_dynamodb_table.task.arn,
          aws_dynamodb_table.activity_log.arn,
          aws_dynamodb_table.billing_info.arn,
          aws_dynamodb_table.tenant_usage.arn,
          "${aws_dynamodb_table.tenant.arn}/index/*",
          "${aws_dynamodb_table.user.arn}/index/*",
          "${aws_dynamodb_table.project.arn}/index/*",
          "${aws_dynamodb_table.task.arn}/index/*",
          "${aws_dynamodb_table.activity_log.arn}/index/*",
          "${aws_dynamodb_table.billing_info.arn}/index/*",
          "${aws_dynamodb_table.tenant_usage.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.tenant_resolver.arn,
          aws_lambda_function.auth_triggers.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# ==========================================
# Lambda Functions
# ==========================================

# Lambda function ZIP files
data "archive_file" "tenant_resolver_zip" {
  type        = "zip"
  output_path = "/tmp/tenant_resolver.zip"
  source {
    content = templatefile("${path.module}/lambda_functions/tenant_resolver.js", {
      tenant_table     = aws_dynamodb_table.tenant.name
      user_table       = aws_dynamodb_table.user.name
      activity_table   = aws_dynamodb_table.activity_log.name
      billing_table    = aws_dynamodb_table.billing_info.name
    })
    filename = "index.js"
  }
}

data "archive_file" "auth_triggers_zip" {
  type        = "zip"
  output_path = "/tmp/auth_triggers.zip"
  source {
    content = templatefile("${path.module}/lambda_functions/auth_triggers.js", {
      tenant_table   = aws_dynamodb_table.tenant.name
      user_table     = aws_dynamodb_table.user.name
      activity_table = aws_dynamodb_table.activity_log.name
    })
    filename = "index.js"
  }
}

# Tenant resolver Lambda function
resource "aws_lambda_function" "tenant_resolver" {
  filename         = data.archive_file.tenant_resolver_zip.output_path
  function_name    = "${local.name_prefix}-tenant-resolver-${local.suffix}"
  role            = aws_iam_role.tenant_resolver_lambda_role.arn
  handler         = "index.handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      TENANT_TABLE     = aws_dynamodb_table.tenant.name
      USER_TABLE       = aws_dynamodb_table.user.name
      ACTIVITY_LOG_TABLE = aws_dynamodb_table.activity_log.name
      BILLING_TABLE    = aws_dynamodb_table.billing_info.name
      KMS_KEY_ID       = aws_kms_key.main.arn
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-tenant-resolver"
    Type = "TenantManagement"
  })

  depends_on = [
    aws_iam_role_policy.tenant_resolver_lambda_policy,
    aws_cloudwatch_log_group.tenant_resolver
  ]
}

# Auth triggers Lambda function
resource "aws_lambda_function" "auth_triggers" {
  filename         = data.archive_file.auth_triggers_zip.output_path
  function_name    = "${local.name_prefix}-auth-triggers-${local.suffix}"
  role            = aws_iam_role.auth_triggers_lambda_role.arn
  handler         = "index.handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      TENANT_TABLE       = aws_dynamodb_table.tenant.name
      USER_TABLE         = aws_dynamodb_table.user.name
      ACTIVITY_LOG_TABLE = aws_dynamodb_table.activity_log.name
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-auth-triggers"
    Type = "Authentication"
  })

  depends_on = [
    aws_iam_role_policy.auth_triggers_lambda_policy,
    aws_cloudwatch_log_group.auth_triggers
  ]
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "tenant_resolver" {
  name              = "/aws/lambda/${local.name_prefix}-tenant-resolver-${local.suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-tenant-resolver-logs"
  })
}

resource "aws_cloudwatch_log_group" "auth_triggers" {
  name              = "/aws/lambda/${local.name_prefix}-auth-triggers-${local.suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-auth-triggers-logs"
  })
}

# Lambda permissions for Cognito triggers
resource "aws_lambda_permission" "cognito_pre_signup" {
  statement_id  = "AllowCognitoPreSignUp"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_triggers.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}

resource "aws_lambda_permission" "cognito_post_confirmation" {
  statement_id  = "AllowCognitoPostConfirmation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_triggers.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}

resource "aws_lambda_permission" "cognito_pre_authentication" {
  statement_id  = "AllowCognitoPreAuthentication"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_triggers.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}

resource "aws_lambda_permission" "cognito_token_generation" {
  statement_id  = "AllowCognitoTokenGeneration"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_triggers.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}

# ==========================================
# Amazon Cognito User Pool
# ==========================================

resource "aws_cognito_user_pool" "main" {
  name = "${local.name_prefix}-user-pool-${local.suffix}"

  # User attributes
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # User pool add-ons
  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }

  # Lambda triggers for tenant-aware authentication
  lambda_config {
    pre_sign_up                    = aws_lambda_function.auth_triggers.arn
    post_confirmation              = aws_lambda_function.auth_triggers.arn
    pre_authentication             = aws_lambda_function.auth_triggers.arn
    pre_token_generation           = aws_lambda_function.auth_triggers.arn
  }

  # Custom attributes for tenant information
  schema {
    name                = "tenant_id"
    attribute_data_type = "String"
    mutable             = true
    
    string_attribute_constraints {
      max_length = "256"
      min_length = "1"
    }
  }

  schema {
    name                = "user_role"
    attribute_data_type = "String"
    mutable             = true
    
    string_attribute_constraints {
      max_length = "50"
      min_length = "1"
    }
  }

  # Device configuration
  device_configuration {
    challenge_required_on_new_device      = true
    device_only_remembered_on_user_prompt = true
  }

  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Verification message templates
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your verification code"
    email_message        = "Your verification code is {####}"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-user-pool"
    Type = "Authentication"
  })

  depends_on = [
    aws_lambda_permission.cognito_pre_signup,
    aws_lambda_permission.cognito_post_confirmation,
    aws_lambda_permission.cognito_pre_authentication,
    aws_lambda_permission.cognito_token_generation
  ]
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${local.name_prefix}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  enable_propagate_additional_user_context_data = true

  # OAuth configuration
  supported_identity_providers = ["COGNITO"]
  
  callback_urls = var.cognito_callback_urls
  logout_urls   = var.cognito_logout_urls

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "profile", "aws.cognito.signin.user.admin"]

  # Token validity
  id_token_validity      = 60    # 1 hour
  access_token_validity  = 60    # 1 hour
  refresh_token_validity = 30    # 30 days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # Read and write attributes
  read_attributes = [
    "email",
    "email_verified",
    "given_name",
    "family_name",
    "custom:tenant_id",
    "custom:user_role"
  ]

  write_attributes = [
    "email",
    "given_name",
    "family_name",
    "custom:tenant_id",
    "custom:user_role"
  ]

  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

# Cognito User Pool Domain (optional)
resource "aws_cognito_user_pool_domain" "main" {
  count        = var.cognito_domain_prefix != null ? 1 : 0
  domain       = "${var.cognito_domain_prefix}-${local.suffix}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# Cognito Identity Pool
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${local.name_prefix}-identity-pool-${local.suffix}"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.main.id
    provider_name           = aws_cognito_user_pool.main.endpoint
    server_side_token_check = false
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-identity-pool"
    Type = "Authentication"
  })
}

# Cognito User Groups for tenant isolation
resource "aws_cognito_user_group" "super_admins" {
  name         = "SuperAdmins"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Super administrators with platform-wide access"
  precedence   = 1
}

resource "aws_cognito_user_group" "tenant_admins" {
  name         = "TenantAdmins"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Tenant administrators with tenant-specific admin access"
  precedence   = 2
}

# ==========================================
# AWS AppSync GraphQL API
# ==========================================

resource "aws_appsync_graphql_api" "main" {
  name                = "${local.name_prefix}-graphql-api-${local.suffix}"
  authentication_type = var.appsync_authentication_type

  # Primary authentication with Cognito User Pool
  user_pool_config {
    user_pool_id   = aws_cognito_user_pool.main.id
    aws_region     = data.aws_region.current.name
    default_action = "ALLOW"
  }

  # Additional authentication types
  additional_authentication_provider {
    authentication_type = "AWS_IAM"
  }

  # Logging configuration
  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync_cloudwatch_role.arn
    field_log_level          = var.appsync_log_level
    exclude_verbose_content  = true
  }

  # X-Ray tracing
  xray_enabled = var.enable_xray_tracing

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-graphql-api"
    Type = "API"
  })
}

# AppSync CloudWatch logging role
resource "aws_iam_role" "appsync_cloudwatch_role" {
  name = "${local.name_prefix}-appsync-cloudwatch-role-${local.suffix}"

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

resource "aws_iam_role_policy_attachment" "appsync_cloudwatch_policy" {
  role       = aws_iam_role.appsync_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AppSyncPushToCloudWatchLogs"
}

# AppSync GraphQL Schema
resource "aws_appsync_graphql_api" "schema" {
  api_id = aws_appsync_graphql_api.main.id
  schema = file("${path.module}/graphql/schema.graphql")
}

# ==========================================
# AppSync Data Sources
# ==========================================

# DynamoDB data sources
resource "aws_appsync_datasource" "tenant_table" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "TenantTable"
  service_role_arn = aws_iam_role.appsync_service_role.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = aws_dynamodb_table.tenant.name
  }
}

resource "aws_appsync_datasource" "user_table" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "UserTable"
  service_role_arn = aws_iam_role.appsync_service_role.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = aws_dynamodb_table.user.name
  }
}

resource "aws_appsync_datasource" "project_table" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "ProjectTable"
  service_role_arn = aws_iam_role.appsync_service_role.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = aws_dynamodb_table.project.name
  }
}

resource "aws_appsync_datasource" "task_table" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "TaskTable"
  service_role_arn = aws_iam_role.appsync_service_role.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = aws_dynamodb_table.task.name
  }
}

# Lambda data source for tenant resolver
resource "aws_appsync_datasource" "tenant_resolver" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "TenantResolver"
  service_role_arn = aws_iam_role.appsync_service_role.arn
  type             = "AWS_LAMBDA"

  lambda_config {
    function_arn = aws_lambda_function.tenant_resolver.arn
  }
}

# ==========================================
# CloudWatch Monitoring and Alarms
# ==========================================

# CloudWatch Log Group for AppSync
resource "aws_cloudwatch_log_group" "appsync" {
  count             = var.enable_appsync_logging ? 1 : 0
  name              = "/aws/appsync/apis/${aws_appsync_graphql_api.main.id}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-appsync-logs"
  })
}

# CloudWatch Alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.tenant_resolver.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-dynamodb-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "SystemErrors"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors DynamoDB throttling"
  alarm_actions       = []

  dimensions = {
    TableName = aws_dynamodb_table.tenant.name
  }

  tags = local.common_tags
}