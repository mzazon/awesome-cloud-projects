# Core Configuration Variables
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "lex-chatbot"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Amazon Lex Configuration
variable "bot_name" {
  description = "Name of the Amazon Lex bot"
  type        = string
  default     = ""
  
  validation {
    condition     = var.bot_name == "" || can(regex("^[a-zA-Z0-9_-]+$", var.bot_name))
    error_message = "Bot name must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "bot_description" {
  description = "Description of the Amazon Lex bot"
  type        = string
  default     = "Customer service chatbot for product inquiries and order status"
}

variable "bot_idle_session_ttl" {
  description = "Idle session timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.bot_idle_session_ttl >= 60 && var.bot_idle_session_ttl <= 86400
    error_message = "Bot idle session TTL must be between 60 and 86400 seconds."
  }
}

variable "nlu_confidence_threshold" {
  description = "NLU intent confidence threshold"
  type        = number
  default     = 0.7
  
  validation {
    condition     = var.nlu_confidence_threshold >= 0.0 && var.nlu_confidence_threshold <= 1.0
    error_message = "NLU confidence threshold must be between 0.0 and 1.0."
  }
}

# Lambda Configuration
variable "lambda_function_name" {
  description = "Name of the Lambda fulfillment function"
  type        = string
  default     = ""
  
  validation {
    condition     = var.lambda_function_name == "" || can(regex("^[a-zA-Z0-9-_]+$", var.lambda_function_name))
    error_message = "Lambda function name must contain only letters, numbers, hyphens, and underscores."
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
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
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

# DynamoDB Configuration
variable "orders_table_name" {
  description = "Name of the DynamoDB orders table"
  type        = string
  default     = ""
  
  validation {
    condition     = var.orders_table_name == "" || can(regex("^[a-zA-Z0-9_.-]+$", var.orders_table_name))
    error_message = "DynamoDB table name must contain only letters, numbers, underscores, periods, and hyphens."
  }
}

variable "dynamodb_billing_mode" {
  description = "Billing mode for DynamoDB table"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

# S3 Configuration
variable "products_bucket_name" {
  description = "Name of the S3 bucket for product catalog"
  type        = string
  default     = ""
  
  validation {
    condition     = var.products_bucket_name == "" || can(regex("^[a-z0-9.-]+$", var.products_bucket_name))
    error_message = "S3 bucket name must contain only lowercase letters, numbers, periods, and hyphens."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = false
}

variable "s3_force_destroy" {
  description = "Allow Terraform to destroy the S3 bucket with objects"
  type        = bool
  default     = true
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Random Suffix
variable "use_random_suffix" {
  description = "Whether to append a random suffix to resource names"
  type        = bool
  default     = true
}