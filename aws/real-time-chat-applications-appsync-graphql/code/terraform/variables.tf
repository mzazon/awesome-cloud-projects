# Core Configuration Variables
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
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

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "realtime-chat"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# AppSync Configuration
variable "appsync_api_name" {
  description = "Name for the AppSync GraphQL API"
  type        = string
  default     = ""
}

variable "enable_appsync_logging" {
  description = "Enable CloudWatch logging for AppSync API"
  type        = bool
  default     = true
}

variable "appsync_log_level" {
  description = "Log level for AppSync API (ALL, ERROR, NONE)"
  type        = string
  default     = "ERROR"
  
  validation {
    condition     = contains(["ALL", "ERROR", "NONE"], var.appsync_log_level)
    error_message = "AppSync log level must be one of: ALL, ERROR, NONE."
  }
}

variable "enable_enhanced_metrics" {
  description = "Enable enhanced metrics for AppSync API"
  type        = bool
  default     = true
}

# Cognito Configuration
variable "cognito_user_pool_name" {
  description = "Name for the Cognito User Pool"
  type        = string
  default     = ""
}

variable "password_minimum_length" {
  description = "Minimum length for user passwords"
  type        = number
  default     = 8
  
  validation {
    condition     = var.password_minimum_length >= 6 && var.password_minimum_length <= 99
    error_message = "Password minimum length must be between 6 and 99."
  }
}

variable "enable_advanced_security" {
  description = "Enable advanced security features for Cognito User Pool"
  type        = bool
  default     = false
}

variable "auto_verified_attributes" {
  description = "List of attributes to be auto-verified"
  type        = list(string)
  default     = ["email"]
  
  validation {
    condition = alltrue([
      for attr in var.auto_verified_attributes : contains(["email", "phone_number"], attr)
    ])
    error_message = "Auto verified attributes must be a list containing only 'email' and/or 'phone_number'."
  }
}

# DynamoDB Configuration
variable "dynamodb_billing_mode" {
  description = "Billing mode for DynamoDB tables (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "dynamodb_read_capacity" {
  description = "Read capacity units for DynamoDB tables (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "Write capacity units for DynamoDB tables (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

variable "enable_dynamodb_streams" {
  description = "Enable DynamoDB streams for real-time data capture"
  type        = bool
  default     = true
}

variable "dynamodb_stream_view_type" {
  description = "Stream view type for DynamoDB streams (KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES)"
  type        = string
  default     = "NEW_AND_OLD_IMAGES"
  
  validation {
    condition = contains([
      "KEYS_ONLY", 
      "NEW_IMAGE", 
      "OLD_IMAGE", 
      "NEW_AND_OLD_IMAGES"
    ], var.dynamodb_stream_view_type)
    error_message = "DynamoDB stream view type must be one of: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB tables"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for DynamoDB tables"
  type        = bool
  default     = false
}

# Table Names
variable "messages_table_name" {
  description = "Name for the messages DynamoDB table"
  type        = string
  default     = ""
}

variable "conversations_table_name" {
  description = "Name for the conversations DynamoDB table"
  type        = string
  default     = ""
}

variable "users_table_name" {
  description = "Name for the users DynamoDB table"
  type        = string
  default     = ""
}

# Security and Compliance
variable "enable_ssl_only_access" {
  description = "Enforce SSL-only access to resources"
  type        = bool
  default     = true
}

variable "trusted_ip_ranges" {
  description = "List of trusted IP ranges for additional security (CIDR notation)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for cidr in var.trusted_ip_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "All trusted IP ranges must be valid CIDR blocks."
  }
}

# Lambda Configuration (for future extensions)
variable "enable_lambda_authorizer" {
  description = "Enable Lambda authorizer for additional authentication logic"
  type        = bool
  default     = false
}

# Monitoring and Alerts
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "alarm_email_endpoints" {
  description = "List of email addresses to receive CloudWatch alarm notifications"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.alarm_email_endpoints : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All alarm email endpoints must be valid email addresses."
  }
}

# Cost Optimization
variable "enable_cost_tags" {
  description = "Enable detailed cost allocation tags"
  type        = bool
  default     = true
}

# Development and Testing
variable "create_test_users" {
  description = "Create test users in Cognito for development/testing"
  type        = bool
  default     = false
}

variable "test_user_count" {
  description = "Number of test users to create (only if create_test_users is true)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.test_user_count >= 1 && var.test_user_count <= 10
    error_message = "Test user count must be between 1 and 10."
  }
}