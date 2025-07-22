# ==============================================================================
# Variables for Mobile Backend Services with AWS Amplify
# 
# This file defines all the input variables for the Terraform configuration,
# providing customization options for the mobile backend infrastructure.
# ==============================================================================

# ==============================================================================
# Project Configuration Variables
# ==============================================================================

variable "project_name" {
  description = "Name of the project, used as a prefix for resource naming"
  type        = string
  default     = "mobile-backend"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# ==============================================================================
# AWS Configuration Variables
# ==============================================================================

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

# ==============================================================================
# Amazon Cognito Configuration Variables
# ==============================================================================

variable "cognito_password_minimum_length" {
  description = "Minimum length for user passwords in Cognito User Pool"
  type        = number
  default     = 8

  validation {
    condition     = var.cognito_password_minimum_length >= 6 && var.cognito_password_minimum_length <= 99
    error_message = "Password minimum length must be between 6 and 99 characters."
  }
}

variable "cognito_mfa_configuration" {
  description = "Multi-factor authentication configuration for Cognito User Pool"
  type        = string
  default     = "OPTIONAL"

  validation {
    condition     = contains(["OFF", "ON", "OPTIONAL"], var.cognito_mfa_configuration)
    error_message = "MFA configuration must be one of: OFF, ON, OPTIONAL."
  }
}

variable "cognito_access_token_validity" {
  description = "Access token validity period in minutes"
  type        = number
  default     = 60

  validation {
    condition     = var.cognito_access_token_validity >= 5 && var.cognito_access_token_validity <= 1440
    error_message = "Access token validity must be between 5 minutes and 24 hours (1440 minutes)."
  }
}

variable "cognito_id_token_validity" {
  description = "ID token validity period in minutes"
  type        = number
  default     = 60

  validation {
    condition     = var.cognito_id_token_validity >= 5 && var.cognito_id_token_validity <= 1440
    error_message = "ID token validity must be between 5 minutes and 24 hours (1440 minutes)."
  }
}

variable "cognito_refresh_token_validity" {
  description = "Refresh token validity period in days"
  type        = number
  default     = 30

  validation {
    condition     = var.cognito_refresh_token_validity >= 1 && var.cognito_refresh_token_validity <= 3650
    error_message = "Refresh token validity must be between 1 and 3650 days."
  }
}

variable "cognito_callback_urls" {
  description = "List of allowed callback URLs for OAuth2 flows"
  type        = list(string)
  default     = ["myapp://callback"]

  validation {
    condition = alltrue([
      for url in var.cognito_callback_urls : can(regex("^(https?://|[a-zA-Z][a-zA-Z0-9+.-]*://)", url))
    ])
    error_message = "All callback URLs must be valid URLs with a scheme (http://, https://, or custom scheme)."
  }
}

variable "cognito_logout_urls" {
  description = "List of allowed logout URLs for OAuth2 flows"
  type        = list(string)
  default     = ["myapp://logout"]

  validation {
    condition = alltrue([
      for url in var.cognito_logout_urls : can(regex("^(https?://|[a-zA-Z][a-zA-Z0-9+.-]*://)", url))
    ])
    error_message = "All logout URLs must be valid URLs with a scheme (http://, https://, or custom scheme)."
  }
}

# ==============================================================================
# DynamoDB Configuration Variables
# ==============================================================================

variable "dynamodb_billing_mode" {
  description = "Billing mode for DynamoDB tables (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "dynamodb_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB tables"
  type        = bool
  default     = true
}

variable "dynamodb_server_side_encryption" {
  description = "Enable server-side encryption for DynamoDB tables"
  type        = bool
  default     = true
}

variable "dynamodb_read_capacity" {
  description = "Read capacity units for DynamoDB tables (only used with PROVISIONED billing mode)"
  type        = number
  default     = 5

  validation {
    condition     = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "Write capacity units for DynamoDB tables (only used with PROVISIONED billing mode)"
  type        = number
  default     = 5

  validation {
    condition     = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

# ==============================================================================
# AWS AppSync Configuration Variables
# ==============================================================================

variable "appsync_authentication_type" {
  description = "Authentication type for AppSync API"
  type        = string
  default     = "AMAZON_COGNITO_USER_POOLS"

  validation {
    condition = contains([
      "API_KEY",
      "AWS_IAM",
      "AMAZON_COGNITO_USER_POOLS",
      "OPENID_CONNECT"
    ], var.appsync_authentication_type)
    error_message = "AppSync authentication type must be one of: API_KEY, AWS_IAM, AMAZON_COGNITO_USER_POOLS, OPENID_CONNECT."
  }
}

variable "appsync_field_log_level" {
  description = "Field log level for AppSync API"
  type        = string
  default     = "ERROR"

  validation {
    condition     = contains(["NONE", "ERROR", "ALL"], var.appsync_field_log_level)
    error_message = "AppSync field log level must be one of: NONE, ERROR, ALL."
  }
}

variable "appsync_xray_enabled" {
  description = "Enable X-Ray tracing for AppSync API"
  type        = bool
  default     = false
}

# ==============================================================================
# S3 Configuration Variables
# ==============================================================================

variable "s3_versioning_enabled" {
  description = "Enable versioning for the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_encryption_algorithm" {
  description = "Server-side encryption algorithm for S3 bucket"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.s3_encryption_algorithm)
    error_message = "S3 encryption algorithm must be either AES256 or aws:kms."
  }
}

variable "s3_cors_allowed_origins" {
  description = "List of allowed origins for S3 CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "s3_cors_allowed_methods" {
  description = "List of allowed methods for S3 CORS configuration"
  type        = list(string)
  default     = ["GET", "PUT", "POST", "DELETE", "HEAD"]

  validation {
    condition = alltrue([
      for method in var.s3_cors_allowed_methods : 
      contains(["GET", "PUT", "POST", "DELETE", "HEAD"], method)
    ])
    error_message = "S3 CORS allowed methods must be from: GET, PUT, POST, DELETE, HEAD."
  }
}

variable "s3_cors_max_age_seconds" {
  description = "Maximum age in seconds for S3 CORS configuration"
  type        = number
  default     = 3000

  validation {
    condition     = var.s3_cors_max_age_seconds >= 0 && var.s3_cors_max_age_seconds <= 86400
    error_message = "S3 CORS max age must be between 0 and 86400 seconds."
  }
}

# ==============================================================================
# AWS Lambda Configuration Variables
# ==============================================================================

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "nodejs18.x"

  validation {
    condition = contains([
      "nodejs18.x",
      "nodejs20.x",
      "python3.9",
      "python3.10",
      "python3.11",
      "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 128

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# ==============================================================================
# Amazon Pinpoint Configuration Variables
# ==============================================================================

variable "pinpoint_campaign_hook_enabled" {
  description = "Enable campaign hook for Pinpoint application"
  type        = bool
  default     = false
}

variable "pinpoint_cloudwatch_metrics_enabled" {
  description = "Enable CloudWatch metrics for Pinpoint application"
  type        = bool
  default     = true
}

# ==============================================================================
# Monitoring and Logging Configuration Variables
# ==============================================================================

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid retention period."
  }
}

variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "dashboard_widget_period" {
  description = "Period for CloudWatch dashboard widgets in seconds"
  type        = number
  default     = 300

  validation {
    condition = contains([60, 300, 900, 3600, 21600, 86400], var.dashboard_widget_period)
    error_message = "Dashboard widget period must be one of: 60, 300, 900, 3600, 21600, 86400 seconds."
  }
}

# ==============================================================================
# Security Configuration Variables
# ==============================================================================

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

variable "force_destroy_s3_bucket" {
  description = "Allow force destruction of S3 bucket even if it contains objects"
  type        = bool
  default     = false
}

# ==============================================================================
# Cost Optimization Variables
# ==============================================================================

variable "enable_s3_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering for cost optimization"
  type        = bool
  default     = false
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle configuration for cost optimization"
  type        = bool
  default     = false
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days after which objects transition to cheaper storage class"
  type        = number
  default     = 30

  validation {
    condition     = var.s3_lifecycle_transition_days >= 1
    error_message = "S3 lifecycle transition days must be at least 1."
  }
}

# ==============================================================================
# Additional Resource Tags
# ==============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key, value in var.additional_tags : can(regex("^[a-zA-Z0-9+\\-=._:/@]*$", key))
    ])
    error_message = "Tag keys must contain only valid characters."
  }
}