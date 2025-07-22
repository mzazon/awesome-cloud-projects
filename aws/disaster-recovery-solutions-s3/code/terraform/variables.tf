# Variables for S3 Cross-Region Replication Disaster Recovery Solution
# This file defines all configurable parameters for the infrastructure

variable "primary_region" {
  description = "Primary AWS region for the source S3 bucket"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.primary_region))
    error_message = "Primary region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for the replica S3 bucket"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.secondary_region))
    error_message = "Secondary region must be a valid AWS region format (e.g., us-west-2)."
  }
  
  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "Secondary region must be different from primary region."
  }
}

variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["production", "staging", "development", "test"], var.environment)
    error_message = "Environment must be one of: production, staging, development, test."
  }
}

variable "cost_center" {
  description = "Cost center for resource tagging and billing"
  type        = string
  default     = "IT-DR"
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "disaster-recovery"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket names (random suffix will be added)"
  type        = string
  default     = "dr-bucket"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_lifecycle_policies" {
  description = "Enable lifecycle policies for cost optimization"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring and alarms for replication"
  type        = bool
  default     = true
}

variable "enable_sns_notifications" {
  description = "Enable SNS notifications for replication failures"
  type        = bool
  default     = true
}

variable "sns_email_endpoint" {
  description = "Email address for SNS notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.sns_email_endpoint == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sns_email_endpoint))
    error_message = "SNS email endpoint must be a valid email address or empty string."
  }
}

variable "replication_priority" {
  description = "Priority for replication rules (lower number = higher priority)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.replication_priority >= 1 && var.replication_priority <= 1000
    error_message = "Replication priority must be between 1 and 1000."
  }
}

variable "critical_data_prefix" {
  description = "S3 key prefix for critical data that requires faster replication"
  type        = string
  default     = "critical/"
}

variable "standard_data_prefix" {
  description = "S3 key prefix for standard data"
  type        = string
  default     = "standard/"
}

variable "archive_data_prefix" {
  description = "S3 key prefix for archive data"
  type        = string
  default     = "archive/"
}

variable "replica_storage_class" {
  description = "Storage class for replicated objects"
  type        = string
  default     = "STANDARD_IA"
  
  validation {
    condition = contains([
      "STANDARD", 
      "STANDARD_IA", 
      "ONEZONE_IA", 
      "REDUCED_REDUNDANCY",
      "GLACIER",
      "DEEP_ARCHIVE"
    ], var.replica_storage_class)
    error_message = "Replica storage class must be a valid S3 storage class."
  }
}

variable "critical_replica_storage_class" {
  description = "Storage class for critical replicated objects"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", 
      "STANDARD_IA", 
      "ONEZONE_IA", 
      "REDUCED_REDUNDANCY"
    ], var.critical_replica_storage_class)
    error_message = "Critical replica storage class must be a valid S3 storage class."
  }
}

variable "replication_latency_threshold" {
  description = "CloudWatch alarm threshold for replication latency (in seconds)"
  type        = number
  default     = 900
  
  validation {
    condition     = var.replication_latency_threshold >= 60
    error_message = "Replication latency threshold must be at least 60 seconds."
  }
}

variable "lifecycle_transition_days" {
  description = "Number of days before transitioning objects to IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_transition_days >= 1
    error_message = "Lifecycle transition days must be at least 1."
  }
}

variable "lifecycle_glacier_days" {
  description = "Number of days before transitioning objects to Glacier storage class"
  type        = number
  default     = 90
  
  validation {
    condition     = var.lifecycle_glacier_days >= 1
    error_message = "Lifecycle glacier days must be at least 1."
  }
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail for audit logging"
  type        = bool
  default     = true
}

variable "enable_server_side_encryption" {
  description = "Enable server-side encryption for S3 buckets"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "Number of days before KMS key deletion (7-30 days)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}