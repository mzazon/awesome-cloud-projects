# =====================================================
# Variables for Simple Business Notifications Infrastructure
# =====================================================
# This file defines all configurable variables for the
# EventBridge Scheduler and SNS notification system.

# =====================================================
# General Configuration Variables
# =====================================================

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "BusinessNotifications"
    ManagedBy   = "Terraform"
    Purpose     = "AutomatedNotifications"
    CostCenter  = "IT-Operations"
  }
}

# =====================================================
# SNS Configuration Variables
# =====================================================

variable "topic_name_prefix" {
  description = "Prefix for SNS topic name (suffix will be auto-generated)"
  type        = string
  default     = "business-notifications"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.topic_name_prefix))
    error_message = "Topic name prefix can only contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "sns_display_name" {
  description = "Display name for the SNS topic"
  type        = string
  default     = "Business Notifications"
}

variable "notification_emails" {
  description = "List of email addresses to subscribe to business notifications"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for email in var.notification_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid email format."
  }
}

variable "notification_phone_numbers" {
  description = "List of phone numbers for SMS notifications (format: +1234567890)"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for phone in var.notification_phone_numbers : can(regex("^\\+[1-9]\\d{10,14}$", phone))
    ])
    error_message = "Phone numbers must be in international format starting with + and containing 10-15 digits."
  }
}

variable "email_filter_policy" {
  description = "Optional filter policy for email subscriptions (JSON object)"
  type        = map(list(string))
  default     = null
}

variable "enable_sqs_integration" {
  description = "Enable SQS queue integration for system processing"
  type        = bool
  default     = false
}

variable "enable_dlq" {
  description = "Enable dead letter queue for failed message deliveries"
  type        = bool
  default     = true
}

# =====================================================
# EventBridge Scheduler Configuration Variables
# =====================================================

variable "schedule_group_prefix" {
  description = "Prefix for EventBridge Scheduler group name"
  type        = string
  default     = "business-schedules"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.schedule_group_prefix))
    error_message = "Schedule group prefix can only contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "scheduler_role_prefix" {
  description = "Prefix for EventBridge Scheduler IAM role name"
  type        = string
  default     = "eventbridge-scheduler-role"
}

variable "schedules_enabled" {
  description = "Enable or disable all schedules"
  type        = bool
  default     = true
}

variable "schedule_timezone" {
  description = "Timezone for schedule expressions (e.g., America/New_York)"
  type        = string
  default     = "America/New_York"
  validation {
    condition = contains([
      "America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles",
      "America/Phoenix", "America/Anchorage", "Pacific/Honolulu", "UTC",
      "Europe/London", "Europe/Paris", "Europe/Berlin", "Europe/Rome",
      "Asia/Tokyo", "Asia/Shanghai", "Asia/Kolkata", "Australia/Sydney"
    ], var.schedule_timezone)
    error_message = "Please use a valid timezone identifier."
  }
}

# =====================================================
# Schedule Expression Variables
# =====================================================

variable "daily_schedule_expression" {
  description = "Cron expression for daily business reports (default: 9 AM weekdays)"
  type        = string
  default     = "cron(0 9 ? * MON-FRI *)"
  validation {
    condition     = can(regex("^cron\\(.*\\)$", var.daily_schedule_expression))
    error_message = "Schedule expression must be a valid cron expression in the format cron(fields)."
  }
}

variable "weekly_schedule_expression" {
  description = "Cron expression for weekly summaries (default: Monday 8 AM)"
  type        = string
  default     = "cron(0 8 ? * MON *)"
  validation {
    condition     = can(regex("^cron\\(.*\\)$", var.weekly_schedule_expression))
    error_message = "Schedule expression must be a valid cron expression in the format cron(fields)."
  }
}

variable "monthly_schedule_expression" {
  description = "Cron expression for monthly reminders (default: 1st of month 10 AM)"
  type        = string
  default     = "cron(0 10 1 * ? *)"
  validation {
    condition     = can(regex("^cron\\(.*\\)$", var.monthly_schedule_expression))
    error_message = "Schedule expression must be a valid cron expression in the format cron(fields)."
  }
}

# =====================================================
# Flexible Time Window Variables
# =====================================================

variable "daily_flexible_window_minutes" {
  description = "Flexible time window for daily notifications (minutes)"
  type        = number
  default     = 15
  validation {
    condition     = var.daily_flexible_window_minutes >= 1 && var.daily_flexible_window_minutes <= 60
    error_message = "Flexible time window must be between 1 and 60 minutes."
  }
}

variable "weekly_flexible_window_minutes" {
  description = "Flexible time window for weekly notifications (minutes)"
  type        = number
  default     = 30
  validation {
    condition     = var.weekly_flexible_window_minutes >= 1 && var.weekly_flexible_window_minutes <= 60
    error_message = "Flexible time window must be between 1 and 60 minutes."
  }
}

# =====================================================
# Notification Message Content Variables
# =====================================================

variable "daily_notification_subject" {
  description = "Subject line for daily business report notifications"
  type        = string
  default     = "Daily Business Report - Ready for Review"
}

variable "daily_notification_message" {
  description = "Message content for daily business report notifications"
  type        = string
  default     = "Good morning! Your daily business report is ready for review. Please check the dashboard for key metrics including sales performance, customer engagement, and operational status. Have a great day!"
}

variable "weekly_notification_subject" {
  description = "Subject line for weekly business summary notifications"
  type        = string
  default     = "Weekly Business Summary - New Week Ahead"
}

variable "weekly_notification_message" {
  description = "Message content for weekly business summary notifications"
  type        = string
  default     = "Good Monday morning! Here is your weekly business summary with key achievements from last week and priorities for the week ahead. Review the quarterly goals progress and upcoming milestones. Let us make this week productive!"
}

variable "monthly_notification_subject" {
  description = "Subject line for monthly business reminder notifications"
  type        = string
  default     = "Monthly Business Reminder - Important Tasks"
}

variable "monthly_notification_message" {
  description = "Message content for monthly business reminder notifications"
  type        = string
  default     = "Welcome to a new month! This is your monthly reminder for important business tasks: review financial reports, update quarterly projections, conduct team performance reviews, and assess goal progress. Schedule time for strategic planning and process improvements."
}

# =====================================================
# CloudWatch Logging Variables
# =====================================================

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for EventBridge Scheduler"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch logs retention period in days"
  type        = number
  default     = 14
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

# =====================================================
# Advanced Configuration Variables
# =====================================================

variable "custom_message_attributes" {
  description = "Custom message attributes for advanced SNS filtering"
  type        = map(string)
  default     = {}
}

variable "enable_message_encryption" {
  description = "Enable server-side encryption for SNS messages"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for SNS topic encryption (optional, uses AWS managed key if not specified)"
  type        = string
  default     = null
}

variable "delivery_policy" {
  description = "Custom delivery policy for SNS topic (JSON string)"
  type        = string
  default     = null
}