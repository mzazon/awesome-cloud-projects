# Input variables for the Simple Color Palette Generator infrastructure
# These variables allow customization of the deployment while maintaining best practices

variable "project_name" {
  description = "Name of the project, used for resource naming and tagging"
  type        = string
  default     = "color-palette-generator"

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
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for unique resource naming"
  type        = number
  default     = 6

  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 4 and 10 characters."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "s3_force_destroy" {
  description = "Allow Terraform to destroy S3 bucket even if not empty (use with caution)"
  type        = bool
  default     = false
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket for palette history tracking"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch Logs for Lambda function monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch Logs"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allowed_methods" {
  description = "List of allowed HTTP methods for CORS configuration"
  type        = list(string)
  default     = ["GET", "POST", "OPTIONS"]
}

variable "cors_allowed_headers" {
  description = "List of allowed headers for CORS configuration"
  type        = list(string)
  default     = ["Content-Type"]
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}