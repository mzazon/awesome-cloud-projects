# AWS Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
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

# S3 Bucket Configuration
variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket name (will be combined with random suffix)"
  type        = string
  default     = "data-archiving-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_server_side_encryption" {
  description = "Enable S3 bucket server-side encryption"
  type        = bool
  default     = true
}

# Lifecycle Policy Configuration
variable "document_ia_transition_days" {
  description = "Days to transition documents to Infrequent Access storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.document_ia_transition_days >= 30
    error_message = "Transition to IA must be at least 30 days."
  }
}

variable "document_glacier_transition_days" {
  description = "Days to transition documents to Glacier storage"
  type        = number
  default     = 90
  
  validation {
    condition     = var.document_glacier_transition_days >= 90
    error_message = "Transition to Glacier must be at least 90 days."
  }
}

variable "document_deep_archive_transition_days" {
  description = "Days to transition documents to Glacier Deep Archive storage"
  type        = number
  default     = 365
  
  validation {
    condition     = var.document_deep_archive_transition_days >= 180
    error_message = "Transition to Deep Archive must be at least 180 days."
  }
}

variable "log_ia_transition_days" {
  description = "Days to transition logs to Infrequent Access storage"
  type        = number
  default     = 7
  
  validation {
    condition     = var.log_ia_transition_days >= 1
    error_message = "Log IA transition must be at least 1 day."
  }
}

variable "log_glacier_transition_days" {
  description = "Days to transition logs to Glacier storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_glacier_transition_days >= 30
    error_message = "Log Glacier transition must be at least 30 days."
  }
}

variable "log_expiration_days" {
  description = "Days after which to delete log files (7 years)"
  type        = number
  default     = 2555
  
  validation {
    condition     = var.log_expiration_days > 0
    error_message = "Log expiration must be greater than 0 days."
  }
}

variable "backup_ia_transition_days" {
  description = "Days to transition backups to Infrequent Access storage"
  type        = number
  default     = 1
  
  validation {
    condition     = var.backup_ia_transition_days >= 1
    error_message = "Backup IA transition must be at least 1 day."
  }
}

variable "backup_glacier_transition_days" {
  description = "Days to transition backups to Glacier storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_glacier_transition_days >= 30
    error_message = "Backup Glacier transition must be at least 30 days."
  }
}

# Monitoring Configuration
variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "storage_cost_threshold" {
  description = "CloudWatch alarm threshold for storage costs in USD"
  type        = number
  default     = 10.0
  
  validation {
    condition     = var.storage_cost_threshold > 0
    error_message = "Storage cost threshold must be greater than 0."
  }
}

variable "object_count_threshold" {
  description = "CloudWatch alarm threshold for object count"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.object_count_threshold > 0
    error_message = "Object count threshold must be greater than 0."
  }
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications (optional)"
  type        = string
  default     = ""
}

# Analytics and Reporting Configuration
variable "enable_s3_analytics" {
  description = "Enable S3 Analytics for storage class analysis"
  type        = bool
  default     = true
}

variable "enable_s3_inventory" {
  description = "Enable S3 Inventory for storage tracking"
  type        = bool
  default     = true
}

variable "inventory_frequency" {
  description = "S3 Inventory report frequency (Daily or Weekly)"
  type        = string
  default     = "Daily"
  
  validation {
    condition     = contains(["Daily", "Weekly"], var.inventory_frequency)
    error_message = "Inventory frequency must be either Daily or Weekly."
  }
}

# Intelligent Tiering Configuration
variable "enable_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering for media files"
  type        = bool
  default     = true
}

variable "intelligent_tiering_archive_days" {
  description = "Days to move to Archive Access tier in Intelligent Tiering"
  type        = number
  default     = 90
  
  validation {
    condition     = var.intelligent_tiering_archive_days >= 90
    error_message = "Archive Access transition must be at least 90 days."
  }
}

variable "intelligent_tiering_deep_archive_days" {
  description = "Days to move to Deep Archive Access tier in Intelligent Tiering"
  type        = number
  default     = 180
  
  validation {
    condition     = var.intelligent_tiering_deep_archive_days >= 180
    error_message = "Deep Archive Access transition must be at least 180 days."
  }
}

# IAM Configuration
variable "create_lifecycle_role" {
  description = "Create IAM role for lifecycle management"
  type        = bool
  default     = true
}

variable "lifecycle_role_name" {
  description = "Name for the lifecycle management IAM role"
  type        = string
  default     = "S3LifecycleRole"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_+=,.@-]*$", var.lifecycle_role_name))
    error_message = "Role name must start with a letter and contain only alphanumeric characters and +=,.@-_ characters."
  }
}