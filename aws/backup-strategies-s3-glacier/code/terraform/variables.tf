# variables.tf
# Input variables for backup strategies with S3 and Glacier

variable "aws_region" {
  description = "Primary AWS region for backup infrastructure"
  type        = string
  default     = "us-east-1"
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1'."
  }
}

variable "dr_region" {
  description = "Disaster recovery AWS region for cross-region replication"
  type        = string
  default     = "us-west-2"
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.dr_region))
    error_message = "AWS region must be in the format 'us-west-2'."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "owner" {
  description = "Owner of the backup infrastructure"
  type        = string
  default     = "backup-team"
  validation {
    condition = length(var.owner) > 0
    error_message = "Owner must not be empty."
  }
}

variable "backup_bucket_prefix" {
  description = "Prefix for backup bucket name (suffix will be auto-generated)"
  type        = string
  default     = "backup-strategy"
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.backup_bucket_prefix))
    error_message = "Bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for disaster recovery"
  type        = bool
  default     = true
}

variable "enable_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering for cost optimization"
  type        = bool
  default     = true
}

variable "backup_schedule_daily" {
  description = "Cron expression for daily backup schedule (UTC)"
  type        = string
  default     = "cron(0 2 * * ? *)"
  validation {
    condition = can(regex("^cron\\(", var.backup_schedule_daily))
    error_message = "Backup schedule must be a valid cron expression."
  }
}

variable "backup_schedule_weekly" {
  description = "Cron expression for weekly backup schedule (UTC)"
  type        = string
  default     = "cron(0 1 ? * SUN *)"
  validation {
    condition = can(regex("^cron\\(", var.backup_schedule_weekly))
    error_message = "Backup schedule must be a valid cron expression."
  }
}

variable "lifecycle_transition_ia_days" {
  description = "Number of days before transitioning to Infrequent Access"
  type        = number
  default     = 30
  validation {
    condition = var.lifecycle_transition_ia_days >= 30
    error_message = "Transition to IA must be at least 30 days."
  }
}

variable "lifecycle_transition_glacier_days" {
  description = "Number of days before transitioning to Glacier"
  type        = number
  default     = 90
  validation {
    condition = var.lifecycle_transition_glacier_days >= 90
    error_message = "Transition to Glacier must be at least 90 days."
  }
}

variable "lifecycle_transition_deep_archive_days" {
  description = "Number of days before transitioning to Deep Archive"
  type        = number
  default     = 365
  validation {
    condition = var.lifecycle_transition_deep_archive_days >= 180
    error_message = "Transition to Deep Archive must be at least 180 days."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days to retain noncurrent object versions"
  type        = number
  default     = 2555
  validation {
    condition = var.noncurrent_version_expiration_days > 0
    error_message = "Noncurrent version expiration must be greater than 0."
  }
}

variable "notification_email" {
  description = "Email address for backup notifications (leave empty to skip email setup)"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Email must be a valid email address or empty."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 300
  validation {
    condition = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

variable "backup_alarm_threshold_failure" {
  description = "Threshold for backup failure alarm (number of failures)"
  type        = number
  default     = 1
  validation {
    condition = var.backup_alarm_threshold_failure > 0
    error_message = "Backup failure threshold must be greater than 0."
  }
}

variable "backup_alarm_threshold_duration" {
  description = "Threshold for backup duration alarm in seconds"
  type        = number
  default     = 600
  validation {
    condition = var.backup_alarm_threshold_duration > 0
    error_message = "Backup duration threshold must be greater than 0."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}