# ====================================
# GENERAL CONFIGURATION VARIABLES
# ====================================

variable "primary_region" {
  description = "The primary AWS region where backup resources will be created"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.primary_region))
    error_message = "Primary region must be a valid AWS region format (e.g., us-west-2)."
  }
}

variable "dr_region" {
  description = "The disaster recovery AWS region for cross-region backup replication"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.dr_region))
    error_message = "DR region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
  default     = "production"
  
  validation {
    condition = contains(["production", "staging", "development", "test"], var.environment)
    error_message = "Environment must be one of: production, staging, development, test."
  }
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "AWS-Backup-Solution"
    CreatedBy   = "Terraform"
    Purpose     = "Automated-Backup-Infrastructure"
  }
}

# ====================================
# BACKUP VAULT CONFIGURATION
# ====================================

variable "backup_vault_prefix" {
  description = "Prefix for the primary backup vault name"
  type        = string
  default     = "enterprise-backup-vault"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]{1,50}$", var.backup_vault_prefix))
    error_message = "Backup vault prefix must be 1-50 characters and contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "dr_backup_vault_prefix" {
  description = "Prefix for the disaster recovery backup vault name"
  type        = string
  default     = "dr-backup-vault"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]{1,50}$", var.dr_backup_vault_prefix))
    error_message = "DR backup vault prefix must be 1-50 characters and contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "enable_backup_vault_lock" {
  description = "Enable backup vault lock for immutable backups (compliance mode)"
  type        = bool
  default     = false
}

variable "backup_vault_lock_changeable_days" {
  description = "Number of days that vault lock configuration can be changed"
  type        = number
  default     = 3
  
  validation {
    condition = var.backup_vault_lock_changeable_days >= 3 && var.backup_vault_lock_changeable_days <= 36500
    error_message = "Backup vault lock changeable days must be between 3 and 36500."
  }
}

variable "backup_vault_lock_min_retention_days" {
  description = "Minimum retention period in days for backup vault lock"
  type        = number
  default     = 1
  
  validation {
    condition = var.backup_vault_lock_min_retention_days >= 1 && var.backup_vault_lock_min_retention_days <= 36500
    error_message = "Backup vault lock minimum retention days must be between 1 and 36500."
  }
}

variable "backup_vault_lock_max_retention_days" {
  description = "Maximum retention period in days for backup vault lock"
  type        = number
  default     = 36500
  
  validation {
    condition = var.backup_vault_lock_max_retention_days >= 1 && var.backup_vault_lock_max_retention_days <= 36500
    error_message = "Backup vault lock maximum retention days must be between 1 and 36500."
  }
}

# ====================================
# BACKUP PLAN CONFIGURATION
# ====================================

variable "backup_plan_prefix" {
  description = "Prefix for the backup plan name"
  type        = string
  default     = "enterprise-backup-plan"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]{1,50}$", var.backup_plan_prefix))
    error_message = "Backup plan prefix must be 1-50 characters and contain only alphanumeric characters, hyphens, and underscores."
  }
}

# Daily backup configuration
variable "daily_backup_schedule" {
  description = "Cron expression for daily backup schedule"
  type        = string
  default     = "cron(0 2 ? * * *)"
  
  validation {
    condition = can(regex("^cron\\(.*\\)$", var.daily_backup_schedule))
    error_message = "Daily backup schedule must be a valid cron expression in the format 'cron(...)'."
  }
}

variable "daily_backup_retention_days" {
  description = "Number of days to retain daily backups"
  type        = number
  default     = 30
  
  validation {
    condition = var.daily_backup_retention_days >= 1 && var.daily_backup_retention_days <= 36500
    error_message = "Daily backup retention days must be between 1 and 36500."
  }
}

# Weekly backup configuration
variable "weekly_backup_schedule" {
  description = "Cron expression for weekly backup schedule"
  type        = string
  default     = "cron(0 3 ? * SUN *)"
  
  validation {
    condition = can(regex("^cron\\(.*\\)$", var.weekly_backup_schedule))
    error_message = "Weekly backup schedule must be a valid cron expression in the format 'cron(...)'."
  }
}

variable "weekly_backup_retention_days" {
  description = "Number of days to retain weekly backups"
  type        = number
  default     = 90
  
  validation {
    condition = var.weekly_backup_retention_days >= 1 && var.weekly_backup_retention_days <= 36500
    error_message = "Weekly backup retention days must be between 1 and 36500."
  }
}

# Monthly backup configuration
variable "monthly_backup_schedule" {
  description = "Cron expression for monthly backup schedule"
  type        = string
  default     = "cron(0 4 1 * ? *)"
  
  validation {
    condition = can(regex("^cron\\(.*\\)$", var.monthly_backup_schedule))
    error_message = "Monthly backup schedule must be a valid cron expression in the format 'cron(...)'."
  }
}

variable "monthly_backup_retention_days" {
  description = "Number of days to retain monthly backups"
  type        = number
  default     = 365
  
  validation {
    condition = var.monthly_backup_retention_days >= 1 && var.monthly_backup_retention_days <= 36500
    error_message = "Monthly backup retention days must be between 1 and 36500."
  }
}

# Backup window configuration
variable "backup_start_window_minutes" {
  description = "Start window in minutes for backup jobs"
  type        = number
  default     = 60
  
  validation {
    condition = var.backup_start_window_minutes >= 60 && var.backup_start_window_minutes <= 1440
    error_message = "Backup start window must be between 60 and 1440 minutes."
  }
}

variable "backup_completion_window_minutes" {
  description = "Completion window in minutes for daily backup jobs"
  type        = number
  default     = 120
  
  validation {
    condition = var.backup_completion_window_minutes >= 120 && var.backup_completion_window_minutes <= 1440
    error_message = "Backup completion window must be between 120 and 1440 minutes."
  }
}

variable "weekly_backup_completion_window_minutes" {
  description = "Completion window in minutes for weekly backup jobs"
  type        = number
  default     = 240
  
  validation {
    condition = var.weekly_backup_completion_window_minutes >= 120 && var.weekly_backup_completion_window_minutes <= 1440
    error_message = "Weekly backup completion window must be between 120 and 1440 minutes."
  }
}

variable "monthly_backup_completion_window_minutes" {
  description = "Completion window in minutes for monthly backup jobs"
  type        = number
  default     = 360
  
  validation {
    condition = var.monthly_backup_completion_window_minutes >= 120 && var.monthly_backup_completion_window_minutes <= 1440
    error_message = "Monthly backup completion window must be between 120 and 1440 minutes."
  }
}

variable "enable_continuous_backup" {
  description = "Enable continuous backup for supported resources"
  type        = bool
  default     = true
}

# ====================================
# BACKUP SELECTION CONFIGURATION
# ====================================

variable "backup_exclusion_resources" {
  description = "List of resource ARNs to exclude from backup"
  type        = list(string)
  default     = []
}

# ====================================
# IAM CONFIGURATION
# ====================================

variable "backup_service_role_name" {
  description = "Name for the AWS Backup service role"
  type        = string
  default     = "AWSBackupDefaultServiceRole"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.backup_service_role_name))
    error_message = "Backup service role name must be 1-64 characters and contain only alphanumeric characters and +=,.@_- symbols."
  }
}

# ====================================
# ENCRYPTION CONFIGURATION
# ====================================

variable "kms_deletion_window_days" {
  description = "Number of days to wait before deleting KMS keys"
  type        = number
  default     = 10
  
  validation {
    condition = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

# ====================================
# MONITORING AND NOTIFICATIONS
# ====================================

variable "sns_topic_prefix" {
  description = "Prefix for the SNS topic name"
  type        = string
  default     = "backup-notifications"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]{1,50}$", var.sns_topic_prefix))
    error_message = "SNS topic prefix must be 1-50 characters and contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "notification_email" {
  description = "Email address for backup notifications (leave empty to disable email notifications)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "backup_vault_events" {
  description = "List of backup vault events to send notifications for"
  type        = list(string)
  default = [
    "BACKUP_JOB_STARTED",
    "BACKUP_JOB_COMPLETED",
    "BACKUP_JOB_FAILED",
    "RESTORE_JOB_STARTED",
    "RESTORE_JOB_COMPLETED",
    "RESTORE_JOB_FAILED",
    "COPY_JOB_STARTED",
    "COPY_JOB_SUCCESSFUL",
    "COPY_JOB_FAILED"
  ]
  
  validation {
    condition = length(var.backup_vault_events) > 0
    error_message = "At least one backup vault event must be specified."
  }
}

variable "backup_storage_threshold_bytes" {
  description = "Threshold in bytes for backup storage usage alarm"
  type        = number
  default     = 107374182400  # 100GB in bytes
  
  validation {
    condition = var.backup_storage_threshold_bytes > 0
    error_message = "Backup storage threshold must be greater than 0."
  }
}

# ====================================
# REPORTING CONFIGURATION
# ====================================

variable "enable_backup_reporting" {
  description = "Enable AWS Backup reporting functionality"
  type        = bool
  default     = true
}

variable "s3_reports_bucket_prefix" {
  description = "Prefix for the S3 bucket that stores backup reports"
  type        = string
  default     = "aws-backup-reports"
  
  validation {
    condition = can(regex("^[a-z0-9-]{3,50}$", var.s3_reports_bucket_prefix))
    error_message = "S3 reports bucket prefix must be 3-50 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

# ====================================
# COMPLIANCE CONFIGURATION
# ====================================

variable "enable_config_compliance" {
  description = "Enable AWS Config compliance rules for backup monitoring"
  type        = bool
  default     = false
}

variable "config_required_frequency_value" {
  description = "Required backup frequency value for Config compliance rule"
  type        = string
  default     = "1"
  
  validation {
    condition = can(regex("^[0-9]+$", var.config_required_frequency_value))
    error_message = "Config required frequency value must be a numeric string."
  }
}

variable "config_required_retention_days" {
  description = "Required backup retention days for Config compliance rule"
  type        = string
  default     = "35"
  
  validation {
    condition = can(regex("^[0-9]+$", var.config_required_retention_days))
    error_message = "Config required retention days must be a numeric string."
  }
}

variable "config_required_frequency_unit" {
  description = "Required backup frequency unit for Config compliance rule"
  type        = string
  default     = "days"
  
  validation {
    condition = contains(["hours", "days", "weeks", "months"], var.config_required_frequency_unit)
    error_message = "Config required frequency unit must be one of: hours, days, weeks, months."
  }
}

# ====================================
# RESTORE TESTING CONFIGURATION
# ====================================

variable "enable_restore_testing" {
  description = "Enable automated restore testing functionality"
  type        = bool
  default     = false
}

variable "restore_testing_schedule" {
  description = "Cron expression for automated restore testing schedule"
  type        = string
  default     = "cron(0 4 ? * MON *)"
  
  validation {
    condition = can(regex("^cron\\(.*\\)$", var.restore_testing_schedule))
    error_message = "Restore testing schedule must be a valid cron expression in the format 'cron(...)'."
  }
}

variable "restore_testing_selection_window_days" {
  description = "Number of days to look back for recovery points in restore testing"
  type        = number
  default     = 7
  
  validation {
    condition = var.restore_testing_selection_window_days >= 1 && var.restore_testing_selection_window_days <= 365
    error_message = "Restore testing selection window days must be between 1 and 365."
  }
}