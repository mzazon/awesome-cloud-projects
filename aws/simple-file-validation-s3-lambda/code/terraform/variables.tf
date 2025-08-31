# =============================================================================
# Variables for Simple File Validation with S3 and Lambda
# =============================================================================

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "file-validation"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
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
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

# -----------------------------------------------------------------------------
# S3 Configuration
# -----------------------------------------------------------------------------

variable "force_destroy_buckets" {
  description = "Allow Terraform to destroy S3 buckets with objects (use with caution)"
  type        = bool
  default     = false
}

variable "s3_filter_prefix" {
  description = "S3 object key prefix filter for triggering Lambda function"
  type        = string
  default     = ""
}

variable "s3_filter_suffix" {
  description = "S3 object key suffix filter for triggering Lambda function"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Lambda Function Configuration
# -----------------------------------------------------------------------------

variable "lambda_memory_size" {
  description = "Amount of memory in MB your Lambda Function can use at runtime"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10,240 MB."
  }
}

variable "lambda_timeout" {
  description = "Amount of time your Lambda Function has to run in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_log_level" {
  description = "Log level for Lambda function (DEBUG, INFO, WARNING, ERROR, CRITICAL)"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.lambda_log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

# -----------------------------------------------------------------------------
# File Validation Configuration
# -----------------------------------------------------------------------------

variable "max_file_size_mb" {
  description = "Maximum allowed file size in megabytes"
  type        = number
  default     = 10

  validation {
    condition     = var.max_file_size_mb > 0 && var.max_file_size_mb <= 100
    error_message = "Maximum file size must be between 1 MB and 100 MB."
  }
}

variable "allowed_file_extensions" {
  description = "List of allowed file extensions (include the dot, e.g., .txt, .pdf)"
  type        = list(string)
  default     = [".txt", ".pdf", ".jpg", ".jpeg", ".png", ".doc", ".docx", ".csv"]

  validation {
    condition = alltrue([
      for ext in var.allowed_file_extensions : can(regex("^\\.[a-zA-Z0-9]+$", ext))
    ])
    error_message = "All file extensions must start with a dot and contain only alphanumeric characters."
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Logs Configuration
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch log retention periods."
  }
}

# -----------------------------------------------------------------------------
# Resource Tagging
# -----------------------------------------------------------------------------

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key, value in var.additional_tags :
      can(regex("^[a-zA-Z0-9+\\-=._:/@]*$", key)) && can(regex("^[a-zA-Z0-9+\\-=._:/@\\s]*$", value))
    ])
    error_message = "Tag keys and values must only contain alphanumeric characters and the characters: + - = . _ : / @ (spaces allowed in values)."
  }
}