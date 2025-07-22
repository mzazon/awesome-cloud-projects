# Input variables for the custom CloudFormation resources infrastructure

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-west-2' or similar."
  }
}

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "development"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "custom-resource-demo"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
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

variable "lambda_runtime" {
  description = "Python runtime version for Lambda functions"
  type        = string
  default     = "python3.9"

  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "log_retention_days" {
  description = "CloudWatch logs retention period in days"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch logs retention value."
  }
}

variable "s3_versioning_enabled" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days after which to delete old S3 object versions"
  type        = number
  default     = 30

  validation {
    condition     = var.s3_lifecycle_expiration_days > 0
    error_message = "S3 lifecycle expiration days must be greater than 0."
  }
}

variable "custom_data_content" {
  description = "JSON content for the custom resource data"
  type        = string
  default     = "{\"environment\": \"demo\", \"version\": \"1.0\", \"features\": [\"logging\", \"monitoring\"]}"

  validation {
    condition     = can(jsondecode(var.custom_data_content))
    error_message = "Custom data content must be valid JSON."
  }
}

variable "data_file_name" {
  description = "Name of the data file to create in S3"
  type        = string
  default     = "demo-data.json"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+\\.(json|txt|yaml|yml)$", var.data_file_name))
    error_message = "Data file name must be a valid file name with appropriate extension."
  }
}

variable "enable_advanced_error_handling" {
  description = "Deploy the advanced Lambda function with enhanced error handling"
  type        = bool
  default     = true
}

variable "enable_production_template" {
  description = "Deploy the production-ready CloudFormation template"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition     = length(var.tags) <= 50
    error_message = "Maximum of 50 additional tags allowed."
  }
}