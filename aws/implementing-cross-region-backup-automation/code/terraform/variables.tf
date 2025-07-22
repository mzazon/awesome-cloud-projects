# ==============================================================================
# Multi-Region Backup Strategies - Variables Configuration
# ==============================================================================
# This file defines all configurable parameters for the multi-region backup
# strategy implementation. Variables are organized by functional area and
# include validation rules to ensure proper configuration.
# ==============================================================================

# ==============================================================================
# Organization and Environment Configuration
# ==============================================================================

variable "organization_name" {
  description = "Name of the organization for resource naming and tagging"
  type        = string
  default     = "myorg"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.organization_name))
    error_message = "Organization name must contain only lowercase letters, numbers, and hyphens."
  }
  
  validation {
    condition     = length(var.organization_name) >= 2 && length(var.organization_name) <= 20
    error_message = "Organization name must be between 2 and 20 characters long."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and selection (e.g., production, staging, development)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["production", "staging", "development", "test"], var.environment)
    error_message = "Environment must be one of: production, staging, development, test."
  }
}

variable "project_name" {
  description = "Name of the project for resource organization"
  type        = string
  default     = "multi-region-backup"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# ==============================================================================
# Multi-Region Configuration
# ==============================================================================

variable "primary_region" {
  description = "Primary AWS region for backup operations and main infrastructure"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.primary_region))
    error_message = "Primary region must be a valid AWS region identifier."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for cross-region backup copies and disaster recovery"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.secondary_region))
    error_message = "Secondary region must be a valid AWS region identifier."
  }
}

variable "tertiary_region" {
  description = "Tertiary AWS region for long-term archival and extended backup retention"
  type        = string
  default     = "eu-west-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.tertiary_region))
    error_message = "Tertiary region must be a valid AWS region identifier."
  }
}

# ==============================================================================
# Backup Schedule Configuration
# ==============================================================================

variable "daily_backup_schedule" {
  description = "Cron expression for daily backup schedule (UTC timezone)"
  type        = string
  default     = "cron(0 2 * * ? *)"  # Daily at 2:00 AM UTC
  
  validation {
    condition     = can(regex("^cron\\(.*\\)$", var.daily_backup_schedule))
    error_message = "Daily backup schedule must be a valid cron expression starting with 'cron('."
  }
}

variable "weekly_backup_schedule" {
  description = "Cron expression for weekly backup schedule (UTC timezone)"
  type        = string
  default     = "cron(0 3 ? * SUN *)"  # Weekly on Sunday at 3:00 AM UTC
  
  validation {
    condition     = can(regex("^cron\\(.*\\)$", var.weekly_backup_schedule))
    error_message = "Weekly backup schedule must be a valid cron expression starting with 'cron('."
  }
}

variable "backup_start_window" {
  description = "Time window in minutes for backup jobs to start"
  type        = number
  default     = 480  # 8 hours
  
  validation {
    condition     = var.backup_start_window >= 60 && var.backup_start_window <= 1440
    error_message = "Backup start window must be between 60 and 1440 minutes (1 to 24 hours)."
  }
}

variable "backup_completion_window" {
  description = "Time window in minutes for backup jobs to complete"
  type        = number
  default     = 10080  # 7 days
  
  validation {
    condition     = var.backup_completion_window >= 120 && var.backup_completion_window <= 10080
    error_message = "Backup completion window must be between 120 and 10080 minutes (2 hours to 7 days)."
  }
}

# ==============================================================================
# Backup Retention and Lifecycle Configuration
# ==============================================================================

variable "daily_retention_days" {
  description = "Number of days to retain daily backups before deletion"
  type        = number
  default     = 365  # 1 year
  
  validation {
    condition     = var.daily_retention_days >= 1 && var.daily_retention_days <= 36500
    error_message = "Daily retention days must be between 1 and 36500 days (100 years)."
  }
}

variable "daily_cold_storage_days" {
  description = "Number of days after creation before moving daily backups to cold storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.daily_cold_storage_days >= 1 && var.daily_cold_storage_days <= 36500
    error_message = "Daily cold storage days must be between 1 and 36500 days."
  }
}

variable "weekly_retention_days" {
  description = "Number of days to retain weekly backups before deletion"
  type        = number
  default     = 2555  # 7 years
  
  validation {
    condition     = var.weekly_retention_days >= 1 && var.weekly_retention_days <= 36500
    error_message = "Weekly retention days must be between 1 and 36500 days (100 years)."
  }
}

variable "weekly_cold_storage_days" {
  description = "Number of days after creation before moving weekly backups to cold storage"
  type        = number
  default     = 90
  
  validation {
    condition     = var.weekly_cold_storage_days >= 1 && var.weekly_cold_storage_days <= 36500
    error_message = "Weekly cold storage days must be between 1 and 36500 days."
  }
}

# ==============================================================================
# Security and Encryption Configuration
# ==============================================================================

variable "kms_deletion_window" {
  description = "Number of days to wait before deleting KMS keys (7-30 days)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_deletion_window >= 7 && var.kms_deletion_window <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

variable "enable_backup_vault_lock" {
  description = "Enable AWS Backup Vault Lock for immutable backups (compliance requirement)"
  type        = bool
  default     = false
}

variable "vault_lock_min_retention_days" {
  description = "Minimum retention period for vault lock in days (only used if vault lock is enabled)"
  type        = number
  default     = 365
  
  validation {
    condition     = var.vault_lock_min_retention_days >= 1 && var.vault_lock_min_retention_days <= 36500
    error_message = "Vault lock minimum retention must be between 1 and 36500 days."
  }
}

variable "vault_lock_max_retention_days" {
  description = "Maximum retention period for vault lock in days (only used if vault lock is enabled)"
  type        = number
  default     = 36500  # 100 years
  
  validation {
    condition     = var.vault_lock_max_retention_days >= 1 && var.vault_lock_max_retention_days <= 36500
    error_message = "Vault lock maximum retention must be between 1 and 36500 days."
  }
}

# ==============================================================================
# Resource Selection and Tagging Configuration
# ==============================================================================

variable "backup_resource_tags" {
  description = "Map of tags that resources must have to be included in backup selection"
  type        = map(string)
  default = {
    Environment    = "production"
    BackupEnabled  = "true"
  }
}

variable "exclude_resource_tags" {
  description = "Map of tags that will exclude resources from backup selection"
  type        = map(string)
  default = {
    BackupEnabled = "false"
    Environment   = "test"
  }
}

variable "resource_types_to_backup" {
  description = "List of AWS resource types to include in backup selection (empty list means all supported types)"
  type        = list(string)
  default     = []
  
  # Common resource types that can be backed up by AWS Backup:
  # "EC2", "EBS", "RDS", "DynamoDB", "EFS", "FSx", "Storage Gateway", "Redshift", "Neptune"
}

# ==============================================================================
# Notification Configuration
# ==============================================================================

variable "notification_email" {
  description = "Email address for backup failure notifications (optional)"
  type        = string
  default     = null
  
  validation {
    condition = var.notification_email == null || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or null."
  }
}

variable "enable_slack_notifications" {
  description = "Enable Slack notifications for backup events"
  type        = bool
  default     = false
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (only used if Slack notifications are enabled)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "notification_events" {
  description = "List of backup events that should trigger notifications"
  type        = list(string)
  default     = ["BACKUP_JOB_FAILED", "BACKUP_JOB_ABORTED", "COPY_JOB_FAILED"]
  
  validation {
    condition = alltrue([
      for event in var.notification_events : contains([
        "BACKUP_JOB_STARTED", "BACKUP_JOB_COMPLETED", "BACKUP_JOB_FAILED", "BACKUP_JOB_ABORTED",
        "COPY_JOB_STARTED", "COPY_JOB_COMPLETED", "COPY_JOB_FAILED", "COPY_JOB_ABORTED",
        "RESTORE_JOB_STARTED", "RESTORE_JOB_COMPLETED", "RESTORE_JOB_FAILED"
      ], event)
    ])
    error_message = "All notification events must be valid AWS Backup event types."
  }
}

# ==============================================================================
# Lambda Function Configuration
# ==============================================================================

variable "lambda_runtime" {
  description = "Python runtime version for Lambda functions"
  type        = string
  default     = "python3.12"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds (15 minutes)."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_log_level" {
  description = "Log level for Lambda functions (DEBUG, INFO, WARNING, ERROR, CRITICAL)"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.lambda_log_level)
    error_message = "Lambda log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

# ==============================================================================
# Monitoring and Logging Configuration
# ==============================================================================

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch logs retention period."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for backup operations"
  type        = bool
  default     = true
}

variable "create_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard for backup monitoring"
  type        = bool
  default     = true
}

variable "dashboard_refresh_interval" {
  description = "CloudWatch dashboard auto-refresh interval in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.dashboard_refresh_interval >= 60 && var.dashboard_refresh_interval <= 3600
    error_message = "Dashboard refresh interval must be between 60 and 3600 seconds."
  }
}

# ==============================================================================
# Cost Optimization Configuration
# ==============================================================================

variable "enable_cost_allocation_tags" {
  description = "Enable cost allocation tags for backup resources"
  type        = bool
  default     = true
}

variable "cost_center" {
  description = "Cost center for billing and cost allocation"
  type        = string
  default     = ""
}

variable "budget_alert_threshold" {
  description = "Monthly budget threshold in USD for backup costs (0 to disable budget alerts)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.budget_alert_threshold >= 0
    error_message = "Budget alert threshold must be a non-negative number."
  }
}

variable "enable_intelligent_tiering" {
  description = "Enable intelligent tiering for backup storage optimization"
  type        = bool
  default     = true
}

# ==============================================================================
# Advanced Backup Configuration
# ==============================================================================

variable "enable_continuous_backup" {
  description = "Enable continuous backup for supported resources (Point-in-Time Recovery)"
  type        = bool
  default     = false
}

variable "backup_window_timezone" {
  description = "Timezone for backup schedule expressions"
  type        = string
  default     = "UTC"
  
  validation {
    condition = contains([
      "UTC", "US/Eastern", "US/Central", "US/Mountain", "US/Pacific",
      "Europe/London", "Europe/Paris", "Europe/Berlin", "Asia/Tokyo",
      "Asia/Singapore", "Australia/Sydney"
    ], var.backup_window_timezone)
    error_message = "Backup window timezone must be a valid timezone identifier."
  }
}

variable "enable_backup_reports" {
  description = "Enable AWS Backup reporting for compliance and auditing"
  type        = bool
  default     = true
}

variable "report_delivery_s3_bucket" {
  description = "S3 bucket name for backup report delivery (optional, will create if not specified)"
  type        = string
  default     = ""
}

# ==============================================================================
# Disaster Recovery Configuration
# ==============================================================================

variable "rpo_target_hours" {
  description = "Recovery Point Objective (RPO) target in hours for business continuity planning"
  type        = number
  default     = 24
  
  validation {
    condition     = var.rpo_target_hours >= 1 && var.rpo_target_hours <= 168
    error_message = "RPO target must be between 1 and 168 hours (1 week)."
  }
}

variable "rto_target_hours" {
  description = "Recovery Time Objective (RTO) target in hours for business continuity planning"
  type        = number
  default     = 4
  
  validation {
    condition     = var.rto_target_hours >= 1 && var.rto_target_hours <= 72
    error_message = "RTO target must be between 1 and 72 hours."
  }
}

variable "enable_cross_account_backup" {
  description = "Enable cross-account backup sharing for enhanced security"
  type        = bool
  default     = false
}

variable "backup_destination_account_ids" {
  description = "List of AWS account IDs for cross-account backup sharing"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for account_id in var.backup_destination_account_ids : can(regex("^[0-9]{12}$", account_id))
    ])
    error_message = "All account IDs must be 12-digit numbers."
  }
}

# ==============================================================================
# Resource Tagging
# ==============================================================================

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_resource_tagging" {
  description = "Enable automatic resource tagging for backup operations"
  type        = bool
  default     = true
}

# ==============================================================================
# Feature Flags
# ==============================================================================

variable "enable_backup_notifications" {
  description = "Enable backup event notifications"
  type        = bool
  default     = true
}

variable "enable_lambda_validation" {
  description = "Enable Lambda-based backup validation"
  type        = bool
  default     = true
}

variable "enable_eventbridge_monitoring" {
  description = "Enable EventBridge-based backup monitoring"
  type        = bool
  default     = true
}

variable "enable_multi_region_monitoring" {
  description = "Enable monitoring across all configured regions"
  type        = bool
  default     = true
}