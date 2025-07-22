# Input Variables for Automated Patching Infrastructure
# This file defines all configurable parameters for the patching solution

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "patch_group" {
  description = "Patch group name for organizing instances"
  type        = string
  default     = "Production"
  
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_-]*$", var.patch_group))
    error_message = "Patch group name must start with a letter and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "maintenance_window_schedule" {
  description = "Cron expression for maintenance window schedule (UTC)"
  type        = string
  default     = "cron(0 2 ? * SUN *)"
  
  validation {
    condition     = can(regex("^cron\\(", var.maintenance_window_schedule))
    error_message = "Maintenance window schedule must be a valid cron expression starting with 'cron('."
  }
}

variable "scan_window_schedule" {
  description = "Cron expression for patch scanning schedule (UTC)"
  type        = string
  default     = "cron(0 1 * * ? *)"
  
  validation {
    condition     = can(regex("^cron\\(", var.scan_window_schedule))
    error_message = "Scan window schedule must be a valid cron expression starting with 'cron('."
  }
}

variable "maintenance_window_duration" {
  description = "Duration in hours for maintenance window"
  type        = number
  default     = 4
  
  validation {
    condition     = var.maintenance_window_duration >= 1 && var.maintenance_window_duration <= 24
    error_message = "Maintenance window duration must be between 1 and 24 hours."
  }
}

variable "maintenance_window_cutoff" {
  description = "Cutoff time in hours before maintenance window ends"
  type        = number
  default     = 1
  
  validation {
    condition     = var.maintenance_window_cutoff >= 0 && var.maintenance_window_cutoff < var.maintenance_window_duration
    error_message = "Cutoff time must be less than the maintenance window duration."
  }
}

variable "scan_window_duration" {
  description = "Duration in hours for scan window"
  type        = number
  default     = 2
  
  validation {
    condition     = var.scan_window_duration >= 1 && var.scan_window_duration <= 24
    error_message = "Scan window duration must be between 1 and 24 hours."
  }
}

variable "patch_baseline_operating_system" {
  description = "Operating system for patch baseline"
  type        = string
  default     = "AMAZON_LINUX_2"
  
  validation {
    condition = contains([
      "AMAZON_LINUX", "AMAZON_LINUX_2", "AMAZON_LINUX_2022", "AMAZON_LINUX_2023",
      "UBUNTU", "REDHAT_ENTERPRISE_LINUX", "SUSE", "CENTOS", "ORACLE_LINUX",
      "DEBIAN", "MACOS", "RASPBIAN", "ROCKY_LINUX", "ALMA_LINUX", "WINDOWS"
    ], var.patch_baseline_operating_system)
    error_message = "Operating system must be a valid SSM-supported OS."
  }
}

variable "patch_classification_filters" {
  description = "List of patch classifications to include"
  type        = list(string)
  default     = ["Security", "Bugfix", "Critical"]
  
  validation {
    condition = alltrue([
      for filter in var.patch_classification_filters :
      contains(["Security", "Bugfix", "Critical", "Important", "Recommended", "Enhancement"], filter)
    ])
    error_message = "Patch classifications must be valid SSM classification types."
  }
}

variable "patch_approve_after_days" {
  description = "Number of days to wait before auto-approving patches"
  type        = number
  default     = 7
  
  validation {
    condition     = var.patch_approve_after_days >= 0 && var.patch_approve_after_days <= 100
    error_message = "Approve after days must be between 0 and 100."
  }
}

variable "patch_compliance_level" {
  description = "Compliance level for patches"
  type        = string
  default     = "CRITICAL"
  
  validation {
    condition     = contains(["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFORMATIONAL"], var.patch_compliance_level)
    error_message = "Compliance level must be one of: CRITICAL, HIGH, MEDIUM, LOW, INFORMATIONAL."
  }
}

variable "max_concurrency" {
  description = "Maximum percentage of instances to patch concurrently"
  type        = string
  default     = "50%"
  
  validation {
    condition     = can(regex("^[0-9]+%$", var.max_concurrency)) || can(regex("^[0-9]+$", var.max_concurrency))
    error_message = "Max concurrency must be a percentage (e.g., '50%') or absolute number (e.g., '10')."
  }
}

variable "max_errors" {
  description = "Maximum percentage of instances that can fail before stopping"
  type        = string
  default     = "10%"
  
  validation {
    condition     = can(regex("^[0-9]+%$", var.max_errors)) || can(regex("^[0-9]+$", var.max_errors))
    error_message = "Max errors must be a percentage (e.g., '10%') or absolute number (e.g., '5')."
  }
}

variable "scan_max_concurrency" {
  description = "Maximum percentage of instances to scan concurrently"
  type        = string
  default     = "100%"
  
  validation {
    condition     = can(regex("^[0-9]+%$", var.scan_max_concurrency)) || can(regex("^[0-9]+$", var.scan_max_concurrency))
    error_message = "Scan max concurrency must be a percentage (e.g., '100%') or absolute number (e.g., '50')."
  }
}

variable "scan_max_errors" {
  description = "Maximum percentage of instances that can fail scanning before stopping"
  type        = string
  default     = "5%"
  
  validation {
    condition     = can(regex("^[0-9]+%$", var.scan_max_errors)) || can(regex("^[0-9]+$", var.scan_max_errors))
    error_message = "Scan max errors must be a percentage (e.g., '5%') or absolute number (e.g., '2')."
  }
}

variable "target_tag_key" {
  description = "EC2 tag key for targeting instances"
  type        = string
  default     = "Environment"
  
  validation {
    condition     = length(var.target_tag_key) > 0 && length(var.target_tag_key) <= 127
    error_message = "Target tag key must be between 1 and 127 characters."
  }
}

variable "target_tag_value" {
  description = "EC2 tag value for targeting instances"
  type        = string
  default     = "Production"
  
  validation {
    condition     = length(var.target_tag_value) > 0 && length(var.target_tag_value) <= 255
    error_message = "Target tag value must be between 1 and 255 characters."
  }
}

variable "notification_email" {
  description = "Email address for patch notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_patch_compliance_monitoring" {
  description = "Enable CloudWatch monitoring for patch compliance"
  type        = bool
  default     = true
}

variable "s3_bucket_name" {
  description = "S3 bucket name for patch logs (leave empty for auto-generation)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.s3_bucket_name == "" || can(regex("^[a-z0-9.-]+$", var.s3_bucket_name))
    error_message = "S3 bucket name must contain only lowercase letters, numbers, hyphens, and dots."
  }
}

variable "resource_name_prefix" {
  description = "Prefix for resource names (leave empty for auto-generation)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.resource_name_prefix == "" || can(regex("^[a-zA-Z0-9-]+$", var.resource_name_prefix))
    error_message = "Resource name prefix must contain only letters, numbers, and hyphens."
  }
}