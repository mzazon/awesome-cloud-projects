# variables.tf
# Variables for AWS AppSync and DynamoDB Streams real-time data synchronization

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "appsync-realtime-sync"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment for resource deployment (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table for storing real-time data"
  type        = string
  default     = ""
  
  validation {
    condition     = var.dynamodb_table_name == "" || can(regex("^[a-zA-Z0-9._-]{3,255}$", var.dynamodb_table_name))
    error_message = "DynamoDB table name must be between 3 and 255 characters and contain only letters, numbers, dots, hyphens, and underscores."
  }
}

variable "appsync_api_name" {
  description = "Name of the AppSync GraphQL API"
  type        = string
  default     = ""
  
  validation {
    condition     = var.appsync_api_name == "" || can(regex("^[a-zA-Z0-9_-]{1,65}$", var.appsync_api_name))
    error_message = "AppSync API name must be between 1 and 65 characters and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "lambda_function_name" {
  description = "Name of the Lambda function for processing DynamoDB streams"
  type        = string
  default     = ""
  
  validation {
    condition     = var.lambda_function_name == "" || can(regex("^[a-zA-Z0-9_-]{1,64}$", var.lambda_function_name))
    error_message = "Lambda function name must be between 1 and 64 characters and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "stream_batch_size" {
  description = "Batch size for DynamoDB stream processing"
  type        = number
  default     = 10
  
  validation {
    condition     = var.stream_batch_size >= 1 && var.stream_batch_size <= 1000
    error_message = "Stream batch size must be between 1 and 1000."
  }
}

variable "stream_maximum_batching_window_in_seconds" {
  description = "Maximum batching window for DynamoDB stream processing in seconds"
  type        = number
  default     = 5
  
  validation {
    condition     = var.stream_maximum_batching_window_in_seconds >= 0 && var.stream_maximum_batching_window_in_seconds <= 300
    error_message = "Maximum batching window must be between 0 and 300 seconds."
  }
}

variable "appsync_authentication_type" {
  description = "Authentication type for AppSync API"
  type        = string
  default     = "API_KEY"
  
  validation {
    condition     = contains(["API_KEY", "AWS_IAM", "AMAZON_COGNITO_USER_POOLS", "OPENID_CONNECT"], var.appsync_authentication_type)
    error_message = "Authentication type must be one of: API_KEY, AWS_IAM, AMAZON_COGNITO_USER_POOLS, OPENID_CONNECT."
  }
}

variable "api_key_description" {
  description = "Description for the AppSync API key"
  type        = string
  default     = "API key for real-time data synchronization"
}

variable "api_key_expires" {
  description = "Expiration time for the AppSync API key in seconds from creation"
  type        = number
  default     = 7776000 # 90 days
  
  validation {
    condition     = var.api_key_expires >= 86400 && var.api_key_expires <= 31536000
    error_message = "API key expiration must be between 1 day (86400) and 365 days (31536000) in seconds."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for AppSync"
  type        = bool
  default     = true
}

variable "cloudwatch_logs_retention_in_days" {
  description = "Retention period for CloudWatch logs in days"
  type        = number
  default     = 7
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_logs_retention_in_days)
    error_message = "CloudWatch logs retention must be a valid retention period."
  }
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "AppSync-RealTime-Sync"
    ManagedBy   = "Terraform"
    Environment = "dev"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}