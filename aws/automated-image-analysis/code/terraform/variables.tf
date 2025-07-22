# Variables for Amazon Rekognition image analysis infrastructure

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "rekognition-analysis"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "s3_versioning_enabled" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable lifecycle management on the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days after which objects transition to IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_lifecycle_transition_days > 0
    error_message = "Lifecycle transition days must be greater than 0."
  }
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days after which objects are deleted (0 to disable)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.s3_lifecycle_expiration_days >= 0
    error_message = "Lifecycle expiration days must be greater than or equal to 0."
  }
}

variable "enable_s3_public_access_block" {
  description = "Enable S3 public access block settings for security"
  type        = bool
  default     = true
}

variable "enable_s3_encryption" {
  description = "Enable S3 server-side encryption"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for API calls"
  type        = bool
  default     = false
}

variable "allowed_image_extensions" {
  description = "List of allowed image file extensions"
  type        = list(string)
  default     = ["jpg", "jpeg", "png"]
  
  validation {
    condition     = length(var.allowed_image_extensions) > 0
    error_message = "At least one image extension must be specified."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}