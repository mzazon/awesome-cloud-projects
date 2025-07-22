# Core configuration variables
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "backup-archive-demo"
  
  validation {
    condition = length(var.project_name) > 0 && length(var.project_name) <= 30
    error_message = "Project name must be between 1 and 30 characters."
  }
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

# S3 configuration variables
variable "enable_versioning" {
  description = "Enable S3 bucket versioning for backup integrity"
  type        = bool
  default     = true
}

variable "enable_mfa_delete" {
  description = "Enable MFA delete protection for the S3 bucket"
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Allow force destruction of the bucket (use with caution in production)"
  type        = bool
  default     = false
}

# Lifecycle policy configuration variables
variable "backup_transition_to_ia_days" {
  description = "Number of days before transitioning backup data to Infrequent Access"
  type        = number
  default     = 30
  
  validation {
    condition = var.backup_transition_to_ia_days >= 1 && var.backup_transition_to_ia_days <= 365
    error_message = "Backup IA transition days must be between 1 and 365."
  }
}

variable "backup_transition_to_glacier_ir_days" {
  description = "Number of days before transitioning backup data to Glacier Instant Retrieval"
  type        = number
  default     = 90
  
  validation {
    condition = var.backup_transition_to_glacier_ir_days >= 1 && var.backup_transition_to_glacier_ir_days <= 365
    error_message = "Backup Glacier IR transition days must be between 1 and 365."
  }
}

variable "backup_transition_to_glacier_days" {
  description = "Number of days before transitioning backup data to Glacier Flexible Retrieval"
  type        = number
  default     = 365
  
  validation {
    condition = var.backup_transition_to_glacier_days >= 90 && var.backup_transition_to_glacier_days <= 3650
    error_message = "Backup Glacier transition days must be between 90 and 3650."
  }
}

variable "backup_transition_to_deep_archive_days" {
  description = "Number of days before transitioning backup data to Deep Archive"
  type        = number
  default     = 2555
  
  validation {
    condition = var.backup_transition_to_deep_archive_days >= 180 && var.backup_transition_to_deep_archive_days <= 3650
    error_message = "Backup Deep Archive transition days must be between 180 and 3650."
  }
}

variable "logs_transition_to_ia_days" {
  description = "Number of days before transitioning log data to Infrequent Access"
  type        = number
  default     = 7
  
  validation {
    condition = var.logs_transition_to_ia_days >= 1 && var.logs_transition_to_ia_days <= 365
    error_message = "Logs IA transition days must be between 1 and 365."
  }
}

variable "logs_expiration_days" {
  description = "Number of days before deleting log data"
  type        = number
  default     = 2555
  
  validation {
    condition = var.logs_expiration_days >= 1 && var.logs_expiration_days <= 3650
    error_message = "Logs expiration days must be between 1 and 3650."
  }
}

variable "documents_transition_to_glacier_ir_days" {
  description = "Number of days before transitioning document data to Glacier Instant Retrieval"
  type        = number
  default     = 60
  
  validation {
    condition = var.documents_transition_to_glacier_ir_days >= 1 && var.documents_transition_to_glacier_ir_days <= 365
    error_message = "Documents Glacier IR transition days must be between 1 and 365."
  }
}

variable "documents_transition_to_glacier_days" {
  description = "Number of days before transitioning document data to Glacier Flexible Retrieval"
  type        = number
  default     = 180
  
  validation {
    condition = var.documents_transition_to_glacier_days >= 90 && var.documents_transition_to_glacier_days <= 3650
    error_message = "Documents Glacier transition days must be between 90 and 3650."
  }
}

variable "documents_transition_to_deep_archive_days" {
  description = "Number of days before transitioning document data to Deep Archive"
  type        = number
  default     = 1095
  
  validation {
    condition = var.documents_transition_to_deep_archive_days >= 180 && var.documents_transition_to_deep_archive_days <= 3650
    error_message = "Documents Deep Archive transition days must be between 180 and 3650."
  }
}

# CloudWatch monitoring configuration
variable "enable_cost_monitoring" {
  description = "Enable CloudWatch cost monitoring and alerts"
  type        = bool
  default     = true
}

variable "cost_threshold_usd" {
  description = "Cost threshold in USD for CloudWatch billing alerts"
  type        = number
  default     = 50.0
  
  validation {
    condition = var.cost_threshold_usd > 0 && var.cost_threshold_usd <= 10000
    error_message = "Cost threshold must be between 0 and 10000 USD."
  }
}

variable "notification_email" {
  description = "Email address for cost alert notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Glacier data retrieval policy configuration
variable "glacier_retrieval_bytes_per_hour" {
  description = "Maximum bytes per hour for Glacier data retrieval (1GB = 1073741824 bytes)"
  type        = number
  default     = 1073741824
  
  validation {
    condition = var.glacier_retrieval_bytes_per_hour >= 0
    error_message = "Glacier retrieval bytes per hour must be non-negative."
  }
}

# Tagging configuration
variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "backup-archive-demo"
    Environment = "dev"
    ManagedBy   = "terraform"
    Purpose     = "backup-archiving"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}