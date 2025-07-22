# ============================================================================
# Enterprise Authentication with AWS Amplify and External Identity Providers
# ============================================================================
# This Terraform configuration deploys a complete enterprise authentication
# solution using AWS Cognito User Pools, Identity Pools, and SAML/OIDC
# federation with external identity providers like Active Directory.
#
# Architecture Components:
# - Amazon Cognito User Pool with SAML/OIDC federation
# - Cognito Identity Pool for AWS resource access
# - IAM roles for authenticated and unauthenticated users
# - Optional API Gateway with Cognito authorization
# - Optional AWS Amplify application hosting
# - S3 bucket for user content storage
# - CloudWatch monitoring and dashboards
# ============================================================================

# Random suffix for resource naming uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

# ============================================================================
# DATA SOURCES
# ============================================================================

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ============================================================================
# LOCAL VALUES
# ============================================================================

locals {
  # Build list of supported identity providers based on configuration
  supported_identity_providers = compact([
    "COGNITO",
    var.enable_saml_provider ? var.saml_provider_name : "",
    var.enable_oidc_provider ? "OIDC" : ""
  ])

  # Common tags applied to all resources
  common_tags = {
    Project              = var.project_name
    Environment          = var.environment
    ManagedBy           = "terraform"
    Recipe              = "enterprise-authentication-amplify-external-identity-providers"
    CreatedBy           = "terraform"
    LastModified        = timestamp()
  }
}

# ============================================================================
# AMAZON COGNITO USER POOL
# ============================================================================

# Primary Cognito User Pool for enterprise authentication
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool-${var.environment}"

  # Configure password policy for enterprise security standards
  password_policy {
    minimum_length                   = var.password_minimum_length
    require_lowercase               = var.password_require_lowercase
    require_numbers                 = var.password_require_numbers
    require_symbols                 = var.password_require_symbols
    require_uppercase               = var.password_require_uppercase
    temporary_password_validity_days = var.temporary_password_validity_days
  }

  # User pool configuration
  alias_attributes         = ["email", "preferred_username"]
  auto_verified_attributes = ["email"]
  username_configuration {
    case_sensitive = false
  }

  # Standard user attributes
  schema {
    name                     = "email"
    attribute_data_type     = "String"
    required                = true
    mutable                 = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  schema {
    name                     = "given_name"
    attribute_data_type     = "String"
    required                = false
    mutable                 = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  schema {
    name                     = "family_name"
    attribute_data_type     = "String"
    required                = false
    mutable                 = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  # Custom attribute for department information from enterprise directory
  schema {
    name                     = "department"
    attribute_data_type     = "String"
    required                = false
    mutable                 = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  # Account recovery settings
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Admin user creation configuration
  admin_create_user_config {
    allow_admin_create_user_only = var.admin_create_user_only
    invite_message_action        = "EMAIL"

    invite_message_template {
      email_message = "Welcome to ${var.project_name}! Your temporary password is {password}. Please sign in and change your password."
      email_subject = "Welcome to ${var.project_name}"
      sms_message   = "Your ${var.project_name} verification code is {password}"
    }
  }

  # Multi-factor authentication configuration
  mfa_configuration          = var.mfa_configuration
  enabled_mfas              = var.enabled_mfas
  sms_authentication_message = "Your ${var.project_name} verification code is {####}"

  # Software token MFA configuration
  dynamic "software_token_mfa_configuration" {
    for_each = contains(var.enabled_mfas, "SOFTWARE_TOKEN_MFA") ? [1] : []
    content {
      enabled = true
    }
  }

  # Advanced security features for threat detection
  user_pool_add_ons {
    advanced_security_mode = var.advanced_security_mode
  }

  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Verification messages
  verification_message_template {
    default_email_option  = "CONFIRM_WITH_LINK"
    email_message_by_link = "Please click the link below to verify your email address: {##Verify Email##}"
    email_subject_by_link = "Verify your ${var.project_name} account"
  }

  tags = local.common_tags
}

# ============================================================================
# SAML IDENTITY PROVIDER
# ============================================================================

# SAML 2.0 Identity Provider for enterprise Active Directory federation
resource "aws_cognito_identity_provider" "saml" {
  count         = var.enable_saml_provider ? 1 : 0
  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = var.saml_provider_name
  provider_type = "SAML"

  # SAML provider configuration with metadata URL from enterprise IdP
  provider_details = {
    MetadataURL = var.saml_metadata_url
  }

  # Attribute mapping between SAML assertions and Cognito attributes
  attribute_mapping = {
    email                = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"
    given_name          = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname"
    family_name         = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname"
    "custom:department" = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/department"
  }

  # Ensure User Pool is created before identity provider
  depends_on = [aws_cognito_user_pool.main]
}

# ============================================================================
# OIDC IDENTITY PROVIDER
# ============================================================================

# OpenID Connect Identity Provider for modern OAuth 2.0 federation
resource "aws_cognito_identity_provider" "oidc" {
  count         = var.enable_oidc_provider ? 1 : 0
  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "OIDC"
  provider_type = "OIDC"

  # OIDC provider configuration
  provider_details = {
    oidc_issuer                   = var.oidc_provider_url
    client_id                     = var.oidc_client_id
    client_secret                 = var.oidc_client_secret
    attributes_request_method     = "GET"
    authorize_scopes             = "openid profile email"
  }

  # Standard OIDC attribute mapping
  attribute_mapping = {
    email       = "email"
    given_name  = "given_name"
    family_name = "family_name"
  }

  # Ensure User Pool is created before identity provider
  depends_on = [aws_cognito_user_pool.main]
}

# ============================================================================
# COGNITO USER POOL CLIENT
# ============================================================================

# User Pool Client for web applications with federation support
resource "aws_cognito_user_pool_client" "web_client" {
  name         = "${var.project_name}-web-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main.id

  # OAuth 2.0 flow configuration
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile", "aws.cognito.signin.user.admin"]

  # Dynamically configure supported identity providers
  supported_identity_providers = local.supported_identity_providers

  # Application callback and logout URLs
  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  # Security and token settings
  generate_secret                = false
  prevent_user_existence_errors  = "ENABLED"
  enable_token_revocation       = true

  # Token validity periods
  refresh_token_validity = var.refresh_token_validity
  access_token_validity  = var.access_token_validity
  id_token_validity     = var.id_token_validity

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # Attribute read/write permissions
  read_attributes  = var.read_attributes
  write_attributes = var.write_attributes

  # Authentication flows
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  # Ensure identity providers are created before client
  depends_on = [
    aws_cognito_identity_provider.saml,
    aws_cognito_identity_provider.oidc
  ]
}

# ============================================================================
# COGNITO USER POOL DOMAIN
# ============================================================================

# Hosted UI domain for authentication flows
resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.user_pool_domain_prefix != "" ? var.user_pool_domain_prefix : "${var.project_name}-auth-${var.environment}-${random_id.suffix.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# ============================================================================
# COGNITO IDENTITY POOL
# ============================================================================

# Identity Pool for AWS resource access with temporary credentials
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${var.project_name}_identity_pool_${var.environment}"
  allow_unauthenticated_identities = var.allow_unauthenticated_identities

  # Configure Cognito User Pool as identity provider
  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.web_client.id
    provider_name           = aws_cognito_user_pool.main.endpoint
    server_side_token_check = true
  }

  tags = local.common_tags
}

# ============================================================================
# IAM ROLES FOR COGNITO IDENTITY POOL
# ============================================================================

# IAM role for authenticated users with AWS resource access
resource "aws_iam_role" "authenticated_user_role" {
  name = "${var.project_name}-authenticated-role-${var.environment}"

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

# IAM policy for authenticated users
resource "aws_iam_role_policy" "authenticated_user_policy" {
  name = "CognitoIdentityPolicy"
  role = aws_iam_role.authenticated_user_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "mobileanalytics:PutEvents",
          "cognito-sync:*",
          "cognito-identity:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.user_content.arn}/private/$${cognito-identity.amazonaws.com:sub}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.user_content.arn}/public/*"
      }
    ]
  })
}

# IAM role for unauthenticated users (minimal permissions)
resource "aws_iam_role" "unauthenticated_user_role" {
  name = "${var.project_name}-unauthenticated-role-${var.environment}"

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
            "cognito-identity.amazonaws.com:amr" = "unauthenticated"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Minimal policy for unauthenticated users
resource "aws_iam_role_policy" "unauthenticated_user_policy" {
  name = "UnauthenticatedPolicy"
  role = aws_iam_role.unauthenticated_user_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "mobileanalytics:PutEvents",
          "cognito-sync:CognitoUnauthenticated"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach roles to Identity Pool
resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    "authenticated"   = aws_iam_role.authenticated_user_role.arn
    "unauthenticated" = aws_iam_role.unauthenticated_user_role.arn
  }

  depends_on = [
    aws_iam_role.authenticated_user_role,
    aws_iam_role.unauthenticated_user_role
  ]
}

# ============================================================================
# S3 BUCKET FOR USER CONTENT
# ============================================================================

# S3 bucket for storing user-generated content with proper security
resource "aws_s3_bucket" "user_content" {
  bucket = "${var.project_name}-user-content-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = local.common_tags
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "user_content" {
  bucket = aws_s3_bucket.user_content.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to maintain security
resource "aws_s3_bucket_public_access_block" "user_content" {
  bucket = aws_s3_bucket.user_content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for data protection
resource "aws_s3_bucket_versioning" "user_content" {
  bucket = aws_s3_bucket.user_content.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle configuration to manage storage costs
resource "aws_s3_bucket_lifecycle_configuration" "user_content" {
  bucket = aws_s3_bucket.user_content.id

  rule {
    id     = "DeleteOldVersions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.s3_noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ============================================================================
# API GATEWAY (OPTIONAL)
# ============================================================================

# REST API for authenticated backend services
resource "aws_api_gateway_rest_api" "main" {
  count       = var.create_api_gateway ? 1 : 0
  name        = "${var.project_name}-api-${var.environment}"
  description = "Backend API for enterprise authentication demo with Cognito authorization"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

# Cognito User Pool authorizer for API Gateway
resource "aws_api_gateway_authorizer" "cognito" {
  count                            = var.create_api_gateway ? 1 : 0
  name                            = "CognitoAuthorizer"
  rest_api_id                     = aws_api_gateway_rest_api.main[0].id
  type                            = "COGNITO_USER_POOLS"
  provider_arns                   = [aws_cognito_user_pool.main.arn]
  identity_source                 = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 300
}

# API Gateway resource for user operations
resource "aws_api_gateway_resource" "user" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main[0].id
  parent_id   = aws_api_gateway_rest_api.main[0].root_resource_id
  path_part   = "user"
}

# GET method for user profile information
resource "aws_api_gateway_method" "user_get" {
  count             = var.create_api_gateway ? 1 : 0
  rest_api_id       = aws_api_gateway_rest_api.main[0].id
  resource_id       = aws_api_gateway_resource.user[0].id
  http_method       = "GET"
  authorization     = "COGNITO_USER_POOLS"
  authorizer_id     = aws_api_gateway_authorizer.cognito[0].id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

# Mock integration for demonstration (replace with Lambda in production)
resource "aws_api_gateway_integration" "user_get" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main[0].id
  resource_id = aws_api_gateway_resource.user[0].id
  http_method = aws_api_gateway_method.user_get[0].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

# Success response configuration
resource "aws_api_gateway_method_response" "user_get" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main[0].id
  resource_id = aws_api_gateway_resource.user[0].id
  http_method = aws_api_gateway_method.user_get[0].http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Integration response with user context
resource "aws_api_gateway_integration_response" "user_get" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main[0].id
  resource_id = aws_api_gateway_resource.user[0].id
  http_method = aws_api_gateway_method.user_get[0].http_method
  status_code = aws_api_gateway_method_response.user_get[0].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  response_templates = {
    "application/json" = jsonencode({
      message   = "Hello from authenticated API"
      user      = "$context.authorizer.claims.email"
      sub       = "$context.authorizer.claims.sub"
      timestamp = "$context.requestTime"
      region    = "${data.aws_region.current.name}"
    })
  }
}

# Deploy API to stage
resource "aws_api_gateway_deployment" "main" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.main[0].id
  stage_name  = var.environment

  depends_on = [
    aws_api_gateway_method.user_get,
    aws_api_gateway_integration.user_get,
    aws_api_gateway_integration_response.user_get
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# AWS AMPLIFY APPLICATION (OPTIONAL)
# ============================================================================

# Amplify application for hosting the React frontend
resource "aws_amplify_app" "main" {
  count                     = var.create_amplify_app ? 1 : 0
  name                     = "${var.project_name}-app-${var.environment}"
  repository               = var.github_repository != "" ? var.github_repository : null
  access_token             = var.github_access_token != "" ? var.github_access_token : null
  enable_branch_auto_build = var.github_repository != "" ? true : false

  # Build specification for React applications
  build_spec = yamlencode({
    version = 1
    frontend = {
      phases = {
        preBuild = {
          commands = [
            "npm ci"
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
  })

  # Environment variables for React application
  environment_variables = {
    REACT_APP_AWS_REGION           = data.aws_region.current.name
    REACT_APP_USER_POOL_ID         = aws_cognito_user_pool.main.id
    REACT_APP_USER_POOL_CLIENT_ID  = aws_cognito_user_pool_client.web_client.id
    REACT_APP_IDENTITY_POOL_ID     = aws_cognito_identity_pool.main.id
    REACT_APP_COGNITO_DOMAIN       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
    REACT_APP_API_ENDPOINT         = var.create_api_gateway ? "https://${aws_api_gateway_rest_api.main[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.environment}" : ""
    REACT_APP_S3_BUCKET           = aws_s3_bucket.user_content.bucket
  }

  # Custom rules for SPA routing
  custom_rule {
    source = "/<*>"
    status = "404-200"
    target = "/index.html"
  }

  tags = local.common_tags
}

# Main branch configuration for Amplify
resource "aws_amplify_branch" "main" {
  count       = var.create_amplify_app ? 1 : 0
  app_id      = aws_amplify_app.main[0].id
  branch_name = var.amplify_branch_name

  enable_auto_build = var.github_repository != "" ? true : false
  stage            = var.environment == "prod" ? "PRODUCTION" : "DEVELOPMENT"

  tags = local.common_tags
}

# ============================================================================
# CLOUDWATCH MONITORING
# ============================================================================

# CloudWatch Log Group for Cognito triggers and monitoring
resource "aws_cloudwatch_log_group" "cognito_monitoring" {
  name              = "/aws/cognito/${var.project_name}-${var.environment}"
  retention_in_days = var.cloudwatch_retention_days

  tags = local.common_tags
}

# CloudWatch Dashboard for authentication monitoring
resource "aws_cloudwatch_dashboard" "monitoring" {
  count          = var.create_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "${var.project_name}-auth-monitoring-${var.environment}"

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
            ["AWS/Cognito", "SignInSuccesses", "UserPool", aws_cognito_user_pool.main.id, "UserPoolClient", aws_cognito_user_pool_client.web_client.id],
            [".", "SignInThrottles", ".", ".", ".", "."],
            [".", "SignUpSuccesses", ".", ".", ".", "."],
            [".", "TokenRefreshSuccesses", ".", ".", ".", "."]
          ]
          view   = "timeSeries"
          stacked = false
          region = data.aws_region.current.name
          title  = "Cognito Authentication Metrics"
          period = 300
          stat   = "Sum"
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
            ["AWS/Cognito", "CompromisedCredentialsRisk", "UserPool", aws_cognito_user_pool.main.id],
            [".", "AccountTakeoverRisk", ".", "."],
            [".", "OverrideBlockedIpAction", ".", "."]
          ]
          view   = "timeSeries"
          stacked = false
          region = data.aws_region.current.name
          title  = "Cognito Security Metrics"
          period = 300
          stat   = "Sum"
        }
      }
    ]
  })

  depends_on = [aws_cognito_user_pool.main]
}