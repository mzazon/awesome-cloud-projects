# Variables for S3 Scheduled Backups Infrastructure
# This file defines all input variables for the backup solution

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z]+$", var.environment))
    error_message = "Environment must contain only lowercase letters."
  }
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "s3-backup"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "primary_bucket_name" {
  description = "Name of the primary S3 bucket (leave empty for auto-generated name)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.primary_bucket_name == "" || can(regex("^[a-z0-9.-]+$", var.primary_bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, dots, and hyphens."
  }
}

variable "backup_bucket_name" {
  description = "Name of the backup S3 bucket (leave empty for auto-generated name)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.backup_bucket_name == "" || can(regex("^[a-z0-9.-]+$", var.backup_bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, dots, and hyphens."
  }
}

variable "backup_schedule" {
  description = "EventBridge schedule expression for backup execution (cron format)"
  type        = string
  default     = "cron(0 1 * * ? *)"
  
  validation {
    condition     = can(regex("^(cron|rate)\\(.*\\)$", var.backup_schedule))
    error_message = "Schedule must be a valid EventBridge schedule expression."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 10 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 10 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory allocation in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lifecycle_ia_transition_days" {
  description = "Number of days after which objects transition to Standard-IA"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_ia_transition_days >= 0
    error_message = "IA transition days must be non-negative."
  }
}

variable "lifecycle_glacier_transition_days" {
  description = "Number of days after which objects transition to Glacier"
  type        = number
  default     = 90
  
  validation {
    condition     = var.lifecycle_glacier_transition_days >= 0
    error_message = "Glacier transition days must be non-negative."
  }
}

variable "lifecycle_expiration_days" {
  description = "Number of days after which objects are deleted (0 to disable)"
  type        = number
  default     = 365
  
  validation {
    condition     = var.lifecycle_expiration_days >= 0
    error_message = "Expiration days must be non-negative."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on the backup bucket"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable server-side encryption for S3 buckets"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}