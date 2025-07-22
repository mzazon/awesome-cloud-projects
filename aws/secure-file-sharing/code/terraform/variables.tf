# Variables for S3 Presigned URLs File Sharing Solution
# This file defines all configurable parameters for the infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format xx-xxxx-x (e.g., us-east-1)."
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "file-sharing-demo"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bucket_name_suffix" {
  description = "Optional suffix for bucket name (leave empty for random suffix)"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.bucket_name_suffix))
    error_message = "Bucket name suffix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning for better file management"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable S3 bucket server-side encryption"
  type        = bool
  default     = true
}

variable "default_presigned_url_expiry" {
  description = "Default expiration time for presigned URLs in hours"
  type        = number
  default     = 24

  validation {
    condition     = var.default_presigned_url_expiry > 0 && var.default_presigned_url_expiry <= 168
    error_message = "Presigned URL expiry must be between 1 and 168 hours (7 days)."
  }
}

variable "enable_access_logging" {
  description = "Enable S3 access logging for audit purposes"
  type        = bool
  default     = true
}

variable "lifecycle_rules" {
  description = "S3 lifecycle configuration for automatic file management"
  type = object({
    enable_documents_transition = bool
    documents_ia_days          = number
    documents_glacier_days     = number
    enable_uploads_cleanup     = bool
    uploads_expiry_days        = number
  })
  default = {
    enable_documents_transition = true
    documents_ia_days          = 30
    documents_glacier_days     = 90
    enable_uploads_cleanup     = true
    uploads_expiry_days        = 7
  }

  validation {
    condition = (
      var.lifecycle_rules.documents_ia_days > 0 &&
      var.lifecycle_rules.documents_glacier_days > var.lifecycle_rules.documents_ia_days &&
      var.lifecycle_rules.uploads_expiry_days > 0
    )
    error_message = "Lifecycle rules must have positive values and glacier days must be greater than IA days."
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allowed_methods" {
  description = "List of allowed HTTP methods for CORS"
  type        = list(string)
  default     = ["GET", "PUT", "POST", "DELETE", "HEAD"]
}

variable "notification_email" {
  description = "Email address for CloudWatch alarm notifications (optional)"
  type        = string
  default     = ""

  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for S3 API calls"
  type        = bool
  default     = false
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}