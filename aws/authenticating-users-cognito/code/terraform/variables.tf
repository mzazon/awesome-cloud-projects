# Variables for Cognito User Pool Authentication Infrastructure
# This file defines all configurable parameters for the Cognito authentication solution

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "ecommerce-auth"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# User Pool Configuration Variables
variable "user_pool_name" {
  description = "Name for the Cognito User Pool"
  type        = string
  default     = null
}

variable "password_minimum_length" {
  description = "Minimum password length for user accounts"
  type        = number
  default     = 12
  
  validation {
    condition     = var.password_minimum_length >= 8 && var.password_minimum_length <= 99
    error_message = "Password minimum length must be between 8 and 99 characters."
  }
}

variable "password_require_uppercase" {
  description = "Whether to require uppercase letters in passwords"
  type        = bool
  default     = true
}

variable "password_require_lowercase" {
  description = "Whether to require lowercase letters in passwords"
  type        = bool
  default     = true
}

variable "password_require_numbers" {
  description = "Whether to require numbers in passwords"
  type        = bool
  default     = true
}

variable "password_require_symbols" {
  description = "Whether to require symbols in passwords"
  type        = bool
  default     = true
}

variable "temporary_password_validity_days" {
  description = "Number of days temporary passwords are valid"
  type        = number
  default     = 1
  
  validation {
    condition     = var.temporary_password_validity_days >= 1 && var.temporary_password_validity_days <= 365
    error_message = "Temporary password validity must be between 1 and 365 days."
  }
}

variable "mfa_configuration" {
  description = "MFA configuration for the user pool (OFF, ON, OPTIONAL)"
  type        = string
  default     = "OPTIONAL"
  
  validation {
    condition     = contains(["OFF", "ON", "OPTIONAL"], var.mfa_configuration)
    error_message = "MFA configuration must be one of: OFF, ON, OPTIONAL."
  }
}

variable "unused_account_validity_days" {
  description = "Number of days after which unused accounts expire"
  type        = number
  default     = 7
  
  validation {
    condition     = var.unused_account_validity_days >= 1 && var.unused_account_validity_days <= 365
    error_message = "Unused account validity must be between 1 and 365 days."
  }
}

# User Pool Client Configuration Variables
variable "client_name" {
  description = "Name for the Cognito User Pool Client"
  type        = string
  default     = null
}

variable "generate_secret" {
  description = "Whether to generate a client secret for the user pool client"
  type        = bool
  default     = true
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

variable "callback_urls" {
  description = "List of allowed callback URLs for OAuth flows"
  type        = list(string)
  default     = ["https://localhost:3000/callback"]
}

variable "logout_urls" {
  description = "List of allowed logout URLs for OAuth flows"
  type        = list(string)
  default     = ["https://localhost:3000/logout"]
}

# Hosted UI Configuration Variables
variable "domain_prefix" {
  description = "Domain prefix for Cognito hosted UI"
  type        = string
  default     = null
}

# Email Configuration Variables
variable "email_sending_account" {
  description = "Email sending account type (COGNITO_DEFAULT or DEVELOPER)"
  type        = string
  default     = "COGNITO_DEFAULT"
  
  validation {
    condition     = contains(["COGNITO_DEFAULT", "DEVELOPER"], var.email_sending_account)
    error_message = "Email sending account must be either COGNITO_DEFAULT or DEVELOPER."
  }
}

variable "ses_source_arn" {
  description = "SES source ARN for sending emails (required if email_sending_account is DEVELOPER)"
  type        = string
  default     = null
}

variable "reply_to_email_address" {
  description = "Reply-to email address for Cognito emails"
  type        = string
  default     = null
}

# Advanced Security Configuration Variables
variable "advanced_security_mode" {
  description = "Advanced security mode (OFF, AUDIT, ENFORCED)"
  type        = string
  default     = "ENFORCED"
  
  validation {
    condition     = contains(["OFF", "AUDIT", "ENFORCED"], var.advanced_security_mode)
    error_message = "Advanced security mode must be one of: OFF, AUDIT, ENFORCED."
  }
}

# Test User Configuration Variables
variable "create_test_users" {
  description = "Whether to create test users for validation"
  type        = bool
  default     = false
}

variable "admin_email" {
  description = "Email address for admin test user"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "Admin email must be a valid email address."
  }
}

variable "customer_email" {
  description = "Email address for customer test user"
  type        = string
  default     = "customer@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.customer_email))
    error_message = "Customer email must be a valid email address."
  }
}

variable "test_user_temporary_password" {
  description = "Temporary password for test users"
  type        = string
  default     = "TempPass123!"
  sensitive   = true
}

# Social Identity Provider Configuration Variables
variable "enable_google_identity_provider" {
  description = "Whether to enable Google as an identity provider"
  type        = bool
  default     = false
}

variable "google_client_id" {
  description = "Google OAuth client ID"
  type        = string
  default     = null
  sensitive   = true
}

variable "google_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  default     = null
  sensitive   = true
}