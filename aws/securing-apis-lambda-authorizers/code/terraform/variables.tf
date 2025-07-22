variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
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

variable "api_name" {
  description = "Name for the API Gateway"
  type        = string
  default     = "secure-api"
}

variable "token_authorizer_name" {
  description = "Name for the token-based Lambda authorizer function"
  type        = string
  default     = "token-authorizer"
}

variable "request_authorizer_name" {
  description = "Name for the request-based Lambda authorizer function"
  type        = string
  default     = "request-authorizer"
}

variable "protected_function_name" {
  description = "Name for the protected API Lambda function"
  type        = string
  default     = "protected-api"
}

variable "public_function_name" {
  description = "Name for the public API Lambda function"
  type        = string
  default     = "public-api"
}

variable "authorizer_cache_ttl" {
  description = "TTL for authorizer cache in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.authorizer_cache_ttl >= 0 && var.authorizer_cache_ttl <= 3600
    error_message = "Authorizer cache TTL must be between 0 and 3600 seconds."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "api_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for API Gateway"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "valid_tokens" {
  description = "Map of valid tokens for testing purposes"
  type = map(object({
    principal_id = string
    role         = string
    permissions  = string
  }))
  default = {
    "admin-token" = {
      principal_id = "admin-user"
      role         = "admin"
      permissions  = "read,write,delete"
    }
    "user-token" = {
      principal_id = "regular-user"
      role         = "user"
      permissions  = "read"
    }
  }
  sensitive = true
}

variable "valid_api_keys" {
  description = "List of valid API keys for request-based authorization"
  type        = list(string)
  default     = ["secret-api-key-123"]
  sensitive   = true
}

variable "custom_auth_values" {
  description = "List of valid custom auth header values"
  type        = list(string)
  default     = ["custom-auth-value"]
  sensitive   = true
}