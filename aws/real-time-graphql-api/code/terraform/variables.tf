# ==============================================================================
# Variables for AWS AppSync GraphQL API Infrastructure
# ==============================================================================
# This file defines all configurable parameters for the AppSync infrastructure.
# Customize these values to match your specific requirements and environment.
# ==============================================================================

# ------------------------------------------------------------------------------
# General Configuration
# ------------------------------------------------------------------------------

variable "api_name" {
  description = "Name of the AppSync GraphQL API"
  type        = string
  default     = "blog-api"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.api_name))
    error_message = "API name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "table_name" {
  description = "Name of the DynamoDB table for blog posts"
  type        = string
  default     = "BlogPosts"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.table_name))
    error_message = "Table name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "user_pool_name" {
  description = "Name of the Cognito User Pool"
  type        = string
  default     = "BlogUserPool"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_\\s]+$", var.user_pool_name))
    error_message = "User pool name must contain only alphanumeric characters, hyphens, underscores, and spaces."
  }
}

variable "tags" {
  description = "Resource tags for cost tracking and management"
  type        = map(string)
  default = {
    Environment = "development"
    Project     = "graphql-blog-api"
    CreatedBy   = "terraform"
  }
}

# ------------------------------------------------------------------------------
# DynamoDB Configuration
# ------------------------------------------------------------------------------

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode: PROVISIONED or PAY_PER_REQUEST"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only for PROVISIONED billing mode)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity > 0
    error_message = "DynamoDB read capacity must be greater than 0."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only for PROVISIONED billing mode)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity > 0
    error_message = "DynamoDB write capacity must be greater than 0."
  }
}

variable "dynamodb_gsi_read_capacity" {
  description = "DynamoDB Global Secondary Index read capacity units (only for PROVISIONED billing mode)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_gsi_read_capacity > 0
    error_message = "DynamoDB GSI read capacity must be greater than 0."
  }
}

variable "dynamodb_gsi_write_capacity" {
  description = "DynamoDB Global Secondary Index write capacity units (only for PROVISIONED billing mode)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_gsi_write_capacity > 0
    error_message = "DynamoDB GSI write capacity must be greater than 0."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable server-side encryption for DynamoDB table"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# AppSync Configuration
# ------------------------------------------------------------------------------

variable "enable_api_key_auth" {
  description = "Enable API key authentication as additional auth method"
  type        = bool
  default     = true
}

variable "api_key_expires" {
  description = "API key expiration time (Unix timestamp)"
  type        = string
  default     = null
  
  validation {
    condition = var.api_key_expires == null || can(tonumber(var.api_key_expires))
    error_message = "API key expiration must be a valid Unix timestamp or null."
  }
}

variable "log_level" {
  description = "AppSync log level: NONE, ERROR, ALL"
  type        = string
  default     = "ERROR"
  
  validation {
    condition     = contains(["NONE", "ERROR", "ALL"], var.log_level)
    error_message = "Log level must be one of: NONE, ERROR, ALL."
  }
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for AppSync API"
  type        = bool
  default     = false
}

# ------------------------------------------------------------------------------
# Test User Configuration
# ------------------------------------------------------------------------------

variable "create_test_user" {
  description = "Create a test user for authentication testing"
  type        = bool
  default     = false
}

variable "test_username" {
  description = "Test user email address"
  type        = string
  default     = "testuser@example.com"
  
  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.test_username))
    error_message = "Test username must be a valid email address."
  }
}

variable "test_password" {
  description = "Test user password (must meet Cognito password policy)"
  type        = string
  default     = "BlogUser123!"
  sensitive   = true
  
  validation {
    condition     = length(var.test_password) >= 8
    error_message = "Test password must be at least 8 characters long."
  }
}

# ------------------------------------------------------------------------------
# Advanced Configuration
# ------------------------------------------------------------------------------

variable "enable_caching" {
  description = "Enable AppSync caching"
  type        = bool
  default     = false
}

variable "cache_ttl" {
  description = "Cache TTL in seconds (only applies if caching is enabled)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.cache_ttl > 0
    error_message = "Cache TTL must be greater than 0."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = false
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# ------------------------------------------------------------------------------
# Resource Limits and Quotas
# ------------------------------------------------------------------------------

variable "max_batch_size" {
  description = "Maximum batch size for GraphQL operations"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_batch_size > 0 && var.max_batch_size <= 100
    error_message = "Max batch size must be between 1 and 100."
  }
}

variable "query_depth_limit" {
  description = "Maximum query depth limit for GraphQL operations"
  type        = number
  default     = 10
  
  validation {
    condition     = var.query_depth_limit > 0 && var.query_depth_limit <= 20
    error_message = "Query depth limit must be between 1 and 20."
  }
}

variable "introspection_enabled" {
  description = "Enable GraphQL introspection (disable in production)"
  type        = bool
  default     = true
}