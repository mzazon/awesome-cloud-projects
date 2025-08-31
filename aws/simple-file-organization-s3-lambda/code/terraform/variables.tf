# AWS Region for resource deployment
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

# Environment identifier for resource tagging
variable "environment" {
  description = "Environment name for resource tagging and identification"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# S3 bucket name prefix (will be made globally unique with random suffix)
variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name (random suffix will be added for uniqueness)"
  type        = string
  default     = "file-organizer"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Lambda function name
variable "function_name" {
  description = "Name of the Lambda function for file organization"
  type        = string
  default     = "file-organizer-function"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.function_name))
    error_message = "Function name must be 1-64 characters, letters, numbers, hyphens, and underscores only."
  }
}

# Lambda function timeout in seconds
variable "lambda_timeout" {
  description = "Timeout for Lambda function execution in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

# Lambda function memory allocation in MB
variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Enable S3 bucket versioning
variable "enable_versioning" {
  description = "Enable versioning on the S3 bucket for file safety"
  type        = bool
  default     = true
}

# S3 bucket encryption configuration
variable "enable_encryption" {
  description = "Enable server-side encryption on the S3 bucket"
  type        = bool
  default     = true
}

# File organization folders to create in the S3 bucket
variable "organization_folders" {
  description = "List of folders to create for file organization"
  type        = list(string)
  default     = ["images", "documents", "videos", "other"]
  
  validation {
    condition     = length(var.organization_folders) > 0
    error_message = "At least one organization folder must be specified."
  }
}

# Lambda runtime version
variable "lambda_runtime" {
  description = "Python runtime version for Lambda function"
  type        = string
  default     = "python3.12"
  
  validation {
    condition     = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

# CloudWatch log retention period
variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}