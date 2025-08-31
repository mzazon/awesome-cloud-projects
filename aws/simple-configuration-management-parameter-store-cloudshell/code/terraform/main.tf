# ===============================================
# Simple Configuration Management with Parameter Store and CloudShell
# ===============================================
# 
# This Terraform configuration demonstrates centralized configuration 
# management using AWS Systems Manager Parameter Store. It creates 
# a hierarchical structure of parameters including standard strings,
# secure strings, and string lists for comprehensive configuration
# management patterns.
#
# Resources created:
# - SSM Parameters (String, SecureString, StringList types)
# - IAM role for CloudShell Parameter Store access (optional)
# - KMS key for parameter encryption (optional)
# ===============================================

# Local values for resource naming and organization
locals {
  # Generate a random suffix for unique resource naming
  random_suffix = random_string.suffix.result
  
  # Application namespace for parameter organization
  app_name      = "${var.application_name}-${local.random_suffix}"
  param_prefix  = "/${local.app_name}"
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Application   = var.application_name
    Environment   = var.environment
    ManagedBy     = "Terraform"
    Recipe        = "simple-configuration-management-parameter-store-cloudshell"
    AppName       = local.app_name
  })
}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# ===============================================
# KMS Key for Parameter Store Encryption (Optional)
# ===============================================

# KMS key for encrypting SecureString parameters
resource "aws_kms_key" "parameter_store" {
  count = var.create_kms_key ? 1 : 0

  description             = "KMS key for Parameter Store encryption for ${local.app_name}"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "key-policy-parameter-store-${local.random_suffix}"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Systems Manager Service"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
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
    Name = "${local.app_name}-parameter-store-key"
  })
}

# KMS key alias for easier reference
resource "aws_kms_alias" "parameter_store" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${local.app_name}-parameter-store"
  target_key_id = aws_kms_key.parameter_store[0].key_id
}

# ===============================================
# Standard Configuration Parameters
# ===============================================

# Database connection URL parameter (non-sensitive)
resource "aws_ssm_parameter" "database_url" {
  name        = "${local.param_prefix}/database/url"
  description = "Database connection URL for ${local.app_name}"
  type        = "String"
  value       = var.database_url

  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-database-url"
    Category    = "Database"
    Sensitive   = "false"
    ParameterType = "String"
  })
}

# Environment configuration parameter
resource "aws_ssm_parameter" "environment" {
  name        = "${local.param_prefix}/config/environment"
  description = "Application environment setting"
  type        = "String"
  value       = var.environment

  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-environment"
    Category    = "Configuration"
    Sensitive   = "false"
    ParameterType = "String"
  })
}

# Feature flag parameter for debug mode
resource "aws_ssm_parameter" "debug_mode" {
  name        = "${local.param_prefix}/features/debug-mode"
  description = "Debug mode feature flag"
  type        = "String"
  value       = var.debug_mode ? "true" : "false"

  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-debug-mode"
    Category    = "FeatureFlag"
    Sensitive   = "false"
    ParameterType = "String"
  })
}

# Application port configuration
resource "aws_ssm_parameter" "app_port" {
  name        = "${local.param_prefix}/config/port"
  description = "Application port configuration"
  type        = "String"
  value       = tostring(var.application_port)

  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-app-port"
    Category    = "Configuration"
    Sensitive   = "false"
    ParameterType = "String"
  })
}

# ===============================================
# Secure String Parameters for Sensitive Data
# ===============================================

# Third-party API key (encrypted)
resource "aws_ssm_parameter" "api_key" {
  name        = "${local.param_prefix}/api/third-party-key"
  description = "Third-party API key for ${local.app_name}"
  type        = "SecureString"
  value       = var.third_party_api_key
  key_id      = var.create_kms_key ? aws_kms_key.parameter_store[0].arn : "alias/aws/ssm"

  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-api-key"
    Category    = "API"
    Sensitive   = "true"
    ParameterType = "SecureString"
  })
}

# Database password (encrypted)
resource "aws_ssm_parameter" "database_password" {
  name        = "${local.param_prefix}/database/password"
  description = "Database password for ${local.app_name}"
  type        = "SecureString"
  value       = var.database_password
  key_id      = var.create_kms_key ? aws_kms_key.parameter_store[0].arn : "alias/aws/ssm"

  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-database-password"
    Category    = "Database" 
    Sensitive   = "true"
    ParameterType = "SecureString"
  })
}

# JWT secret key (encrypted)
resource "aws_ssm_parameter" "jwt_secret" {
  name        = "${local.param_prefix}/auth/jwt-secret"
  description = "JWT secret key for ${local.app_name}"
  type        = "SecureString"
  value       = var.jwt_secret_key
  key_id      = var.create_kms_key ? aws_kms_key.parameter_store[0].arn : "alias/aws/ssm"

  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-jwt-secret"
    Category    = "Authentication"
    Sensitive   = "true"
    ParameterType = "SecureString"
  })
}

# ===============================================
# StringList Parameters for Multiple Values
# ===============================================

# CORS allowed origins list
resource "aws_ssm_parameter" "allowed_origins" {
  name        = "${local.param_prefix}/api/allowed-origins"
  description = "CORS allowed origins for ${local.app_name}"
  type        = "StringList"
  value       = join(",", var.allowed_origins)

  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-allowed-origins"
    Category    = "API"
    Sensitive   = "false"
    ParameterType = "StringList"
  })
}

# Supported deployment regions list
resource "aws_ssm_parameter" "deployment_regions" {
  name        = "${local.param_prefix}/deployment/regions"
  description = "Supported deployment regions"
  type        = "StringList"
  value       = join(",", var.deployment_regions)

  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-deployment-regions"
    Category    = "Deployment"
    Sensitive   = "false"
    ParameterType = "StringList"
  })
}

# Feature flags list
resource "aws_ssm_parameter" "feature_flags" {
  name        = "${local.param_prefix}/features/enabled-features"
  description = "List of enabled feature flags"
  type        = "StringList"
  value       = join(",", var.enabled_features)

  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-feature-flags"
    Category    = "FeatureFlag"
    Sensitive   = "false"
    ParameterType = "StringList"
  })
}

# ===============================================
# IAM Role for CloudShell Parameter Store Access (Optional)
# ===============================================

# IAM role for CloudShell users to access Parameter Store
resource "aws_iam_role" "cloudshell_parameter_access" {
  count = var.create_cloudshell_role ? 1 : 0

  name               = "${local.app_name}-cloudshell-parameter-access"
  description        = "Role for CloudShell access to Parameter Store for ${local.app_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.app_name}-cloudshell-role"
  })
}

# IAM policy for Parameter Store access
resource "aws_iam_role_policy" "parameter_store_access" {
  count = var.create_cloudshell_role ? 1 : 0

  name = "${local.app_name}-parameter-store-policy"
  role = aws_iam_role.cloudshell_parameter_access[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:DescribeParameters",
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:GetParameterHistory"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${local.param_prefix}",
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${local.param_prefix}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.create_kms_key ? [aws_kms_key.parameter_store[0].arn] : ["arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"]
      }
    ]
  })
}

# ===============================================
# Data Sources
# ===============================================

# Current AWS caller identity
data "aws_caller_identity" "current" {}

# Current AWS region
data "aws_region" "current" {}