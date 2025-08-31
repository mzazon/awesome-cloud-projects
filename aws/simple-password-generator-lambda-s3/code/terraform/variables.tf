# Input variables for the Simple Password Generator infrastructure

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "password-generator"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = ""
  
  validation {
    condition     = var.lambda_function_name == "" || can(regex("^[a-zA-Z0-9-_]+$", var.lambda_function_name))
    error_message = "Lambda function name must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "lambda_runtime" {
  description = "Python runtime version for Lambda function"
  type        = string
  default     = "python3.12"
  
  validation {
    condition     = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function execution in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10,240 MB (10 GB)."
  }
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for password storage (leave empty for auto-generated name)"
  type        = string
  default     = ""
  
  validation {
    condition = var.s3_bucket_name == "" || can(regex("^[a-z0-9.-]+$", var.s3_bucket_name)) && length(var.s3_bucket_name) >= 3 && length(var.s3_bucket_name) <= 63
    error_message = "S3 bucket name must be between 3-63 characters, contain only lowercase letters, numbers, dots, and hyphens."
  }
}

variable "s3_enable_versioning" {
  description = "Enable versioning for the S3 bucket to maintain password history"
  type        = bool
  default     = true
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days after which passwords will be automatically deleted (0 to disable)"
  type        = number
  default     = 90
  
  validation {
    condition     = var.s3_lifecycle_expiration_days >= 0
    error_message = "Lifecycle expiration days must be a non-negative number."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch values."
  }
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for the Lambda function"
  type        = bool
  default     = false
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = alltrue([for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9+-=._:/@]+$", k)) && can(regex("^[a-zA-Z0-9+-=._:/@\\s]*$", v))])
    error_message = "Tag keys and values must contain only valid characters."
  }
}

variable "force_destroy_bucket" {
  description = "Allow Terraform to destroy the S3 bucket even if it contains objects (USE WITH CAUTION)"
  type        = bool
  default     = false
}