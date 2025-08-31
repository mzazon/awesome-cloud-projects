# Variable definitions for website uptime monitoring infrastructure
# This file defines all configurable parameters for the monitoring solution

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "notification_email" {
  description = "Email address to receive uptime notifications (for documentation purposes)"
  type        = string
  default     = "admin@example.com"
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "websites_to_monitor" {
  description = "List of websites to monitor for uptime"
  type        = list(string)
  default = [
    "https://www.google.com",
    "https://www.github.com",
    "https://www.stackoverflow.com"
  ]
  validation {
    condition = length(var.websites_to_monitor) > 0 && length(var.websites_to_monitor) <= 10
    error_message = "Must specify between 1 and 10 websites to monitor."
  }
}

variable "uptime_check_period" {
  description = "How often to run uptime checks in seconds"
  type        = number
  default     = 60
  validation {
    condition = contains([60, 300, 600, 900], var.uptime_check_period)
    error_message = "Uptime check period must be one of: 60, 300, 600, or 900 seconds."
  }
}

variable "uptime_check_timeout" {
  description = "Timeout for uptime checks in seconds"
  type        = number
  default     = 10
  validation {
    condition = var.uptime_check_timeout >= 1 && var.uptime_check_timeout <= 60
    error_message = "Uptime check timeout must be between 1 and 60 seconds."
  }
}

variable "checker_regions" {
  description = "List of regions to run uptime checks from"
  type        = list(string)
  default = [
    "usa",
    "europe",
    "asia_pacific"
  ]
  validation {
    condition = length(var.checker_regions) >= 1 && length(var.checker_regions) <= 6
    error_message = "Must specify between 1 and 6 checker regions."
  }
}

variable "alert_threshold_count" {
  description = "Number of failed checks from different regions before triggering alert"
  type        = number
  default     = 1
  validation {
    condition = var.alert_threshold_count >= 1 && var.alert_threshold_count <= 5
    error_message = "Alert threshold count must be between 1 and 5."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 256
  validation {
    condition = contains([128, 256, 512, 1024, 2048], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, or 2048 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 60
  validation {
    condition = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of Cloud Function instances"
  type        = number
  default     = 10
  validation {
    condition = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function max instances must be between 1 and 1000."
  }
}

variable "auto_close_duration" {
  description = "Duration in seconds after which to automatically close resolved alerts"
  type        = number
  default     = 1800
  validation {
    condition = var.auto_close_duration >= 300 && var.auto_close_duration <= 86400
    error_message = "Auto close duration must be between 300 and 86400 seconds (5 minutes to 24 hours)."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "uptime-monitor"
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "monitoring"
    purpose     = "uptime-checks"
    managed-by  = "terraform"
  }
  validation {
    condition = length(var.labels) <= 64
    error_message = "Maximum of 64 labels can be applied to resources."
  }
}