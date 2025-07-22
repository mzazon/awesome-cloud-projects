# Variables for Amazon Chime SDK video conferencing solution
# This file defines all configurable parameters for the infrastructure deployment

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
  default     = "video-conferencing"

  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 20
    error_message = "Project name must be between 3 and 20 characters."
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

variable "random_suffix_length" {
  description = "Length of random suffix for unique resource naming"
  type        = number
  default     = 6

  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 8
    error_message = "Random suffix length must be between 4 and 8 characters."
  }
}

# DynamoDB Configuration
variable "dynamodb_read_capacity" {
  description = "DynamoDB table read capacity units"
  type        = number
  default     = 5

  validation {
    condition     = var.dynamodb_read_capacity >= 1 && var.dynamodb_read_capacity <= 40000
    error_message = "DynamoDB read capacity must be between 1 and 40000."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB table write capacity units"
  type        = number
  default     = 5

  validation {
    condition     = var.dynamodb_write_capacity >= 1 && var.dynamodb_write_capacity <= 40000
    error_message = "DynamoDB write capacity must be between 1 and 40000."
  }
}

# Lambda Configuration
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
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "nodejs18.x"

  validation {
    condition = contains([
      "nodejs18.x",
      "nodejs20.x",
      "python3.9",
      "python3.10",
      "python3.11"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported runtime version."
  }
}

# S3 Configuration
variable "s3_bucket_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "s3_bucket_encryption" {
  description = "S3 bucket server-side encryption configuration"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.s3_bucket_encryption)
    error_message = "S3 encryption must be either AES256 or aws:kms."
  }
}

# API Gateway Configuration
variable "api_gateway_stage_name" {
  description = "API Gateway deployment stage name"
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.api_gateway_stage_name))
    error_message = "API Gateway stage name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "api_gateway_throttle_rate_limit" {
  description = "API Gateway throttling rate limit (requests per second)"
  type        = number
  default     = 2000

  validation {
    condition     = var.api_gateway_throttle_rate_limit >= 1
    error_message = "API Gateway rate limit must be at least 1 request per second."
  }
}

variable "api_gateway_throttle_burst_limit" {
  description = "API Gateway throttling burst limit"
  type        = number
  default     = 5000

  validation {
    condition     = var.api_gateway_throttle_burst_limit >= var.api_gateway_throttle_rate_limit
    error_message = "API Gateway burst limit must be greater than or equal to rate limit."
  }
}

# Monitoring and Logging
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for all resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

# Security Configuration
variable "enable_sns_encryption" {
  description = "Enable SNS topic encryption"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed CORS origins for API Gateway"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allowed_methods" {
  description = "List of allowed CORS methods for API Gateway"
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
}

variable "cors_allowed_headers" {
  description = "List of allowed CORS headers for API Gateway"
  type        = list(string)
  default     = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}