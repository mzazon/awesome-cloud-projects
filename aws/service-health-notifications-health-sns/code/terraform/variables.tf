# Variables for AWS Health Notifications Infrastructure
# This file defines all configurable parameters for the health notification system

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters and hyphens."
  }
}

variable "notification_email" {
  description = "Email address to receive AWS Health notifications"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "aws-health-notifications"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "sns_display_name" {
  description = "Display name for the SNS topic"
  type        = string
  default     = "AWS Health Notifications"
}

variable "eventbridge_rule_description" {
  description = "Description for the EventBridge rule"
  type        = string
  default     = "Monitor AWS Health events and send SNS notifications"
}

variable "create_email_subscription" {
  description = "Whether to create an email subscription to the SNS topic"
  type        = bool
  default     = true
}

variable "additional_email_addresses" {
  description = "Additional email addresses to subscribe to health notifications"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for email in var.additional_email_addresses :
      can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid."
  }
}

variable "enable_eventbridge_rule" {
  description = "Whether to enable the EventBridge rule immediately"
  type        = bool
  default     = true
}

variable "health_event_categories" {
  description = "List of AWS Health event categories to monitor (empty list monitors all)"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for category in var.health_event_categories :
      contains(["issue", "accountNotification", "scheduledChange", "investigation"], category)
    ])
    error_message = "Valid categories are: issue, accountNotification, scheduledChange, investigation."
  }
}

variable "health_event_status_codes" {
  description = "List of AWS Health event status codes to monitor (empty list monitors all)"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for status in var.health_event_status_codes :
      contains(["open", "upcoming", "closed"], status)
    ])
    error_message = "Valid status codes are: open, upcoming, closed."
  }
}

variable "resource_name_suffix" {
  description = "Optional suffix to append to resource names for uniqueness"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]*$", var.resource_name_suffix))
    error_message = "Resource name suffix must contain only alphanumeric characters and hyphens."
  }
}