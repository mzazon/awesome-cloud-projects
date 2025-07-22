# General variables
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
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
  description = "Name of the project for resource naming"
  type        = string
  default     = "task-manager"
  
  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 32
    error_message = "Project name must be between 1 and 32 characters."
  }
}

# AppSync specific variables
variable "graphql_authentication_type" {
  description = "Authentication type for the GraphQL API"
  type        = string
  default     = "AWS_IAM"
  
  validation {
    condition = contains([
      "API_KEY",
      "AWS_IAM",
      "AMAZON_COGNITO_USER_POOLS",
      "OPENID_CONNECT",
      "AWS_LAMBDA"
    ], var.graphql_authentication_type)
    error_message = "Authentication type must be one of: API_KEY, AWS_IAM, AMAZON_COGNITO_USER_POOLS, OPENID_CONNECT, AWS_LAMBDA."
  }
}

variable "graphql_log_level" {
  description = "Log level for GraphQL API"
  type        = string
  default     = "ERROR"
  
  validation {
    condition     = contains(["NONE", "ERROR", "ALL"], var.graphql_log_level)
    error_message = "Log level must be one of: NONE, ERROR, ALL."
  }
}

# DynamoDB specific variables
variable "dynamodb_billing_mode" {
  description = "Billing mode for DynamoDB table"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "Billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "dynamodb_read_capacity" {
  description = "Read capacity units for DynamoDB table (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1 && var.dynamodb_read_capacity <= 10000
    error_message = "Read capacity must be between 1 and 10000."
  }
}

variable "dynamodb_write_capacity" {
  description = "Write capacity units for DynamoDB table (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1 && var.dynamodb_write_capacity <= 10000
    error_message = "Write capacity must be between 1 and 10000."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = false
}

# Lambda specific variables
variable "lambda_runtime" {
  description = "Runtime for Lambda function"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains([
      "python3.8",
      "python3.9",
      "python3.10",
      "python3.11",
      "nodejs16.x",
      "nodejs18.x",
      "nodejs20.x"
    ], var.lambda_runtime)
    error_message = "Runtime must be a supported Lambda runtime version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# EventBridge Scheduler variables
variable "enable_sample_schedule" {
  description = "Whether to create a sample EventBridge schedule for testing"
  type        = bool
  default     = false
}

variable "sample_schedule_rate" {
  description = "Rate expression for sample schedule (e.g., 'rate(5 minutes)')"
  type        = string
  default     = "rate(5 minutes)"
}