# Core configuration variables
variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "multi-region-s3"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Regional configuration
variable "primary_region" {
  description = "Primary AWS region for source S3 bucket"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.primary_region))
    error_message = "Primary region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for first destination S3 bucket"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.secondary_region))
    error_message = "Secondary region must be a valid AWS region format (e.g., us-west-2)."
  }
}

variable "tertiary_region" {
  description = "Tertiary AWS region for second destination S3 bucket"
  type        = string
  default     = "eu-west-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.tertiary_region))
    error_message = "Tertiary region must be a valid AWS region format (e.g., eu-west-1)."
  }
}

# Bucket configuration
variable "enable_versioning" {
  description = "Enable S3 bucket versioning (required for replication)"
  type        = bool
  default     = true
}

variable "enable_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering for cost optimization"
  type        = bool
  default     = true
}

variable "enable_lifecycle_policy" {
  description = "Enable S3 lifecycle policies for cost optimization"
  type        = bool
  default     = true
}

variable "enable_bucket_key" {
  description = "Enable S3 Bucket Key for KMS cost optimization"
  type        = bool
  default     = true
}

# Replication configuration
variable "replication_time_control_minutes" {
  description = "Replication Time Control (RTC) time in minutes for SLA-backed replication"
  type        = number
  default     = 15
  
  validation {
    condition     = var.replication_time_control_minutes >= 15
    error_message = "Replication Time Control must be at least 15 minutes."
  }
}

variable "enable_delete_marker_replication" {
  description = "Enable replication of delete markers"
  type        = bool
  default     = true
}

variable "destination_storage_class" {
  description = "Storage class for replicated objects in destination buckets"
  type        = string
  default     = "STANDARD_IA"
  
  validation {
    condition = contains([
      "STANDARD", "REDUCED_REDUNDANCY", "STANDARD_IA", "ONEZONE_IA",
      "INTELLIGENT_TIERING", "GLACIER", "DEEP_ARCHIVE", "GLACIER_IR"
    ], var.destination_storage_class)
    error_message = "Destination storage class must be a valid S3 storage class."
  }
}

# Monitoring configuration
variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "replication_failure_threshold" {
  description = "Threshold for replication failure alerts"
  type        = number
  default     = 10
}

variable "replication_latency_threshold" {
  description = "Threshold for replication latency alerts (in seconds)"
  type        = number
  default     = 900
}

# Security configuration
variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "enable_bucket_public_access_block" {
  description = "Enable S3 bucket public access block settings"
  type        = bool
  default     = true
}

variable "enable_ssl_requests_only" {
  description = "Enforce SSL/TLS requests only via bucket policy"
  type        = bool
  default     = true
}

# CloudTrail configuration
variable "enable_cloudtrail" {
  description = "Enable CloudTrail for audit logging"
  type        = bool
  default     = true
}

variable "cloudtrail_include_global_events" {
  description = "Include global service events in CloudTrail"
  type        = bool
  default     = true
}

# SNS configuration
variable "sns_email_endpoints" {
  description = "List of email addresses for SNS notifications"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.sns_email_endpoints : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All SNS email endpoints must be valid email addresses."
  }
}

# Lifecycle policy configuration
variable "transition_to_ia_days" {
  description = "Number of days before transitioning to Infrequent Access"
  type        = number
  default     = 30
  
  validation {
    condition     = var.transition_to_ia_days >= 1
    error_message = "Transition to IA days must be at least 1."
  }
}

variable "transition_to_glacier_days" {
  description = "Number of days before transitioning to Glacier"
  type        = number
  default     = 90
  
  validation {
    condition     = var.transition_to_glacier_days >= 1
    error_message = "Transition to Glacier days must be at least 1."
  }
}

variable "transition_to_deep_archive_days" {
  description = "Number of days before transitioning to Deep Archive"
  type        = number
  default     = 365
  
  validation {
    condition     = var.transition_to_deep_archive_days >= 90
    error_message = "Transition to Deep Archive days must be at least 90."
  }
}

variable "noncurrent_version_transition_ia_days" {
  description = "Number of days before transitioning non-current versions to IA"
  type        = number
  default     = 7
  
  validation {
    condition     = var.noncurrent_version_transition_ia_days >= 1
    error_message = "Non-current version transition to IA days must be at least 1."
  }
}

variable "noncurrent_version_transition_glacier_days" {
  description = "Number of days before transitioning non-current versions to Glacier"
  type        = number
  default     = 30
  
  validation {
    condition     = var.noncurrent_version_transition_glacier_days >= 1
    error_message = "Non-current version transition to Glacier days must be at least 1."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days before expiring non-current versions"
  type        = number
  default     = 365
  
  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "Non-current version expiration days must be at least 1."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}