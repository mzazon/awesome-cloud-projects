# Variables for AWS AppSync real-time data synchronization infrastructure

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
  description = "Name of the project - used for resource naming"
  type        = string
  default     = "realtime-tasks"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB table read capacity units"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1 && var.dynamodb_read_capacity <= 1000
    error_message = "Read capacity must be between 1 and 1000."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB table write capacity units"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1 && var.dynamodb_write_capacity <= 1000
    error_message = "Write capacity must be between 1 and 1000."
  }
}

variable "gsi_read_capacity" {
  description = "Global Secondary Index read capacity units"
  type        = number
  default     = 5
  
  validation {
    condition     = var.gsi_read_capacity >= 1 && var.gsi_read_capacity <= 1000
    error_message = "GSI read capacity must be between 1 and 1000."
  }
}

variable "gsi_write_capacity" {
  description = "Global Secondary Index write capacity units"
  type        = number
  default     = 5
  
  validation {
    condition     = var.gsi_write_capacity >= 1 && var.gsi_write_capacity <= 1000
    error_message = "GSI write capacity must be between 1 and 1000."
  }
}

variable "api_key_expires_in_days" {
  description = "Number of days until the API key expires"
  type        = number
  default     = 30
  
  validation {
    condition     = var.api_key_expires_in_days >= 1 && var.api_key_expires_in_days <= 365
    error_message = "API key expiration must be between 1 and 365 days."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for AppSync"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "authentication_type" {
  description = "AppSync authentication type"
  type        = string
  default     = "API_KEY"
  
  validation {
    condition = contains([
      "API_KEY", "AWS_IAM", "AMAZON_COGNITO_USER_POOLS", "OPENID_CONNECT"
    ], var.authentication_type)
    error_message = "Authentication type must be one of: API_KEY, AWS_IAM, AMAZON_COGNITO_USER_POOLS, OPENID_CONNECT."
  }
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for AppSync"
  type        = bool
  default     = false
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}