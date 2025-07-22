# =============================================================================
# Input Variables for S3 Storage Cost Optimization
# =============================================================================
# This file defines all configurable variables for the S3 storage cost
# optimization solution, allowing customization of bucket settings, lifecycle
# policies, monitoring configurations, and cost management parameters.

# =============================================================================
# General Configuration Variables
# =============================================================================
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name (suffix will be auto-generated)"
  type        = string
  default     = "storage-optimization-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

# =============================================================================
# S3 Bucket Configuration Variables
# =============================================================================
variable "enable_versioning" {
  description = "Enable versioning for the S3 bucket"
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Allow Terraform to destroy the S3 bucket even if it contains objects"
  type        = bool
  default     = false
}

variable "create_sample_data" {
  description = "Create sample data objects to demonstrate lifecycle policies"
  type        = bool
  default     = true
}

# =============================================================================
# Storage Analytics Configuration Variables
# =============================================================================
variable "analytics_prefix" {
  description = "Prefix for objects to be analyzed by storage analytics"
  type        = string
  default     = "data/"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_/]+$", var.analytics_prefix))
    error_message = "Analytics prefix must contain only letters, numbers, hyphens, underscores, and forward slashes."
  }
}

variable "analytics_reports_prefix" {
  description = "Prefix for storage analytics reports"
  type        = string
  default     = "analytics-reports/"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_/]+$", var.analytics_reports_prefix))
    error_message = "Analytics reports prefix must contain only letters, numbers, hyphens, underscores, and forward slashes."
  }
}

# =============================================================================
# Intelligent Tiering Configuration Variables
# =============================================================================
variable "intelligent_tiering_archive_days" {
  description = "Number of days after which objects move to Archive Access tier"
  type        = number
  default     = 1
  
  validation {
    condition     = var.intelligent_tiering_archive_days >= 1
    error_message = "Archive access tier days must be at least 1."
  }
}

variable "intelligent_tiering_deep_archive_days" {
  description = "Number of days after which objects move to Deep Archive Access tier"
  type        = number
  default     = 90
  
  validation {
    condition     = var.intelligent_tiering_deep_archive_days >= 90
    error_message = "Deep archive access tier days must be at least 90."
  }
}

# =============================================================================
# Lifecycle Policy Configuration Variables
# =============================================================================
variable "frequently_accessed_ia_days" {
  description = "Days after which frequently accessed objects move to Standard-IA"
  type        = number
  default     = 30
  
  validation {
    condition     = var.frequently_accessed_ia_days >= 30
    error_message = "Standard-IA transition must be at least 30 days."
  }
}

variable "frequently_accessed_glacier_days" {
  description = "Days after which frequently accessed objects move to Glacier"
  type        = number
  default     = 90
  
  validation {
    condition     = var.frequently_accessed_glacier_days >= 90
    error_message = "Glacier transition must be at least 90 days."
  }
}

variable "infrequently_accessed_ia_days" {
  description = "Days after which infrequently accessed objects move to Standard-IA"
  type        = number
  default     = 1
  
  validation {
    condition     = var.infrequently_accessed_ia_days >= 1
    error_message = "Standard-IA transition must be at least 1 day."
  }
}

variable "infrequently_accessed_glacier_days" {
  description = "Days after which infrequently accessed objects move to Glacier"
  type        = number
  default     = 30
  
  validation {
    condition     = var.infrequently_accessed_glacier_days >= 30
    error_message = "Glacier transition must be at least 30 days."
  }
}

variable "infrequently_accessed_deep_archive_days" {
  description = "Days after which infrequently accessed objects move to Deep Archive"
  type        = number
  default     = 180
  
  validation {
    condition     = var.infrequently_accessed_deep_archive_days >= 180
    error_message = "Deep Archive transition must be at least 180 days."
  }
}

variable "archive_glacier_days" {
  description = "Days after which archive objects move to Glacier"
  type        = number
  default     = 1
  
  validation {
    condition     = var.archive_glacier_days >= 1
    error_message = "Glacier transition must be at least 1 day."
  }
}

variable "archive_deep_archive_days" {
  description = "Days after which archive objects move to Deep Archive"
  type        = number
  default     = 30
  
  validation {
    condition     = var.archive_deep_archive_days >= 30
    error_message = "Deep Archive transition must be at least 30 days."
  }
}

variable "cleanup_incomplete_uploads_days" {
  description = "Days after which incomplete multipart uploads are cleaned up"
  type        = number
  default     = 7
  
  validation {
    condition     = var.cleanup_incomplete_uploads_days >= 1
    error_message = "Cleanup days must be at least 1."
  }
}

# =============================================================================
# Budget Configuration Variables
# =============================================================================
variable "budget_limit_amount" {
  description = "Monthly budget limit for S3 storage costs (in USD)"
  type        = string
  default     = "50.00"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]{2}$", var.budget_limit_amount))
    error_message = "Budget limit must be a valid amount with two decimal places (e.g., 50.00)."
  }
}

variable "budget_alert_threshold" {
  description = "Percentage threshold for budget alerts (e.g., 80 for 80%)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.budget_alert_threshold > 0 && var.budget_alert_threshold <= 100
    error_message = "Budget alert threshold must be between 1 and 100."
  }
}

variable "budget_alert_emails" {
  description = "List of email addresses to receive budget alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.budget_alert_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All budget alert emails must be valid email addresses."
  }
}

variable "enable_forecasted_alerts" {
  description = "Enable forecasted budget alerts in addition to actual spending alerts"
  type        = bool
  default     = false
}

# =============================================================================
# Monitoring and Alerting Configuration Variables
# =============================================================================
variable "enable_enhanced_notifications" {
  description = "Enable enhanced notifications via SNS topic"
  type        = bool
  default     = false
}

variable "enable_storage_alarms" {
  description = "Enable CloudWatch alarms for storage size monitoring"
  type        = bool
  default     = false
}

variable "storage_size_alarm_threshold" {
  description = "Storage size threshold in bytes for CloudWatch alarm"
  type        = number
  default     = 1073741824  # 1 GB in bytes
  
  validation {
    condition     = var.storage_size_alarm_threshold > 0
    error_message = "Storage size alarm threshold must be greater than 0."
  }
}

# =============================================================================
# Dashboard Configuration Variables
# =============================================================================
variable "dashboard_widget_period" {
  description = "Period in seconds for dashboard metric widgets"
  type        = number
  default     = 86400  # 24 hours
  
  validation {
    condition     = contains([300, 900, 1800, 3600, 14400, 21600, 43200, 86400], var.dashboard_widget_period)
    error_message = "Dashboard widget period must be one of: 300, 900, 1800, 3600, 14400, 21600, 43200, or 86400 seconds."
  }
}

variable "dashboard_widget_stat" {
  description = "Statistic to display in dashboard widgets"
  type        = string
  default     = "Average"
  
  validation {
    condition     = contains(["Average", "Sum", "Maximum", "Minimum", "SampleCount"], var.dashboard_widget_stat)
    error_message = "Dashboard widget statistic must be one of: Average, Sum, Maximum, Minimum, or SampleCount."
  }
}

# =============================================================================
# Tagging Configuration Variables
# =============================================================================
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.additional_tags : can(regex("^[a-zA-Z0-9-_]+$", key))
    ])
    error_message = "Tag keys must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "cost_center" {
  description = "Cost center for resource allocation and billing"
  type        = string
  default     = ""
}

variable "owner" {
  description = "Owner of the resources for accountability"
  type        = string
  default     = ""
}

variable "project" {
  description = "Project name for resource organization"
  type        = string
  default     = "S3-Storage-Cost-Optimization"
}

# =============================================================================
# Advanced Configuration Variables
# =============================================================================
variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for disaster recovery"
  type        = bool
  default     = false
}

variable "replication_destination_bucket" {
  description = "Destination bucket for cross-region replication"
  type        = string
  default     = ""
}

variable "replication_destination_region" {
  description = "Destination region for cross-region replication"
  type        = string
  default     = ""
}

variable "enable_logging" {
  description = "Enable S3 access logging"
  type        = bool
  default     = false
}

variable "logging_target_bucket" {
  description = "Target bucket for S3 access logs"
  type        = string
  default     = ""
}

variable "logging_target_prefix" {
  description = "Prefix for S3 access logs"
  type        = string
  default     = "access-logs/"
}

# =============================================================================
# Lifecycle Policy Custom Configuration
# =============================================================================
variable "custom_lifecycle_rules" {
  description = "Custom lifecycle rules for specific use cases"
  type = map(object({
    prefix = string
    transitions = list(object({
      days          = number
      storage_class = string
    }))
    expiration_days = optional(number)
    noncurrent_version_expiration_days = optional(number)
  }))
  default = {}
}

# =============================================================================
# Cost Optimization Features
# =============================================================================
variable "enable_request_payer" {
  description = "Enable Requester Pays for the S3 bucket"
  type        = bool
  default     = false
}

variable "enable_transfer_acceleration" {
  description = "Enable S3 Transfer Acceleration"
  type        = bool
  default     = false
}

variable "storage_class_analysis_frequency" {
  description = "Frequency for storage class analysis (Daily or Weekly)"
  type        = string
  default     = "Daily"
  
  validation {
    condition     = contains(["Daily", "Weekly"], var.storage_class_analysis_frequency)
    error_message = "Storage class analysis frequency must be either 'Daily' or 'Weekly'."
  }
}