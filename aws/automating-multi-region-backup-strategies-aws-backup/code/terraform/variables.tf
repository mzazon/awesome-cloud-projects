# Variables for AWS Multi-Region Backup Strategy
# These variables configure the backup infrastructure across multiple regions
# with customizable retention, scheduling, and notification settings

# Organization and environment configuration
variable "organization_name" {
  description = "Name of the organization for resource naming"
  type        = string
  default     = "example-corp"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.organization_name))
    error_message = "Organization name must contain only lowercase letters, numbers, and hyphens."
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

# Multi-region configuration
variable "primary_region" {
  description = "Primary AWS region for backup operations"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Secondary AWS region for backup replication"
  type        = string
  default     = "us-west-2"
}

variable "tertiary_region" {
  description = "Tertiary AWS region for long-term archival"
  type        = string
  default     = "eu-west-1"
}

# Backup plan configuration
variable "backup_plan_name" {
  description = "Name for the multi-region backup plan"
  type        = string
  default     = "multi-region-backup-plan"
}

variable "daily_backup_schedule" {
  description = "Cron expression for daily backup schedule (UTC)"
  type        = string
  default     = "cron(0 2 ? * * *)"  # Daily at 2 AM UTC
  
  validation {
    condition     = can(regex("^cron\\(.*\\)$", var.daily_backup_schedule))
    error_message = "Daily backup schedule must be a valid cron expression."
  }
}

variable "weekly_backup_schedule" {
  description = "Cron expression for weekly backup schedule (UTC)"
  type        = string
  default     = "cron(0 3 ? * SUN *)"  # Sunday at 3 AM UTC
  
  validation {
    condition     = can(regex("^cron\\(.*\\)$", var.weekly_backup_schedule))
    error_message = "Weekly backup schedule must be a valid cron expression."
  }
}

# Retention and lifecycle policies
variable "daily_retention_days" {
  description = "Number of days to retain daily backups"
  type        = number
  default     = 365
  
  validation {
    condition     = var.daily_retention_days >= 7 && var.daily_retention_days <= 35000
    error_message = "Daily retention must be between 7 and 35000 days."
  }
}

variable "weekly_retention_days" {
  description = "Number of days to retain weekly backups"
  type        = number
  default     = 2555  # ~7 years
  
  validation {
    condition     = var.weekly_retention_days >= 7 && var.weekly_retention_days <= 35000
    error_message = "Weekly retention must be between 7 and 35000 days."
  }
}

variable "cold_storage_after_days" {
  description = "Number of days after which backups move to cold storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.cold_storage_after_days >= 1
    error_message = "Cold storage transition must be at least 1 day."
  }
}

variable "weekly_cold_storage_after_days" {
  description = "Number of days after which weekly backups move to cold storage"
  type        = number
  default     = 90
  
  validation {
    condition     = var.weekly_cold_storage_after_days >= 1
    error_message = "Weekly cold storage transition must be at least 1 day."
  }
}

# Backup job configuration
variable "backup_start_window_minutes" {
  description = "The window in minutes during which the backup job can start"
  type        = number
  default     = 480  # 8 hours
  
  validation {
    condition     = var.backup_start_window_minutes >= 60 && var.backup_start_window_minutes <= 10080
    error_message = "Backup start window must be between 60 and 10080 minutes."
  }
}

variable "backup_completion_window_minutes" {
  description = "The window in minutes during which the backup job must complete"
  type        = number
  default     = 10080  # 7 days
  
  validation {
    condition     = var.backup_completion_window_minutes >= 120 && var.backup_completion_window_minutes <= 86400
    error_message = "Backup completion window must be between 120 and 86400 minutes."
  }
}

# Notification configuration
variable "notification_email" {
  description = "Email address for backup notifications"
  type        = string
  default     = "backup-admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "enable_sns_notifications" {
  description = "Enable SNS notifications for backup events"
  type        = bool
  default     = true
}

# Resource selection tags
variable "backup_resource_tags" {
  description = "Tags used to select resources for backup"
  type        = map(string)
  default = {
    BackupEnabled = "true"
    Environment   = "Production"
  }
}

# KMS encryption configuration
variable "enable_backup_encryption" {
  description = "Enable KMS encryption for backup vaults"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "Number of days to wait before KMS key deletion"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Lambda function configuration
variable "enable_backup_validation" {
  description = "Enable Lambda function for backup validation"
  type        = bool
  default     = true
}

variable "lambda_timeout" {
  description = "Timeout for Lambda backup validation function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

# Additional backup options
variable "enable_windows_vss" {
  description = "Enable Windows Volume Shadow Copy Service (VSS) for EC2 instances"
  type        = bool
  default     = false
}

variable "enable_backup_vault_lock" {
  description = "Enable backup vault lock for compliance"
  type        = bool
  default     = false
}

variable "backup_vault_lock_min_retention_days" {
  description = "Minimum retention days for backup vault lock"
  type        = number
  default     = 1
  
  validation {
    condition     = var.backup_vault_lock_min_retention_days >= 1
    error_message = "Minimum retention for vault lock must be at least 1 day."
  }
}