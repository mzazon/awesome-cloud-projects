# Variables for S3 Glacier Archiving Configuration
# This file defines all the configurable parameters for the archiving solution

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
  default     = "dev"
  
  validation {
    condition = can(regex("^[a-z]+$", var.environment))
    error_message = "Environment must contain only lowercase letters."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name (random suffix will be added)"
  type        = string
  default     = "awscookbook-archive"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "lifecycle_glacier_transition_days" {
  description = "Number of days before objects transition to Glacier Flexible Retrieval"
  type        = number
  default     = 90
  
  validation {
    condition = var.lifecycle_glacier_transition_days >= 30
    error_message = "Minimum transition time to Glacier is 30 days."
  }
}

variable "lifecycle_deep_archive_transition_days" {
  description = "Number of days before objects transition to Glacier Deep Archive"
  type        = number
  default     = 365
  
  validation {
    condition = var.lifecycle_deep_archive_transition_days >= 180
    error_message = "Minimum transition time to Deep Archive is 180 days."
  }
}

variable "archive_prefix" {
  description = "S3 key prefix for objects that should be archived"
  type        = string
  default     = "data/"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9_/-]+/$", var.archive_prefix))
    error_message = "Archive prefix must end with a forward slash and contain only alphanumeric characters, underscores, hyphens, and forward slashes."
  }
}

variable "notification_email" {
  description = "Email address for SNS notifications (leave empty to skip email subscription)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_server_side_encryption" {
  description = "Enable server-side encryption for S3 bucket"
  type        = bool
  default     = true
}

variable "enable_public_access_block" {
  description = "Enable public access block for S3 bucket"
  type        = bool
  default     = true
}

variable "enable_mfa_delete" {
  description = "Enable MFA delete for S3 bucket (requires versioning)"
  type        = bool
  default     = false
}

variable "retention_mode" {
  description = "S3 Object Lock retention mode (GOVERNANCE or COMPLIANCE)"
  type        = string
  default     = "GOVERNANCE"
  
  validation {
    condition = contains(["GOVERNANCE", "COMPLIANCE"], var.retention_mode)
    error_message = "Retention mode must be either GOVERNANCE or COMPLIANCE."
  }
}

variable "enable_object_lock" {
  description = "Enable S3 Object Lock for compliance (requires versioning)"
  type        = bool
  default     = false
}

variable "restore_tier" {
  description = "Default restore tier for Glacier objects (Standard, Bulk, Expedited)"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Standard", "Bulk", "Expedited"], var.restore_tier)
    error_message = "Restore tier must be Standard, Bulk, or Expedited."
  }
}

variable "restore_days" {
  description = "Number of days to keep restored objects available"
  type        = number
  default     = 7
  
  validation {
    condition = var.restore_days >= 1 && var.restore_days <= 365
    error_message = "Restore days must be between 1 and 365."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}