# Input Variables for S3 Intelligent Tiering Configuration
# These variables allow customization of the S3 bucket and storage optimization settings

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format of 'us-east-1', 'eu-west-1', etc."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = length(var.environment) > 0 && length(var.environment) <= 10
    error_message = "Environment must be between 1 and 10 characters."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name. A random suffix will be added automatically."
  type        = string
  default     = "intelligent-tiering-demo"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning for data protection"
  type        = bool
  default     = true
}

variable "enable_mfa_delete" {
  description = "Require MFA for object deletion (requires versioning)"
  type        = bool
  default     = false
}

variable "intelligent_tiering_archive_days" {
  description = "Number of days before objects are moved to Archive Access tier"
  type        = number
  default     = 90
  
  validation {
    condition     = var.intelligent_tiering_archive_days >= 90
    error_message = "Archive access tier requires minimum 90 days."
  }
}

variable "intelligent_tiering_deep_archive_days" {
  description = "Number of days before objects are moved to Deep Archive Access tier"
  type        = number
  default     = 180
  
  validation {
    condition     = var.intelligent_tiering_deep_archive_days >= 180
    error_message = "Deep archive access tier requires minimum 180 days."
  }
}

variable "lifecycle_transition_to_intelligent_tiering_days" {
  description = "Number of days before objects transition to Intelligent Tiering"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_transition_to_intelligent_tiering_days >= 0
    error_message = "Transition days must be a non-negative number."
  }
}

variable "lifecycle_abort_incomplete_multipart_days" {
  description = "Number of days to abort incomplete multipart uploads"
  type        = number
  default     = 7
  
  validation {
    condition     = var.lifecycle_abort_incomplete_multipart_days >= 1
    error_message = "Abort incomplete multipart uploads must be at least 1 day."
  }
}

variable "noncurrent_version_transition_ia_days" {
  description = "Days after which noncurrent object versions transition to IA storage"
  type        = number
  default     = 30
}

variable "noncurrent_version_transition_glacier_days" {
  description = "Days after which noncurrent object versions transition to Glacier"
  type        = number
  default     = 90
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which noncurrent object versions are permanently deleted"
  type        = number
  default     = 365
}

variable "enable_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard for monitoring storage metrics"
  type        = bool
  default     = true
}

variable "enable_access_logging" {
  description = "Enable S3 access logging for audit and analysis"
  type        = bool
  default     = true
}

variable "enable_object_lock" {
  description = "Enable S3 Object Lock for compliance and data protection"
  type        = bool
  default     = false
}

variable "object_lock_mode" {
  description = "Object Lock mode (GOVERNANCE or COMPLIANCE)"
  type        = string
  default     = "GOVERNANCE"
  
  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "Object lock mode must be either GOVERNANCE or COMPLIANCE."
  }
}

variable "object_lock_retention_years" {
  description = "Default retention period in years for Object Lock"
  type        = number
  default     = 1
  
  validation {
    condition     = var.object_lock_retention_years >= 1
    error_message = "Object lock retention must be at least 1 year."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}