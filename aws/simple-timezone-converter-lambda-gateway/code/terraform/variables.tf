# Variables for Simple Timezone Converter with Lambda and API Gateway
# This file defines all input variables used in the Terraform configuration

# Environment and tagging variables
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "cost_center" {
  description = "Cost center for resource billing and tracking"
  type        = string
  default     = "engineering"
}

variable "project_name" {
  description = "Name of the project - used for resource naming"
  type        = string
  default     = "timezone-converter"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Lambda function configuration variables
variable "lambda_function_name" {
  description = "Name of the Lambda function (will be prefixed with project name)"
  type        = string
  default     = "timezone-converter"
}

variable "lambda_runtime" {
  description = "Python runtime version for Lambda function"
  type        = string
  default     = "python3.12"
  
  validation {
    condition     = can(regex("^python3\\.(9|10|11|12)$", var.lambda_runtime))
    error_message = "Lambda runtime must be python3.9, python3.10, python3.11, or python3.12."
  }
}

variable "lambda_timeout" {
  description = "Maximum execution time for Lambda function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocated to Lambda function in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_description" {
  description = "Description for the Lambda function"
  type        = string
  default     = "Simple timezone converter API function"
}

# API Gateway configuration variables
variable "api_gateway_name" {
  description = "Name of the API Gateway REST API"
  type        = string
  default     = "timezone-converter-api"
}

variable "api_gateway_description" {
  description = "Description for the API Gateway"
  type        = string
  default     = "REST API for timezone conversion service"
}

variable "api_gateway_stage_name" {
  description = "Deployment stage name for API Gateway"
  type        = string
  default     = "prod"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.api_gateway_stage_name))
    error_message = "API Gateway stage name must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "api_gateway_endpoint_type" {
  description = "Endpoint configuration type for API Gateway"
  type        = string
  default     = "REGIONAL"
  
  validation {
    condition     = can(regex("^(REGIONAL|EDGE|PRIVATE)$", var.api_gateway_endpoint_type))
    error_message = "API Gateway endpoint type must be REGIONAL, EDGE, or PRIVATE."
  }
}

# IAM configuration variables
variable "lambda_role_name" {
  description = "Name of the IAM role for Lambda execution"
  type        = string
  default     = "timezone-converter-lambda-role"
}

# CloudWatch Logs configuration
variable "log_retention_in_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_in_days)
    error_message = "Log retention must be one of the valid CloudWatch Logs retention periods."
  }
}

# Security and access control variables
variable "enable_cors" {
  description = "Enable CORS headers in API responses"
  type        = bool
  default     = true
}

variable "cors_allow_origins" {
  description = "List of allowed origins for CORS (use ['*'] to allow all)"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allow_methods" {
  description = "List of allowed HTTP methods for CORS"
  type        = list(string)
  default     = ["GET", "POST", "OPTIONS"]
}

variable "cors_allow_headers" {
  description = "List of allowed headers for CORS"
  type        = list(string)
  default     = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
}

# Resource naming and uniqueness
variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness (leave empty to auto-generate)"
  type        = string
  default     = ""
}

# Lambda source code configuration
variable "lambda_source_path" {
  description = "Path to Lambda function source code (relative to module root)"
  type        = string
  default     = "lambda_function.py"
}

# API throttling configuration
variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.api_throttle_rate_limit >= 1 && var.api_throttle_rate_limit <= 10000
    error_message = "API throttle rate limit must be between 1 and 10000 requests per second."
  }
}

variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 200
  
  validation {
    condition     = var.api_throttle_burst_limit >= 1 && var.api_throttle_burst_limit <= 5000
    error_message = "API throttle burst limit must be between 1 and 5000."
  }
}

# Monitoring and observability
variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda function"
  type        = bool
  default     = false
}

variable "enable_detailed_cloudwatch_metrics" {
  description = "Enable detailed CloudWatch metrics for API Gateway"
  type        = bool
  default     = false
}