# Variables for serverless web applications with Amplify and Lambda
# This file defines all configurable variables for the Terraform deployment

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming and tagging"
  type        = string
  default     = "serverless-web-app"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
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

variable "amplify_repository" {
  description = "Git repository URL for Amplify app (optional)"
  type        = string
  default     = ""

  validation {
    condition = var.amplify_repository == "" || can(regex("^https://", var.amplify_repository))
    error_message = "Repository URL must be empty or start with https://."
  }
}

variable "amplify_branch" {
  description = "Git branch for Amplify deployments"
  type        = string
  default     = "main"

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_-]+$", var.amplify_branch))
    error_message = "Branch name must contain only alphanumeric characters, hyphens, underscores, and forward slashes."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "nodejs18.x"

  validation {
    condition = contains([
      "nodejs14.x", "nodejs16.x", "nodejs18.x", "nodejs20.x",
      "python3.8", "python3.9", "python3.10", "python3.11"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported AWS Lambda runtime."
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

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only used with PROVISIONED billing mode)"
  type        = number
  default     = 5

  validation {
    condition     = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used with PROVISIONED billing mode)"
  type        = number
  default     = 5

  validation {
    condition     = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

variable "api_gateway_stage_name" {
  description = "API Gateway deployment stage name"
  type        = string
  default     = "api"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]+$", var.api_gateway_stage_name))
    error_message = "API Gateway stage name must contain only alphanumeric characters."
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]

  validation {
    condition     = length(var.cors_allowed_origins) > 0
    error_message = "At least one CORS origin must be specified."
  }
}

variable "enable_api_caching" {
  description = "Enable API Gateway caching"
  type        = bool
  default     = false
}

variable "api_cache_ttl" {
  description = "API Gateway cache TTL in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.api_cache_ttl >= 0 && var.api_cache_ttl <= 3600
    error_message = "API cache TTL must be between 0 and 3600 seconds."
  }
}

variable "cognito_mfa_configuration" {
  description = "Cognito MFA configuration"
  type        = string
  default     = "OPTIONAL"

  validation {
    condition     = contains(["OFF", "ON", "OPTIONAL"], var.cognito_mfa_configuration)
    error_message = "Cognito MFA configuration must be one of: OFF, ON, OPTIONAL."
  }
}

variable "cognito_password_policy" {
  description = "Cognito password policy configuration"
  type = object({
    minimum_length    = number
    require_lowercase = bool
    require_numbers   = bool
    require_symbols   = bool
    require_uppercase = bool
  })
  default = {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  validation {
    condition     = var.cognito_password_policy.minimum_length >= 6 && var.cognito_password_policy.minimum_length <= 99
    error_message = "Password minimum length must be between 6 and 99 characters."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for API Gateway and Lambda"
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

variable "enable_x_ray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda functions"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition     = length(var.tags) <= 50
    error_message = "Cannot specify more than 50 additional tags."
  }
}