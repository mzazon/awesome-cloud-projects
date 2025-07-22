# ==============================================================================
# Variables for Automated Business Task Scheduling
# ==============================================================================

# General Configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Notification Configuration
variable "notification_email" {
  description = "Email address for SNS notifications (leave empty to skip email subscription)"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address or leave empty."
  }
}

# Schedule Configuration
variable "timezone" {
  description = "Timezone for schedule expressions (e.g., America/New_York, UTC, Europe/London)"
  type        = string
  default     = "America/New_York"
}

variable "daily_report_schedule" {
  description = "Cron expression for daily report generation (default: 9 AM daily)"
  type        = string
  default     = "cron(0 9 * * ? *)"
  validation {
    condition     = can(regex("^(cron|rate)\\(.*\\)$", var.daily_report_schedule))
    error_message = "Schedule expression must be a valid cron or rate expression."
  }
}

variable "hourly_processing_schedule" {
  description = "Rate expression for hourly data processing (default: every hour)"
  type        = string
  default     = "rate(1 hour)"
  validation {
    condition     = can(regex("^(cron|rate)\\(.*\\)$", var.hourly_processing_schedule))
    error_message = "Schedule expression must be a valid cron or rate expression."
  }
}

variable "weekly_notification_schedule" {
  description = "Cron expression for weekly notifications (default: Monday 10 AM)"
  type        = string
  default     = "cron(0 10 ? * MON *)"
  validation {
    condition     = can(regex("^(cron|rate)\\(.*\\)$", var.weekly_notification_schedule))
    error_message = "Schedule expression must be a valid cron or rate expression."
  }
}

# Feature Toggles
variable "schedules_enabled" {
  description = "Whether to enable the EventBridge schedules (set to false to disable all automation)"
  type        = bool
  default     = true
}

variable "enable_hourly_processing" {
  description = "Whether to create the hourly data processing schedule"
  type        = bool
  default     = true
}

variable "enable_weekly_notifications" {
  description = "Whether to create the weekly notification schedule"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Whether to create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

# Lambda Configuration
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Logging Configuration
variable "log_retention_days" {
  description = "CloudWatch logs retention period in days"
  type        = number
  default     = 30
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch log retention periods."
  }
}

# S3 Configuration
variable "enable_s3_lifecycle" {
  description = "Whether to enable S3 lifecycle policies for cost optimization"
  type        = bool
  default     = true
}

variable "s3_intelligent_tiering_days" {
  description = "Number of days before transitioning to Intelligent Tiering"
  type        = number
  default     = 30
  validation {
    condition     = var.s3_intelligent_tiering_days >= 1
    error_message = "S3 Intelligent Tiering transition days must be at least 1."
  }
}

variable "s3_glacier_transition_days" {
  description = "Number of days before transitioning to Glacier"
  type        = number
  default     = 90
  validation {
    condition     = var.s3_glacier_transition_days >= 1
    error_message = "S3 Glacier transition days must be at least 1."
  }
}

variable "s3_version_expiration_days" {
  description = "Number of days to keep old S3 object versions"
  type        = number
  default     = 365
  validation {
    condition     = var.s3_version_expiration_days >= 1
    error_message = "S3 version expiration days must be at least 1."
  }
}

# Security Configuration
variable "enable_s3_encryption" {
  description = "Whether to enable S3 server-side encryption"
  type        = bool
  default     = true
}

variable "enable_sns_encryption" {
  description = "Whether to enable SNS encryption with AWS managed keys"
  type        = bool
  default     = true
}

variable "lambda_tracing_mode" {
  description = "AWS X-Ray tracing mode for Lambda function (Active or PassThrough)"
  type        = string
  default     = "Active"
  validation {
    condition     = contains(["Active", "PassThrough"], var.lambda_tracing_mode)
    error_message = "Lambda tracing mode must be either 'Active' or 'PassThrough'."
  }
}

# Cost Optimization
variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda function (null for unreserved)"
  type        = number
  default     = null
  validation {
    condition     = var.lambda_reserved_concurrency == null || var.lambda_reserved_concurrency >= 0
    error_message = "Lambda reserved concurrency must be null or a non-negative integer."
  }
}

variable "enable_cost_tags" {
  description = "Whether to add additional cost tracking tags to resources"
  type        = bool
  default     = true
}

# Advanced Configuration
variable "scheduler_flexible_time_window_minutes" {
  description = "Flexible time window for schedule execution in minutes (null to disable)"
  type        = number
  default     = null
  validation {
    condition     = var.scheduler_flexible_time_window_minutes == null || (var.scheduler_flexible_time_window_minutes >= 1 && var.scheduler_flexible_time_window_minutes <= 1440)
    error_message = "Flexible time window must be null or between 1 and 1440 minutes."
  }
}

variable "retry_policy_max_attempts" {
  description = "Maximum number of retry attempts for failed schedule executions"
  type        = number
  default     = 3
  validation {
    condition     = var.retry_policy_max_attempts >= 0 && var.retry_policy_max_attempts <= 185
    error_message = "Maximum retry attempts must be between 0 and 185."
  }
}

variable "retry_policy_max_age_seconds" {
  description = "Maximum age of events in seconds for retry attempts"
  type        = number
  default     = 3600
  validation {
    condition     = var.retry_policy_max_age_seconds >= 60 && var.retry_policy_max_age_seconds <= 86400
    error_message = "Maximum event age must be between 60 and 86400 seconds (24 hours)."
  }
}

# Development and Testing
variable "enable_debug_logging" {
  description = "Whether to enable debug logging in Lambda function"
  type        = bool
  default     = false
}

variable "lambda_environment_variables" {
  description = "Additional environment variables for Lambda function"
  type        = map(string)
  default     = {}
}