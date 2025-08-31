# Variable definitions for the Markdown to HTML Converter infrastructure
# These variables allow customization of the deployment without modifying the core configuration

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|production)$", var.environment))
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "markdown-converter"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "input_bucket_suffix" {
  description = "Optional suffix for the input S3 bucket name (random if not provided)"
  type        = string
  default     = ""
}

variable "output_bucket_suffix" {
  description = "Optional suffix for the output S3 bucket name (random if not provided)"
  type        = string
  default     = ""
}

variable "lambda_function_name" {
  description = "Name for the Lambda function"
  type        = string
  default     = "markdown-to-html-converter"
  
  validation {
    condition     = length(var.lambda_function_name) <= 64
    error_message = "Lambda function name must be 64 characters or less."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for the Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Runtime environment for the Lambda function"
  type        = string
  default     = "python3.12"
  
  validation {
    condition = contains([
      "python3.9", "python3.10", "python3.11", "python3.12", "python3.13"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention period."
  }
}

variable "s3_bucket_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "s3_bucket_encryption" {
  description = "Enable server-side encryption on S3 buckets"
  type        = bool
  default     = true
}

variable "markdown_file_extensions" {
  description = "List of markdown file extensions to process"
  type        = list(string)
  default     = [".md", ".markdown"]
  
  validation {
    condition     = length(var.markdown_file_extensions) > 0
    error_message = "At least one markdown file extension must be specified."
  }
}

variable "enable_s3_access_logging" {
  description = "Enable access logging for S3 buckets"
  type        = bool
  default     = false
}

variable "enable_lambda_tracing" {
  description = "Enable X-Ray tracing for the Lambda function"
  type        = bool
  default     = false
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for the Lambda function (-1 for unreserved)"
  type        = number
  default     = -1
  
  validation {
    condition     = var.lambda_reserved_concurrency >= -1
    error_message = "Reserved concurrency must be -1 (unreserved) or a positive number."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}