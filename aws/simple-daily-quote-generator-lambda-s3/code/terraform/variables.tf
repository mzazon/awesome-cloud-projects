# AWS region for resource deployment
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be a valid region identifier (e.g., us-east-1, eu-west-1)."
  }
}

# Environment identifier for resource naming and tagging
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Lambda function configuration
variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "daily-quote-generator"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.lambda_function_name))
    error_message = "Lambda function name must be 1-64 characters and contain only letters, numbers, hyphens, and underscores."
  }
}

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
  default     = 128

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.12"

  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

# S3 bucket configuration
variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket name (will be suffixed with random string)"
  type        = string
  default     = "daily-quotes"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,37}$", var.s3_bucket_prefix))
    error_message = "S3 bucket prefix must be 3-37 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = false
}

# Quote data configuration
variable "quotes_data" {
  description = "JSON data containing inspirational quotes"
  type = object({
    quotes = list(object({
      text   = string
      author = string
    }))
  })
  default = {
    quotes = [
      {
        text   = "The only way to do great work is to love what you do."
        author = "Steve Jobs"
      },
      {
        text   = "Innovation distinguishes between a leader and a follower."
        author = "Steve Jobs"
      },
      {
        text   = "Life is what happens to you while you're busy making other plans."
        author = "John Lennon"
      },
      {
        text   = "The future belongs to those who believe in the beauty of their dreams."
        author = "Eleanor Roosevelt"
      },
      {
        text   = "It is during our darkest moments that we must focus to see the light."
        author = "Aristotle"
      },
      {
        text   = "Success is not final, failure is not fatal: it is the courage to continue that counts."
        author = "Winston Churchill"
      }
    ]
  }
}

# CORS configuration for Lambda Function URL
variable "cors_allow_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allow_methods" {
  description = "List of allowed HTTP methods for CORS"
  type        = list(string)
  default     = ["GET"]
}

variable "cors_max_age" {
  description = "Maximum age for CORS preflight cache in seconds"
  type        = number
  default     = 86400

  validation {
    condition     = var.cors_max_age >= 0 && var.cors_max_age <= 86400
    error_message = "CORS max age must be between 0 and 86400 seconds."
  }
}

# Resource naming configuration
variable "resource_name_suffix" {
  description = "Optional suffix for resource names (leave empty to auto-generate)"
  type        = string
  default     = ""

  validation {
    condition     = var.resource_name_suffix == "" || can(regex("^[a-z0-9-]{1,8}$", var.resource_name_suffix))
    error_message = "Resource name suffix must be empty or 1-8 characters containing only lowercase letters, numbers, and hyphens."
  }
}

# Cost optimization settings
variable "enable_cost_optimization" {
  description = "Enable cost optimization features (S3 Intelligent Tiering, etc.)"
  type        = bool
  default     = false
}