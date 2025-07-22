# ============================================================================
# TERRAFORM VARIABLES FOR ENTERPRISE AUTHENTICATION
# ============================================================================
# This file defines all configurable variables for the enterprise
# authentication solution with AWS Amplify and external identity providers.
#
# Variables are organized by functional area:
# - Project Configuration
# - Authentication Settings
# - Identity Provider Configuration
# - Security Settings
# - Application Settings
# - Monitoring and Logging
# ============================================================================

# ============================================================================
# PROJECT CONFIGURATION
# ============================================================================

variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
  default     = "enterprise-auth"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod) for resource naming and configuration"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format of region-direction-number (e.g., us-east-1)."
  }
}

# ============================================================================
# AUTHENTICATION SETTINGS
# ============================================================================

variable "user_pool_domain_prefix" {
  description = "Custom prefix for Cognito User Pool domain. Leave empty for auto-generated"
  type        = string
  default     = ""

  validation {
    condition = var.user_pool_domain_prefix == "" || can(regex("^[a-z0-9-]+$", var.user_pool_domain_prefix))
    error_message = "Domain prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "callback_urls" {
  description = "List of allowed callback URLs for OAuth flow"
  type        = list(string)
  default     = ["http://localhost:3000/auth/callback", "https://localhost:3000/auth/callback"]

  validation {
    condition     = length(var.callback_urls) > 0
    error_message = "At least one callback URL must be provided."
  }
}

variable "logout_urls" {
  description = "List of allowed logout URLs for OAuth flow"
  type        = list(string)
  default     = ["http://localhost:3000/auth/logout", "https://localhost:3000/auth/logout"]

  validation {
    condition     = length(var.logout_urls) > 0
    error_message = "At least one logout URL must be provided."
  }
}

variable "allow_unauthenticated_identities" {
  description = "Whether to allow unauthenticated access to the identity pool"
  type        = bool
  default     = false
}

# ============================================================================
# PASSWORD POLICY SETTINGS
# ============================================================================

variable "password_minimum_length" {
  description = "Minimum length for user passwords"
  type        = number
  default     = 8

  validation {
    condition     = var.password_minimum_length >= 8 && var.password_minimum_length <= 99
    error_message = "Password minimum length must be between 8 and 99 characters."
  }
}

variable "password_require_lowercase" {
  description = "Whether passwords must contain lowercase letters"
  type        = bool
  default     = true
}

variable "password_require_uppercase" {
  description = "Whether passwords must contain uppercase letters"
  type        = bool
  default     = true
}

variable "password_require_numbers" {
  description = "Whether passwords must contain numbers"
  type        = bool
  default     = true
}

variable "password_require_symbols" {
  description = "Whether passwords must contain symbols"
  type        = bool
  default     = true
}

variable "temporary_password_validity_days" {
  description = "Number of days temporary passwords are valid"
  type        = number
  default     = 7

  validation {
    condition     = var.temporary_password_validity_days >= 1 && var.temporary_password_validity_days <= 365
    error_message = "Temporary password validity must be between 1 and 365 days."
  }
}

# ============================================================================
# MULTI-FACTOR AUTHENTICATION
# ============================================================================

variable "mfa_configuration" {
  description = "MFA configuration for user pool (OFF, OPTIONAL, REQUIRED)"
  type        = string
  default     = "OPTIONAL"

  validation {
    condition     = contains(["OFF", "OPTIONAL", "REQUIRED"], var.mfa_configuration)
    error_message = "MFA configuration must be one of: OFF, OPTIONAL, REQUIRED."
  }
}

variable "enabled_mfas" {
  description = "List of enabled MFA methods"
  type        = list(string)
  default     = ["SOFTWARE_TOKEN_MFA"]

  validation {
    condition = alltrue([
      for mfa in var.enabled_mfas :
      contains(["SOFTWARE_TOKEN_MFA", "SMS_MFA"], mfa)
    ])
    error_message = "Enabled MFAs must be one or more of: SOFTWARE_TOKEN_MFA, SMS_MFA."
  }
}

# ============================================================================
# SAML IDENTITY PROVIDER CONFIGURATION
# ============================================================================

variable "enable_saml_provider" {
  description = "Whether to enable SAML 2.0 identity provider integration"
  type        = bool
  default     = false
}

variable "saml_provider_name" {
  description = "Name for the SAML identity provider (e.g., 'EnterpriseAD', 'CompanySSO')"
  type        = string
  default     = "EnterpriseAD"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.saml_provider_name))
    error_message = "SAML provider name must start with a letter and contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "saml_metadata_url" {
  description = "SAML metadata URL from your identity provider (required if enable_saml_provider is true)"
  type        = string
  default     = ""

  validation {
    condition = var.enable_saml_provider == false || (
      var.enable_saml_provider == true && 
      var.saml_metadata_url != "" && 
      can(regex("^https://", var.saml_metadata_url))
    )
    error_message = "SAML metadata URL must be a valid HTTPS URL when SAML provider is enabled."
  }
}

# ============================================================================
# OIDC IDENTITY PROVIDER CONFIGURATION
# ============================================================================

variable "enable_oidc_provider" {
  description = "Whether to enable OpenID Connect identity provider integration"
  type        = bool
  default     = false
}

variable "oidc_provider_url" {
  description = "OIDC provider URL/issuer (required if enable_oidc_provider is true)"
  type        = string
  default     = ""

  validation {
    condition = var.enable_oidc_provider == false || (
      var.enable_oidc_provider == true && 
      var.oidc_provider_url != "" && 
      can(regex("^https://", var.oidc_provider_url))
    )
    error_message = "OIDC provider URL must be a valid HTTPS URL when OIDC provider is enabled."
  }
}

variable "oidc_client_id" {
  description = "OIDC client ID from your identity provider (required if enable_oidc_provider is true)"
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition = var.enable_oidc_provider == false || (
      var.enable_oidc_provider == true && 
      var.oidc_client_id != ""
    )
    error_message = "OIDC client ID is required when OIDC provider is enabled."
  }
}

variable "oidc_client_secret" {
  description = "OIDC client secret from your identity provider (required if enable_oidc_provider is true)"
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition = var.enable_oidc_provider == false || (
      var.enable_oidc_provider == true && 
      var.oidc_client_secret != ""
    )
    error_message = "OIDC client secret is required when OIDC provider is enabled."
  }
}

# ============================================================================
# SECURITY SETTINGS
# ============================================================================

variable "advanced_security_mode" {
  description = "Advanced security mode for Cognito (OFF, AUDIT, ENFORCED)"
  type        = string
  default     = "AUDIT"

  validation {
    condition     = contains(["OFF", "AUDIT", "ENFORCED"], var.advanced_security_mode)
    error_message = "Advanced security mode must be one of: OFF, AUDIT, ENFORCED."
  }
}

variable "admin_create_user_only" {
  description = "Whether only administrators can create users"
  type        = bool
  default     = false
}

variable "read_attributes" {
  description = "List of user attributes that applications can read"
  type        = list(string)
  default = [
    "email",
    "email_verified",
    "given_name",
    "family_name",
    "custom:department"
  ]
}

variable "write_attributes" {
  description = "List of user attributes that applications can write"
  type        = list(string)
  default = [
    "email",
    "given_name",
    "family_name"
  ]
}

# ============================================================================
# TOKEN VALIDITY SETTINGS
# ============================================================================

variable "refresh_token_validity" {
  description = "Refresh token validity in days"
  type        = number
  default     = 30

  validation {
    condition     = var.refresh_token_validity >= 1 && var.refresh_token_validity <= 3650
    error_message = "Refresh token validity must be between 1 and 3650 days."
  }
}

variable "access_token_validity" {
  description = "Access token validity in minutes"
  type        = number
  default     = 60

  validation {
    condition     = var.access_token_validity >= 5 && var.access_token_validity <= 1440
    error_message = "Access token validity must be between 5 and 1440 minutes."
  }
}

variable "id_token_validity" {
  description = "ID token validity in minutes"
  type        = number
  default     = 60

  validation {
    condition     = var.id_token_validity >= 5 && var.id_token_validity <= 1440
    error_message = "ID token validity must be between 5 and 1440 minutes."
  }
}

# ============================================================================
# S3 STORAGE SETTINGS
# ============================================================================

variable "s3_noncurrent_version_expiration_days" {
  description = "Number of days to retain non-current versions in S3"
  type        = number
  default     = 30

  validation {
    condition     = var.s3_noncurrent_version_expiration_days >= 1 && var.s3_noncurrent_version_expiration_days <= 365
    error_message = "S3 non-current version expiration must be between 1 and 365 days."
  }
}

# ============================================================================
# API GATEWAY SETTINGS
# ============================================================================

variable "create_api_gateway" {
  description = "Whether to create an API Gateway for demonstration purposes"
  type        = bool
  default     = true
}

# ============================================================================
# AWS AMPLIFY SETTINGS
# ============================================================================

variable "create_amplify_app" {
  description = "Whether to create an AWS Amplify application for hosting"
  type        = bool
  default     = false
}

variable "github_repository" {
  description = "GitHub repository URL for Amplify app (optional)"
  type        = string
  default     = ""

  validation {
    condition = var.github_repository == "" || can(regex("^https://github.com/", var.github_repository))
    error_message = "GitHub repository must be a valid GitHub HTTPS URL or empty."
  }
}

variable "github_access_token" {
  description = "GitHub personal access token for Amplify app (required if github_repository is provided)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "amplify_branch_name" {
  description = "Git branch name for Amplify app deployment"
  type        = string
  default     = "main"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9/_-]*$", var.amplify_branch_name))
    error_message = "Branch name must start with a letter and contain only valid Git branch characters."
  }
}

# ============================================================================
# MONITORING AND LOGGING
# ============================================================================

variable "cloudwatch_retention_days" {
  description = "CloudWatch log group retention period in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_retention_days)
    error_message = "CloudWatch retention days must be a valid value."
  }
}

variable "create_cloudwatch_dashboard" {
  description = "Whether to create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

# ============================================================================
# FEATURE FLAGS
# ============================================================================

variable "enable_cognito_triggers" {
  description = "Whether to enable Cognito Lambda triggers for custom authentication logic"
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Whether to enable AWS WAF for API Gateway protection"
  type        = bool
  default     = false
}

variable "enable_custom_domain" {
  description = "Whether to use a custom domain for Cognito hosted UI"
  type        = bool
  default     = false
}

variable "custom_domain_name" {
  description = "Custom domain name for Cognito hosted UI (required if enable_custom_domain is true)"
  type        = string
  default     = ""

  validation {
    condition = var.enable_custom_domain == false || (
      var.enable_custom_domain == true && 
      var.custom_domain_name != "" && 
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", var.custom_domain_name))
    )
    error_message = "Custom domain name must be a valid domain when custom domain is enabled."
  }
}

variable "certificate_arn" {
  description = "SSL certificate ARN for custom domain (required if enable_custom_domain is true)"
  type        = string
  default     = ""

  validation {
    condition = var.enable_custom_domain == false || (
      var.enable_custom_domain == true && 
      var.certificate_arn != "" && 
      can(regex("^arn:aws:acm:", var.certificate_arn))
    )
    error_message = "Certificate ARN must be a valid ACM certificate ARN when custom domain is enabled."
  }
}

# ============================================================================
# COST OPTIMIZATION
# ============================================================================

variable "enable_cost_allocation_tags" {
  description = "Whether to enable detailed cost allocation tags"
  type        = bool
  default     = true
}

variable "cost_center" {
  description = "Cost center for billing allocation"
  type        = string
  default     = ""
}

variable "business_unit" {
  description = "Business unit for resource organization"
  type        = string
  default     = ""
}

# ============================================================================
# COMPLIANCE AND GOVERNANCE
# ============================================================================

variable "compliance_framework" {
  description = "Compliance framework requirements (SOC2, HIPAA, PCI, etc.)"
  type        = list(string)
  default     = []
}

variable "data_classification" {
  description = "Data classification level (public, internal, confidential, restricted)"
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "Data classification must be one of: public, internal, confidential, restricted."
  }
}

variable "retention_policy" {
  description = "Data retention policy in days for compliance"
  type        = number
  default     = 2555  # 7 years

  validation {
    condition     = var.retention_policy >= 30
    error_message = "Retention policy must be at least 30 days."
  }
}