# ================================================================================
# Variables for Enterprise Identity Federation with Bedrock AgentCore
# ================================================================================
# This file defines all configurable parameters for the enterprise identity
# federation infrastructure, enabling customization for different environments
# and organizational requirements.

# ================================================================================
# Environment and Naming Variables
# ================================================================================

variable "environment" {
  description = "Environment name (e.g., development, staging, production)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "pool_name" {
  description = "Base name for the Cognito User Pool (suffix will be auto-generated)"
  type        = string
  default     = "enterprise-ai-agents"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.pool_name))
    error_message = "Pool name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "agentcore_identity_name" {
  description = "Base name for the Bedrock AgentCore workload identity"
  type        = string
  default     = "enterprise-agent"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.agentcore_identity_name))
    error_message = "AgentCore identity name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# ================================================================================
# SAML Identity Provider Configuration
# ================================================================================

variable "idp_metadata_url" {
  description = "SAML metadata URL for the enterprise identity provider"
  type        = string
  default     = "https://your-enterprise-idp.com/metadata"
  
  validation {
    condition     = can(regex("^https://", var.idp_metadata_url))
    error_message = "IDP metadata URL must be a valid HTTPS URL."
  }
}

variable "idp_sso_url" {
  description = "SAML SSO redirect binding URI for the enterprise identity provider"
  type        = string
  default     = "https://your-enterprise-idp.com/sso"
  
  validation {
    condition     = can(regex("^https://", var.idp_sso_url))
    error_message = "IDP SSO URL must be a valid HTTPS URL."
  }
}

variable "idp_slo_url" {
  description = "SAML SLO redirect binding URI for the enterprise identity provider"
  type        = string
  default     = "https://your-enterprise-idp.com/slo"
  
  validation {
    condition     = can(regex("^https://", var.idp_slo_url))
    error_message = "IDP SLO URL must be a valid HTTPS URL."
  }
}

# ================================================================================
# OAuth Configuration Variables
# ================================================================================

variable "oauth_callback_urls" {
  description = "List of OAuth callback URLs for the Cognito User Pool App Client"
  type        = list(string)
  default = [
    "https://your-app.company.com/oauth/callback",
    "https://localhost:8080/callback"
  ]
  
  validation {
    condition = alltrue([
      for url in var.oauth_callback_urls : can(regex("^https://", url))
    ])
    error_message = "All OAuth callback URLs must be valid HTTPS URLs."
  }
}

variable "oauth_logout_urls" {
  description = "List of OAuth logout URLs for the Cognito User Pool App Client"
  type        = list(string)
  default = [
    "https://your-app.company.com/logout",
    "https://localhost:8080/logout"
  ]
  
  validation {
    condition = alltrue([
      for url in var.oauth_logout_urls : can(regex("^https://", url))
    ])
    error_message = "All OAuth logout URLs must be valid HTTPS URLs."
  }
}

# ================================================================================
# Security and Authorization Variables
# ================================================================================

variable "authorized_domains" {
  description = "List of email domains authorized for AI agent management"
  type        = list(string)
  default     = ["@company.com", "@enterprise.org"]
  
  validation {
    condition = alltrue([
      for domain in var.authorized_domains : can(regex("^@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", domain))
    ])
    error_message = "Authorized domains must be in format @domain.com."
  }
}

variable "enable_advanced_security" {
  description = "Enable advanced security features for Cognito User Pool"
  type        = bool
  default     = true
}

variable "mfa_configuration" {
  description = "Multi-factor authentication configuration for Cognito User Pool"
  type        = string
  default     = "OPTIONAL"
  
  validation {
    condition     = contains(["OFF", "ON", "OPTIONAL"], var.mfa_configuration)
    error_message = "MFA configuration must be one of: OFF, ON, OPTIONAL."
  }
}

# ================================================================================
# Password Policy Variables
# ================================================================================

variable "password_minimum_length" {
  description = "Minimum password length for Cognito User Pool"
  type        = number
  default     = 12
  
  validation {
    condition     = var.password_minimum_length >= 8 && var.password_minimum_length <= 256
    error_message = "Password minimum length must be between 8 and 256 characters."
  }
}

variable "password_require_uppercase" {
  description = "Require uppercase letters in passwords"
  type        = bool
  default     = true
}

variable "password_require_lowercase" {
  description = "Require lowercase letters in passwords"
  type        = bool
  default     = true
}

variable "password_require_numbers" {
  description = "Require numbers in passwords"
  type        = bool
  default     = true
}

variable "password_require_symbols" {
  description = "Require symbols in passwords"
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

# ================================================================================
# Token Validity Variables
# ================================================================================

variable "access_token_validity" {
  description = "Access token validity in hours"
  type        = number
  default     = 1
  
  validation {
    condition     = var.access_token_validity >= 1 && var.access_token_validity <= 24
    error_message = "Access token validity must be between 1 and 24 hours."
  }
}

variable "id_token_validity" {
  description = "ID token validity in hours"
  type        = number
  default     = 1
  
  validation {
    condition     = var.id_token_validity >= 1 && var.id_token_validity <= 24
    error_message = "ID token validity must be between 1 and 24 hours."
  }
}

variable "refresh_token_validity" {
  description = "Refresh token validity in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.refresh_token_validity >= 1 && var.refresh_token_validity <= 3650
    error_message = "Refresh token validity must be between 1 and 3650 days."
  }
}

# ================================================================================
# Lambda Configuration Variables
# ================================================================================

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.11"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

# ================================================================================
# Logging and Monitoring Variables
# ================================================================================

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail for auditing authentication events"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

# ================================================================================
# S3 Configuration Variables
# ================================================================================

variable "cloudtrail_bucket_force_destroy" {
  description = "Allow force destruction of CloudTrail S3 bucket (for testing only)"
  type        = bool
  default     = false
}

variable "s3_encryption_algorithm" {
  description = "S3 server-side encryption algorithm"
  type        = string
  default     = "AES256"
  
  validation {
    condition     = contains(["AES256", "aws:kms"], var.s3_encryption_algorithm)
    error_message = "S3 encryption algorithm must be either AES256 or aws:kms."
  }
}

# ================================================================================
# Department Permission Configuration
# ================================================================================

variable "engineering_max_agents" {
  description = "Maximum number of AI agents for engineering department"
  type        = number
  default     = 10
  
  validation {
    condition     = var.engineering_max_agents >= 1 && var.engineering_max_agents <= 100
    error_message = "Engineering max agents must be between 1 and 100."
  }
}

variable "security_max_agents" {
  description = "Maximum number of AI agents for security department"
  type        = number
  default     = 5
  
  validation {
    condition     = var.security_max_agents >= 1 && var.security_max_agents <= 100
    error_message = "Security max agents must be between 1 and 100."
  }
}

variable "general_max_agents" {
  description = "Maximum number of AI agents for general department"
  type        = number
  default     = 2
  
  validation {
    condition     = var.general_max_agents >= 1 && var.general_max_agents <= 100
    error_message = "General max agents must be between 1 and 100."
  }
}

# ================================================================================
# Enterprise Integration Variables
# ================================================================================

variable "enable_saml_federation" {
  description = "Enable SAML federation with enterprise identity provider"
  type        = bool
  default     = true
}

variable "enable_oauth_flows" {
  description = "Enable OAuth 2.0 flows for third-party integrations"
  type        = bool
  default     = true
}

variable "custom_domain_name" {
  description = "Custom domain name for Cognito hosted UI (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.custom_domain_name == "" || can(regex("^[a-zA-Z0-9.-]+$", var.custom_domain_name))
    error_message = "Custom domain name must be a valid domain or empty string."
  }
}

# ================================================================================
# Tagging Variables
# ================================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9+\\-=._:/@]+$", k)) && can(regex("^[a-zA-Z0-9+\\-=._:/@\\s]*$", v))
    ])
    error_message = "Tag keys and values must contain only valid characters."
  }
}

variable "cost_center" {
  description = "Cost center for billing purposes"
  type        = string
  default     = ""
}

variable "business_unit" {
  description = "Business unit responsible for the resources"
  type        = string
  default     = ""
}

variable "contact_email" {
  description = "Contact email for the resource owner"
  type        = string
  default     = ""
  
  validation {
    condition = var.contact_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.contact_email))
    error_message = "Contact email must be a valid email address or empty string."
  }
}