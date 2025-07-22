# Variables for sustainable data archiving solution

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region name."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "sustainable-archive"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bucket_name_suffix" {
  description = "Suffix for bucket names (will be combined with random string)"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.bucket_name_suffix))
    error_message = "Bucket name suffix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_advanced_intelligent_tiering" {
  description = "Enable advanced intelligent tiering with Archive and Deep Archive tiers"
  type        = bool
  default     = true
}

variable "long_term_prefix" {
  description = "Prefix for objects that should use advanced intelligent tiering"
  type        = string
  default     = "long-term/"
}

variable "lifecycle_noncurrent_version_expiration_days" {
  description = "Number of days after which non-current versions are deleted"
  type        = number
  default     = 365
  
  validation {
    condition     = var.lifecycle_noncurrent_version_expiration_days > 0
    error_message = "Non-current version expiration days must be greater than 0."
  }
}

variable "lifecycle_noncurrent_version_glacier_days" {
  description = "Number of days after which non-current versions transition to Glacier"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_noncurrent_version_glacier_days > 0
    error_message = "Non-current version Glacier transition days must be greater than 0."
  }
}

variable "lifecycle_noncurrent_version_deep_archive_days" {
  description = "Number of days after which non-current versions transition to Deep Archive"
  type        = number
  default     = 90
  
  validation {
    condition = var.lifecycle_noncurrent_version_deep_archive_days > var.lifecycle_noncurrent_version_glacier_days
    error_message = "Deep Archive transition must be greater than Glacier transition days."
  }
}

variable "multipart_upload_cleanup_days" {
  description = "Number of days after which incomplete multipart uploads are cleaned up"
  type        = number
  default     = 1
  
  validation {
    condition     = var.multipart_upload_cleanup_days > 0
    error_message = "Multipart upload cleanup days must be greater than 0."
  }
}

variable "enable_storage_lens" {
  description = "Enable S3 Storage Lens for analytics"
  type        = bool
  default     = true
}

variable "storage_lens_export_prefix" {
  description = "Prefix for Storage Lens report exports"
  type        = string
  default     = "storage-lens-reports/"
}

variable "enable_sustainability_monitoring" {
  description = "Enable Lambda function for sustainability monitoring"
  type        = bool
  default     = true
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard for sustainability metrics"
  type        = bool
  default     = true
}

variable "monitoring_schedule" {
  description = "EventBridge schedule expression for sustainability monitoring"
  type        = string
  default     = "rate(1 day)"
  
  validation {
    condition = can(regex("^(rate\\(|cron\\()", var.monitoring_schedule))
    error_message = "Monitoring schedule must be a valid EventBridge schedule expression."
  }
}

variable "enable_sample_data" {
  description = "Create sample data for testing intelligent tiering"
  type        = bool
  default     = false
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}