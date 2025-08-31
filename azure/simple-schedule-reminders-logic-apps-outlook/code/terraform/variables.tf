# variables.tf
# Input variables for the Azure Logic Apps schedule reminder solution
# These variables allow customization of the deployment

# Basic Azure configuration variables
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "South India", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = length(var.environment) <= 10 && can(regex("^[a-zA-Z][a-zA-Z0-9]*$", var.environment))
    error_message = "Environment must be alphanumeric, start with a letter, and be 10 characters or less."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "schedule-reminders"
  
  validation {
    condition     = length(var.project_name) <= 20 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name))
    error_message = "Project name must be alphanumeric with hyphens, start with a letter, and be 20 characters or less."
  }
}

# Logic App configuration variables
variable "logic_app_state" {
  description = "Initial state of the Logic App workflow (Enabled or Disabled)"
  type        = string
  default     = "Enabled"
  
  validation {
    condition     = contains(["Enabled", "Disabled"], var.logic_app_state)
    error_message = "Logic App state must be either 'Enabled' or 'Disabled'."
  }
}

# Email configuration variables
variable "email_recipient" {
  description = "Email address to receive the reminder notifications"
  type        = string
  default     = "user@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.email_recipient))
    error_message = "Email recipient must be a valid email address."
  }
}

variable "email_subject" {
  description = "Subject line for the reminder emails"
  type        = string
  default     = "Weekly Reminder - Team Meeting Today"
  
  validation {
    condition     = length(var.email_subject) > 0 && length(var.email_subject) <= 200
    error_message = "Email subject must be between 1 and 200 characters."
  }
}

variable "email_body" {
  description = "HTML body content for the reminder emails"
  type        = string
  default     = "<p>Hello Team,</p><p>This is your weekly reminder that we have our team meeting today at 2:00 PM.</p><p>Please prepare your weekly updates and join the meeting room.</p><p>Best regards,<br>Automated Reminder System</p>"
  
  validation {
    condition     = length(var.email_body) > 0 && length(var.email_body) <= 5000
    error_message = "Email body must be between 1 and 5000 characters."
  }
}

# Schedule configuration variables
variable "recurrence_frequency" {
  description = "Frequency of the recurrence trigger (Day, Week, Month, Year)"
  type        = string
  default     = "Week"
  
  validation {
    condition     = contains(["Day", "Week", "Month", "Year"], var.recurrence_frequency)
    error_message = "Recurrence frequency must be one of: Day, Week, Month, Year."
  }
}

variable "recurrence_interval" {
  description = "Interval for the recurrence (e.g., 1 for every week, 2 for every other week)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.recurrence_interval >= 1 && var.recurrence_interval <= 100
    error_message = "Recurrence interval must be between 1 and 100."
  }
}

variable "schedule_hours" {
  description = "List of hours (0-23) when the reminder should be sent"
  type        = list(number)
  default     = [9]
  
  validation {
    condition     = length(var.schedule_hours) > 0 && alltrue([for h in var.schedule_hours : h >= 0 && h <= 23])
    error_message = "Schedule hours must be a non-empty list of numbers between 0 and 23."
  }
}

variable "schedule_minutes" {
  description = "List of minutes (0-59) when the reminder should be sent"
  type        = list(number)
  default     = [0]
  
  validation {
    condition     = length(var.schedule_minutes) > 0 && alltrue([for m in var.schedule_minutes : m >= 0 && m <= 59])
    error_message = "Schedule minutes must be a non-empty list of numbers between 0 and 59."
  }
}

variable "schedule_weekdays" {
  description = "List of weekdays when the reminder should be sent (for weekly frequency)"
  type        = list(string)
  default     = ["Monday"]
  
  validation {
    condition = alltrue([
      for day in var.schedule_weekdays : contains([
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
      ], day)
    ])
    error_message = "Schedule weekdays must be valid day names: Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday."
  }
}

# Office 365 connection configuration
variable "office365_connection_name" {
  description = "Name for the Office 365 Outlook connection"
  type        = string
  default     = "office365-outlook"
  
  validation {
    condition     = length(var.office365_connection_name) > 0 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.office365_connection_name))
    error_message = "Office 365 connection name must be alphanumeric with hyphens and start with a letter."
  }
}

# Resource tagging variables
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.additional_tags) <= 15
    error_message = "Additional tags map cannot contain more than 15 entries."
  }
}

# Cost optimization variables
variable "integration_service_environment_id" {
  description = "Optional Integration Service Environment ID for dedicated Logic Apps hosting"
  type        = string
  default     = null
  
  validation {
    condition     = var.integration_service_environment_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Logic/integrationServiceEnvironments/[^/]+$", var.integration_service_environment_id))
    error_message = "Integration Service Environment ID must be a valid Azure resource ID or null."
  }
}

# Security and compliance variables
variable "workflow_access_control" {
  description = "Access control configuration for the Logic App workflow"
  type = object({
    contents = optional(object({
      allowed_caller_ip_address_ranges = optional(list(string), [])
    }), {})
    triggers = optional(object({
      allowed_caller_ip_address_ranges = optional(list(string), [])
    }), {})
    actions = optional(object({
      allowed_caller_ip_address_ranges = optional(list(string), [])
    }), {})
  })
  default = {}
  
  validation {
    condition = (
      var.workflow_access_control.contents == null ||
      length(var.workflow_access_control.contents.allowed_caller_ip_address_ranges) <= 20
    )
    error_message = "Contents allowed caller IP address ranges cannot exceed 20 entries."
  }
}