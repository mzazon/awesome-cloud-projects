# Main Terraform Configuration for Cognito User Pool Authentication
# This file creates a comprehensive Cognito User Pool with security features, MFA, and user groups

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values for consistent naming and configuration
locals {
  random_suffix    = random_id.suffix.hex
  user_pool_name   = var.user_pool_name != null ? var.user_pool_name : "${var.project_name}-users-${local.random_suffix}"
  client_name      = var.client_name != null ? var.client_name : "${var.project_name}-web-client-${local.random_suffix}"
  domain_prefix    = var.domain_prefix != null ? var.domain_prefix : "${var.project_name}-auth-${local.random_suffix}"
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "user-authentication-cognito-user-pools"
  }
}

# IAM Role for Cognito to send SMS messages through SNS
resource "aws_iam_role" "cognito_sns_role" {
  name = "${var.project_name}-cognito-sns-role-${local.random_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cognito-idp.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "cognito-${aws_cognito_user_pool.main.id}"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM Policy for Cognito SNS role to publish SMS messages
resource "aws_iam_role_policy" "cognito_sns_policy" {
  name = "${var.project_name}-cognito-sns-policy-${local.random_suffix}"
  role = aws_iam_role.cognito_sns_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })
}

# Main Cognito User Pool with comprehensive security configuration
resource "aws_cognito_user_pool" "main" {
  name = local.user_pool_name

  # Username and alias configuration
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy configuration
  password_policy {
    minimum_length                   = var.password_minimum_length
    require_uppercase                = var.password_require_uppercase
    require_lowercase                = var.password_require_lowercase
    require_numbers                  = var.password_require_numbers
    require_symbols                  = var.password_require_symbols
    temporary_password_validity_days = var.temporary_password_validity_days
  }

  # Multi-factor authentication configuration
  mfa_configuration = var.mfa_configuration
  software_token_mfa_configuration {
    enabled = true
  }
  
  sms_configuration {
    external_id    = "cognito-${aws_cognito_user_pool.main.id}"
    sns_caller_arn = aws_iam_role.cognito_sns_role.arn
    sns_region     = data.aws_region.current.name
  }

  # Device tracking configuration for enhanced security
  device_configuration {
    challenge_required_on_new_device      = true
    device_only_remembered_on_user_prompt = false
  }

  # Admin user creation settings
  admin_create_user_config {
    allow_admin_create_user_only = false
    unused_account_validity_days = var.unused_account_validity_days

    invite_message_template {
      email_subject = "Welcome to ${var.project_name} - Your Account Details"
      email_message = "Welcome to ${var.project_name}! Your username is {username} and temporary password is {####}. Please sign in and change your password."
      sms_message   = "Welcome to ${var.project_name}! Username: {username} Temporary password: {####}"
    }
  }

  # Email verification configuration
  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  # Verification message templates
  verification_message_template {
    default_email_option  = "CONFIRM_WITH_LINK"
    email_subject         = "Welcome to ${var.project_name} - Verify Your Email"
    email_message         = "Thank you for signing up for ${var.project_name}. Please click the link to verify your email: {##Verify Email##}"
    email_subject_by_link = "Welcome to ${var.project_name} - Verify Your Email"
    email_message_by_link = "Thank you for signing up for ${var.project_name}. Please click the link to verify your email: {##Verify Email##}"
  }

  # Email configuration
  dynamic "email_configuration" {
    for_each = var.email_sending_account == "DEVELOPER" ? [1] : []
    content {
      email_sending_account   = var.email_sending_account
      source_arn             = var.ses_source_arn
      reply_to_email_address = var.reply_to_email_address
    }
  }

  # Schema for custom attributes
  schema {
    name                = "customer_tier"
    attribute_data_type = "String"
    required            = false
    mutable             = true
    
    string_attribute_constraints {
      min_length = 1
      max_length = 20
    }
  }

  schema {
    name                = "subscription_status"
    attribute_data_type = "String"
    required            = false
    mutable             = true
    
    string_attribute_constraints {
      min_length = 1
      max_length = 50
    }
  }

  schema {
    name                = "last_login"
    attribute_data_type = "DateTime"
    required            = false
    mutable             = true
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy.cognito_sns_policy]
}

# Configure advanced security features for the user pool
resource "aws_cognito_user_pool_add_ons" "main" {
  user_pool_id = aws_cognito_user_pool.main.id
  
  advanced_security_mode = var.advanced_security_mode
}

# Risk configuration for compromised credentials and account takeover protection
resource "aws_cognito_risk_configuration" "main" {
  user_pool_id = aws_cognito_user_pool.main.id

  # Compromised credentials risk configuration
  compromised_credentials_risk_configuration {
    event_filter = ["SIGN_IN", "PASSWORD_CHANGE", "SIGN_UP"]
    
    actions {
      event_action = "BLOCK"
    }
  }

  # Account takeover risk configuration
  account_takeover_risk_configuration {
    notify_configuration {
      block_email {
        html_body = "<p>We detected suspicious activity on your ${var.project_name} account and have blocked this sign-in attempt.</p>"
        subject   = "Security Alert - Suspicious Activity Blocked"
        text_body = "We detected suspicious activity on your ${var.project_name} account and have blocked this sign-in attempt."
      }
      
      mfa_email {
        html_body = "<p>We detected suspicious activity on your ${var.project_name} account. Please complete MFA to continue.</p>"
        subject   = "Security Alert - MFA Required"
        text_body = "We detected suspicious activity on your ${var.project_name} account. Please complete MFA to continue."
      }
      
      no_action_email {
        html_body = "<p>We detected unusual activity on your ${var.project_name} account. Please review your recent sign-ins.</p>"
        subject   = "Security Alert - Unusual Activity Detected"
        text_body = "We detected unusual activity on your ${var.project_name} account. Please review your recent sign-ins."
      }
      
      from                = var.reply_to_email_address != null ? var.reply_to_email_address : "noreply@${var.project_name}.com"
      reply_to            = var.reply_to_email_address != null ? var.reply_to_email_address : "support@${var.project_name}.com"
      source_arn          = var.ses_source_arn
    }

    actions {
      low_action {
        event_action = "NO_ACTION"
        notify       = true
      }
      
      medium_action {
        event_action = "MFA_IF_CONFIGURED"
        notify       = true
      }
      
      high_action {
        event_action = "BLOCK"
        notify       = true
      }
    }
  }

  depends_on = [aws_cognito_user_pool_add_ons.main]
}

# User Pool Client for web and mobile applications
resource "aws_cognito_user_pool_client" "main" {
  name         = local.client_name
  user_pool_id = aws_cognito_user_pool.main.id

  # Client secret configuration
  generate_secret = var.generate_secret

  # Token validity configuration
  refresh_token_validity = var.refresh_token_validity
  access_token_validity  = var.access_token_validity
  id_token_validity      = var.id_token_validity
  
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # Attribute permissions
  read_attributes  = ["email", "email_verified", "name", "family_name", "given_name", "phone_number", "custom:customer_tier", "custom:subscription_status"]
  write_attributes = ["email", "name", "family_name", "given_name", "phone_number", "custom:customer_tier", "custom:subscription_status"]

  # Authentication flows
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  # OAuth configuration
  supported_identity_providers = ["COGNITO"]
  callback_urls               = var.callback_urls
  logout_urls                = var.logout_urls
  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true

  # Security features
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation      = true
  auth_session_validity        = 3

  depends_on = [aws_cognito_user_pool.main]
}

# Hosted UI Domain for authentication
resource "aws_cognito_user_pool_domain" "main" {
  domain       = local.domain_prefix
  user_pool_id = aws_cognito_user_pool.main.id

  depends_on = [aws_cognito_user_pool.main]
}

# User Groups for role-based access control
resource "aws_cognito_user_group" "administrators" {
  name         = "Administrators"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Administrator users with full access"
  precedence   = 1

  depends_on = [aws_cognito_user_pool.main]
}

resource "aws_cognito_user_group" "customers" {
  name         = "Customers"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Regular customer users"
  precedence   = 10

  depends_on = [aws_cognito_user_pool.main]
}

resource "aws_cognito_user_group" "premium_customers" {
  name         = "PremiumCustomers"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Premium customer users with enhanced features"
  precedence   = 5

  depends_on = [aws_cognito_user_pool.main]
}

# Google Identity Provider (optional)
resource "aws_cognito_identity_provider" "google" {
  count = var.enable_google_identity_provider && var.google_client_id != null && var.google_client_secret != null ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "openid email profile"
  }

  attribute_mapping = {
    email       = "email"
    given_name  = "given_name"
    family_name = "family_name"
    name        = "name"
  }

  depends_on = [aws_cognito_user_pool.main]
}

# Update user pool client to include Google as identity provider
resource "aws_cognito_user_pool_client" "main_with_google" {
  count = var.enable_google_identity_provider && var.google_client_id != null && var.google_client_secret != null ? 1 : 0

  name         = local.client_name
  user_pool_id = aws_cognito_user_pool.main.id

  # Client secret configuration
  generate_secret = var.generate_secret

  # Token validity configuration
  refresh_token_validity = var.refresh_token_validity
  access_token_validity  = var.access_token_validity
  id_token_validity      = var.id_token_validity
  
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # Attribute permissions
  read_attributes  = ["email", "email_verified", "name", "family_name", "given_name", "phone_number", "custom:customer_tier", "custom:subscription_status"]
  write_attributes = ["email", "name", "family_name", "given_name", "phone_number", "custom:customer_tier", "custom:subscription_status"]

  # Authentication flows
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  # OAuth configuration with Google
  supported_identity_providers = ["COGNITO", "Google"]
  callback_urls               = var.callback_urls
  logout_urls                = var.logout_urls
  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true

  # Security features
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation      = true
  auth_session_validity        = 3

  depends_on = [aws_cognito_identity_provider.google[0]]
}

# Test Users (optional - for development/testing purposes)
resource "aws_cognito_user" "admin" {
  count        = var.create_test_users ? 1 : 0
  user_pool_id = aws_cognito_user_pool.main.id
  username     = var.admin_email
  
  attributes = {
    email          = var.admin_email
    name           = "Admin User"
    given_name     = "Admin"
    family_name    = "User"
    email_verified = "true"
  }

  temporary_password = var.test_user_temporary_password
  message_action     = "SUPPRESS"

  depends_on = [aws_cognito_user_pool.main]
}

resource "aws_cognito_user_in_group" "admin" {
  count        = var.create_test_users ? 1 : 0
  user_pool_id = aws_cognito_user_pool.main.id
  group_name   = aws_cognito_user_group.administrators.name
  username     = aws_cognito_user.admin[0].username

  depends_on = [aws_cognito_user.admin[0], aws_cognito_user_group.administrators]
}

resource "aws_cognito_user" "customer" {
  count        = var.create_test_users ? 1 : 0
  user_pool_id = aws_cognito_user_pool.main.id
  username     = var.customer_email
  
  attributes = {
    email          = var.customer_email
    name           = "Customer User"
    given_name     = "Customer"
    family_name    = "User"
    email_verified = "true"
  }

  temporary_password = var.test_user_temporary_password
  message_action     = "SUPPRESS"

  depends_on = [aws_cognito_user_pool.main]
}

resource "aws_cognito_user_in_group" "customer" {
  count        = var.create_test_users ? 1 : 0
  user_pool_id = aws_cognito_user_pool.main.id
  group_name   = aws_cognito_user_group.customers.name
  username     = aws_cognito_user.customer[0].username

  depends_on = [aws_cognito_user.customer[0], aws_cognito_user_group.customers]
}