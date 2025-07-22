# variables.tf - Input variables for DynamoDB Global Tables infrastructure
# This file defines all configurable parameters for the multi-region deployment

# Environment and project configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "Environment must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "globaltables-demo"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

# Region configuration for multi-region deployment
variable "primary_region" {
  description = "Primary AWS region for Global Tables deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.primary_region))
    error_message = "Primary region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for Global Tables replica"
  type        = string
  default     = "eu-west-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.secondary_region))
    error_message = "Secondary region must be a valid AWS region format (e.g., eu-west-1)."
  }
}

variable "tertiary_region" {
  description = "Tertiary AWS region for Global Tables replica"
  type        = string
  default     = "ap-northeast-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.tertiary_region))
    error_message = "Tertiary region must be a valid AWS region format (e.g., ap-northeast-1)."
  }
}

# DynamoDB table configuration
variable "table_name_prefix" {
  description = "Prefix for DynamoDB table name (random suffix will be added)"
  type        = string
  default     = "GlobalUserProfiles"
  
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_-]*$", var.table_name_prefix))
    error_message = "Table name prefix must start with a letter and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.billing_mode)
    error_message = "Billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "read_capacity" {
  description = "Read capacity units for provisioned billing mode"
  type        = number
  default     = 5
  
  validation {
    condition     = var.read_capacity >= 1 && var.read_capacity <= 40000
    error_message = "Read capacity must be between 1 and 40000."
  }
}

variable "write_capacity" {
  description = "Write capacity units for provisioned billing mode"
  type        = number
  default     = 5
  
  validation {
    condition     = var.write_capacity >= 1 && var.write_capacity <= 40000
    error_message = "Write capacity must be between 1 and 40000."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for the DynamoDB table"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for the DynamoDB table"
  type        = bool
  default     = false
}

# Lambda configuration
variable "lambda_function_name_prefix" {
  description = "Prefix for Lambda function name (random suffix will be added)"
  type        = string
  default     = "GlobalTableProcessor"
  
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_-]*$", var.lambda_function_name_prefix))
    error_message = "Lambda function name prefix must start with a letter and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "lambda_runtime" {
  description = "Python runtime version for Lambda functions"
  type        = string
  default     = "python3.11"
  
  validation {
    condition     = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

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
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# CloudWatch monitoring configuration
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "replication_latency_threshold" {
  description = "Replication latency threshold in milliseconds for CloudWatch alarms"
  type        = number
  default     = 10000
  
  validation {
    condition     = var.replication_latency_threshold >= 1000 && var.replication_latency_threshold <= 300000
    error_message = "Replication latency threshold must be between 1000 and 300000 milliseconds."
  }
}

variable "user_errors_threshold" {
  description = "User errors threshold for CloudWatch alarms"
  type        = number
  default     = 5
  
  validation {
    condition     = var.user_errors_threshold >= 1 && var.user_errors_threshold <= 100
    error_message = "User errors threshold must be between 1 and 100."
  }
}

variable "enable_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

# Global Secondary Index configuration
variable "enable_email_gsi" {
  description = "Enable Global Secondary Index for email-based queries"
  type        = bool
  default     = true
}

variable "email_gsi_name" {
  description = "Name for the email Global Secondary Index"
  type        = string
  default     = "EmailIndex"
  
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_-]*$", var.email_gsi_name))
    error_message = "GSI name must start with a letter and contain only letters, numbers, underscores, and hyphens."
  }
}

# SNS notification configuration
variable "enable_sns_notifications" {
  description = "Enable SNS notifications for CloudWatch alarms"
  type        = bool
  default     = false
}

variable "sns_email_endpoint" {
  description = "Email address for SNS notifications (required if enable_sns_notifications is true)"
  type        = string
  default     = ""
  
  validation {
    condition = var.enable_sns_notifications == false || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sns_email_endpoint))
    error_message = "SNS email endpoint must be a valid email address when SNS notifications are enabled."
  }
}

# Resource tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = alltrue([for k, v in var.additional_tags : can(regex("^[\\w\\s\\.\\-_:/@]+$", k)) && can(regex("^[\\w\\s\\.\\-_:/@]*$", v))])
    error_message = "Tag keys and values must contain only alphanumeric characters, spaces, and the following characters: . - _ : / @"
  }
}

# Security configuration
variable "enable_kms_encryption" {
  description = "Enable KMS encryption for DynamoDB table"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}