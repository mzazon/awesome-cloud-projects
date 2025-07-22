# AWS Amplify DataStore - Terraform Variables
# This file defines all input variables for the offline-first mobile application
# infrastructure deployment with AWS Amplify DataStore.

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "offline-tasks"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

variable "amplify_app_name" {
  description = "Name of the Amplify application"
  type        = string
  default     = ""
}

variable "amplify_repository_url" {
  description = "Git repository URL for Amplify app (optional)"
  type        = string
  default     = ""
}

variable "amplify_access_token" {
  description = "Git access token for Amplify app (optional, use environment variable)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cognito_user_pool_name" {
  description = "Name of the Cognito User Pool"
  type        = string
  default     = ""
}

variable "cognito_password_policy" {
  description = "Password policy configuration for Cognito User Pool"
  type = object({
    minimum_length                   = number
    require_lowercase               = bool
    require_uppercase               = bool
    require_numbers                 = bool
    require_symbols                 = bool
    temporary_password_validity_days = number
  })
  default = {
    minimum_length                   = 8
    require_lowercase               = true
    require_uppercase               = true
    require_numbers                 = true
    require_symbols                 = true
    temporary_password_validity_days = 7
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1 && var.dynamodb_read_capacity <= 40000
    error_message = "DynamoDB read capacity must be between 1 and 40000."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1 && var.dynamodb_write_capacity <= 40000
    error_message = "DynamoDB write capacity must be between 1 and 40000."
  }
}

variable "appsync_authentication_type" {
  description = "AppSync authentication type"
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

variable "appsync_log_level" {
  description = "AppSync CloudWatch log level"
  type        = string
  default     = "ERROR"
  
  validation {
    condition     = contains(["NONE", "ERROR", "ALL"], var.appsync_log_level)
    error_message = "AppSync log level must be one of: NONE, ERROR, ALL."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable Point in Time Recovery for DynamoDB tables"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for DynamoDB tables"
  type        = bool
  default     = false
}

variable "enable_server_side_encryption" {
  description = "Enable server-side encryption for DynamoDB tables"
  type        = bool
  default     = true
}

variable "conflict_resolution_strategy" {
  description = "Conflict resolution strategy for DataStore (OPTIMISTIC_CONCURRENCY or AUTOMERGE)"
  type        = string
  default     = "AUTOMERGE"
  
  validation {
    condition     = contains(["OPTIMISTIC_CONCURRENCY", "AUTOMERGE"], var.conflict_resolution_strategy)
    error_message = "Conflict resolution strategy must be either OPTIMISTIC_CONCURRENCY or AUTOMERGE."
  }
}

variable "enable_datastore" {
  description = "Enable DataStore for offline-first functionality"
  type        = bool
  default     = true
}

variable "datastore_sync_expressions" {
  description = "DataStore selective sync expressions"
  type        = list(string)
  default     = []
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "offline-first-mobile-app"
    Environment = "dev"
    CreatedBy   = "terraform"
    Purpose     = "amplify-datastore-demo"
  }
}

variable "create_amplify_app" {
  description = "Whether to create an Amplify app (set to false if using existing app)"
  type        = bool
  default     = true
}

variable "create_custom_domain" {
  description = "Whether to create a custom domain for the Amplify app"
  type        = bool
  default     = false
}

variable "custom_domain_name" {
  description = "Custom domain name for the Amplify app"
  type        = string
  default     = ""
}

variable "enable_auto_build" {
  description = "Enable auto build for Amplify app"
  type        = bool
  default     = true
}

variable "enable_pull_request_preview" {
  description = "Enable pull request preview for Amplify app"
  type        = bool
  default     = false
}

variable "amplify_framework" {
  description = "Framework for the Amplify app"
  type        = string
  default     = "React Native"
  
  validation {
    condition = contains([
      "React Native",
      "React",
      "Vue",
      "Angular",
      "Next.js",
      "Gatsby",
      "Nuxt",
      "Hugo"
    ], var.amplify_framework)
    error_message = "Amplify framework must be one of the supported frameworks."
  }
}

variable "notifications_email" {
  description = "Email address for notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notifications_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notifications_email))
    error_message = "Notifications email must be a valid email address or empty."
  }
}