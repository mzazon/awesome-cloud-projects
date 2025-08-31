# Variables for Email List Management System
# This file defines all configurable parameters for the serverless email list management infrastructure

#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

variable "sender_email" {
  description = "The verified email address to use as the sender for newsletters and notifications. This email must be verified in Amazon SES before deployment."
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sender_email))
    error_message = "The sender_email must be a valid email address format."
  }
}

#------------------------------------------------------------------------------
# Optional Configuration Variables
#------------------------------------------------------------------------------

variable "environment" {
  description = "Environment name for resource tagging and naming (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "test", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, test, prod."
  }
}

variable "lambda_runtime" {
  description = "Runtime version for Lambda functions. Use Python 3.12 for latest features and performance."
  type        = string
  default     = "python3.12"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs for Lambda functions"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

#------------------------------------------------------------------------------
# Lambda Function URL Configuration
#------------------------------------------------------------------------------

variable "enable_function_urls" {
  description = "Enable Lambda Function URLs for direct HTTP access to functions. When enabled, functions can be invoked directly via HTTPS without API Gateway."
  type        = bool
  default     = false
}

variable "allowed_origins" {
  description = "List of allowed origins for CORS when Function URLs are enabled. Use ['*'] for all origins (not recommended for production)."
  type        = list(string)
  default     = ["https://yourdomain.com"]
  
  validation {
    condition     = length(var.allowed_origins) > 0
    error_message = "At least one allowed origin must be specified."
  }
}

#------------------------------------------------------------------------------
# DynamoDB Configuration
#------------------------------------------------------------------------------

variable "enable_point_in_time_recovery" {
  description = "Enable Point-in-Time Recovery for DynamoDB table. Provides continuous backups for the last 35 days."
  type        = bool
  default     = true
}

variable "enable_dynamodb_encryption" {
  description = "Enable server-side encryption for DynamoDB table using AWS managed keys"
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# SES Configuration
#------------------------------------------------------------------------------

variable "ses_configuration_set" {
  description = "Optional SES Configuration Set name for tracking email delivery metrics and handling bounces/complaints"
  type        = string
  default     = null
}

#------------------------------------------------------------------------------
# Lambda Function Configuration
#------------------------------------------------------------------------------

variable "subscribe_function_config" {
  description = "Configuration settings for the subscribe Lambda function"
  type = object({
    timeout     = number
    memory_size = number
  })
  default = {
    timeout     = 30   # seconds
    memory_size = 256  # MB
  }
  
  validation {
    condition     = var.subscribe_function_config.timeout >= 1 && var.subscribe_function_config.timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
  
  validation {
    condition     = var.subscribe_function_config.memory_size >= 128 && var.subscribe_function_config.memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "newsletter_function_config" {
  description = "Configuration settings for the newsletter Lambda function"
  type = object({
    timeout     = number
    memory_size = number
  })
  default = {
    timeout     = 300  # seconds (5 minutes for bulk operations)
    memory_size = 512  # MB (higher memory for processing multiple subscribers)
  }
  
  validation {
    condition     = var.newsletter_function_config.timeout >= 1 && var.newsletter_function_config.timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
  
  validation {
    condition     = var.newsletter_function_config.memory_size >= 128 && var.newsletter_function_config.memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "list_function_config" {
  description = "Configuration settings for the list subscribers Lambda function"
  type = object({
    timeout     = number
    memory_size = number
  })
  default = {
    timeout     = 30   # seconds
    memory_size = 256  # MB
  }
  
  validation {
    condition     = var.list_function_config.timeout >= 1 && var.list_function_config.timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
  
  validation {
    condition     = var.list_function_config.memory_size >= 128 && var.list_function_config.memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "unsubscribe_function_config" {
  description = "Configuration settings for the unsubscribe Lambda function"
  type = object({
    timeout     = number
    memory_size = number
  })
  default = {
    timeout     = 30   # seconds
    memory_size = 256  # MB
  }
  
  validation {
    condition     = var.unsubscribe_function_config.timeout >= 1 && var.unsubscribe_function_config.timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
  
  validation {
    condition     = var.unsubscribe_function_config.memory_size >= 128 && var.unsubscribe_function_config.memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

#------------------------------------------------------------------------------
# Advanced Configuration
#------------------------------------------------------------------------------

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda functions to monitor performance and debug issues"
  type        = bool
  default     = false
}

variable "reserved_concurrent_executions" {
  description = "Number of reserved concurrent executions for Lambda functions. Set to 0 to disable function execution, -1 for unreserved."
  type        = number
  default     = -1
  
  validation {
    condition     = var.reserved_concurrent_executions >= -1
    error_message = "Reserved concurrent executions must be -1 or greater."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources. These will be merged with default tags."
  type        = map(string)
  default     = {}
}

#------------------------------------------------------------------------------
# Security Configuration
#------------------------------------------------------------------------------

variable "enable_lambda_insights" {
  description = "Enable Lambda Insights for enhanced monitoring and troubleshooting"
  type        = bool
  default     = false
}

variable "vpc_config" {
  description = "Optional VPC configuration for Lambda functions. Leave null to run in the default Lambda service VPC."
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

#------------------------------------------------------------------------------
# Cost Optimization
#------------------------------------------------------------------------------

variable "provisioned_concurrency" {
  description = "Provisioned concurrency settings for Lambda functions to reduce cold starts. Set to 0 to disable."
  type        = number
  default     = 0
  
  validation {
    condition     = var.provisioned_concurrency >= 0
    error_message = "Provisioned concurrency must be 0 or greater."
  }
}