# Input variables for the URL Shortener infrastructure
# These variables allow customization of the deployment

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "url-shortener"

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
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = null # Will use current provider region if null
}

variable "dynamodb_billing_mode" {
  description = "Billing mode for DynamoDB table (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "dynamodb_read_capacity" {
  description = "Read capacity units for DynamoDB table (only used with PROVISIONED billing)"
  type        = number
  default     = 5

  validation {
    condition     = var.dynamodb_read_capacity >= 1 && var.dynamodb_read_capacity <= 40000
    error_message = "DynamoDB read capacity must be between 1 and 40000."
  }
}

variable "dynamodb_write_capacity" {
  description = "Write capacity units for DynamoDB table (only used with PROVISIONED billing)"
  type        = number
  default     = 5

  validation {
    condition     = var.dynamodb_write_capacity >= 1 && var.dynamodb_write_capacity <= 40000
    error_message = "DynamoDB write capacity must be between 1 and 40000."
  }
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 10

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size in MB for Lambda functions"
  type        = number
  default     = 128

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "api_gateway_stage_name" {
  description = "Stage name for API Gateway deployment"
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.api_gateway_stage_name))
    error_message = "API Gateway stage name must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 2000

  validation {
    condition     = var.api_throttle_burst_limit >= 0
    error_message = "API throttle burst limit must be non-negative."
  }
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 1000

  validation {
    condition     = var.api_throttle_rate_limit >= 0
    error_message = "API throttle rate limit must be non-negative."
  }
}

variable "short_code_length" {
  description = "Length of generated short codes"
  type        = number
  default     = 6

  validation {
    condition     = var.short_code_length >= 4 && var.short_code_length <= 10
    error_message = "Short code length must be between 4 and 10 characters."
  }
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda functions"
  type        = bool
  default     = false
}

variable "log_retention_in_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_in_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention value."
  }
}

variable "enable_api_access_logging" {
  description = "Enable access logging for API Gateway"
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}