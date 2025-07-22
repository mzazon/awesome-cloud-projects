# Core configuration variables
variable "primary_region" {
  description = "Primary AWS region for source S3 bucket"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.primary_region))
    error_message = "Primary region must be a valid AWS region format."
  }
}

variable "dr_region" {
  description = "Disaster recovery AWS region for destination S3 bucket"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.dr_region))
    error_message = "DR region must be a valid AWS region format."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "test", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, test, prod."
  }
}

# S3 bucket configuration
variable "bucket_prefix" {
  description = "Prefix for S3 bucket names"
  type        = string
  default     = "dr"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_prefix))
    error_message = "Bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "source_bucket_name" {
  description = "Name for the source S3 bucket (leave empty to auto-generate)"
  type        = string
  default     = ""
}

variable "destination_bucket_name" {
  description = "Name for the destination S3 bucket (leave empty to auto-generate)"
  type        = string
  default     = ""
}

variable "replication_storage_class" {
  description = "Storage class for replicated objects in destination bucket"
  type        = string
  default     = "STANDARD_IA"
  
  validation {
    condition = contains([
      "STANDARD",
      "REDUCED_REDUNDANCY", 
      "STANDARD_IA",
      "ONEZONE_IA",
      "INTELLIGENT_TIERING",
      "GLACIER",
      "DEEP_ARCHIVE"
    ], var.replication_storage_class)
    error_message = "Storage class must be a valid S3 storage class."
  }
}

variable "replication_prefix" {
  description = "Prefix filter for objects to replicate (empty string replicates all objects)"
  type        = string
  default     = ""
}

# CloudTrail configuration
variable "enable_cloudtrail" {
  description = "Enable CloudTrail logging for S3 operations"
  type        = bool
  default     = true
}

variable "cloudtrail_log_prefix" {
  description = "Prefix for CloudTrail logs in S3"
  type        = string
  default     = "cloudtrail-logs"
}

# CloudWatch monitoring configuration
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for replication monitoring"
  type        = bool
  default     = true
}

variable "replication_latency_threshold" {
  description = "Threshold in seconds for replication latency alarm"
  type        = number
  default     = 900
  
  validation {
    condition     = var.replication_latency_threshold > 0
    error_message = "Replication latency threshold must be greater than 0."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate for CloudWatch alarms"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

# SNS notification configuration
variable "notification_email" {
  description = "Email address for CloudWatch alarm notifications (leave empty to skip SNS)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Resource naming configuration
variable "resource_name_suffix" {
  description = "Suffix to append to resource names (leave empty to auto-generate)"
  type        = string
  default     = ""
}

# Security configuration
variable "enable_bucket_encryption" {
  description = "Enable server-side encryption for S3 buckets"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for S3 bucket encryption (leave empty to use S3 managed keys)"
  type        = string
  default     = ""
}

variable "enable_public_access_block" {
  description = "Enable S3 public access block for buckets"
  type        = bool
  default     = true
}

variable "enable_bucket_notification" {
  description = "Enable S3 bucket notifications for replication events"
  type        = bool
  default     = false
}

# Lifecycle configuration
variable "enable_lifecycle_policies" {
  description = "Enable S3 lifecycle policies for cost optimization"
  type        = bool
  default     = true
}

variable "transition_to_ia_days" {
  description = "Number of days after which objects transition to IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.transition_to_ia_days >= 1
    error_message = "Transition to IA days must be at least 1."
  }
}

variable "transition_to_glacier_days" {
  description = "Number of days after which objects transition to Glacier storage class"
  type        = number
  default     = 90
  
  validation {
    condition     = var.transition_to_glacier_days >= 1
    error_message = "Transition to Glacier days must be at least 1."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}