# Variable Definitions for Azure Service Health Monitoring
# These variables allow customization of the service health monitoring solution

variable "resource_group_name" {
  description = "Name of the resource group for service health monitoring resources"
  type        = string
  default     = "rg-service-health"
  
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", "Central US", "North Central US", "South Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North", "Norway East", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "Southeast Asia", "East Asia", "Japan East", "Japan West",
      "Korea Central", "India Central", "Central India", "South India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "notification_email" {
  description = "Email address for service health notifications"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address format."
  }
}

variable "notification_phone" {
  description = "Phone number for SMS notifications (format: +1234567890)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_phone == "" || can(regex("^\\+[1-9]\\d{1,14}$", var.notification_phone))
    error_message = "Phone number must be in international format (e.g., +1234567890) or empty string."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production", "test"], var.environment)
    error_message = "Environment must be one of: development, staging, production, test."
  }
}

variable "enable_service_issues_alert" {
  description = "Enable alert rule for Azure service issues"
  type        = bool
  default     = true
}

variable "enable_planned_maintenance_alert" {
  description = "Enable alert rule for planned maintenance notifications"
  type        = bool
  default     = true
}

variable "enable_health_advisory_alert" {
  description = "Enable alert rule for health advisories"
  type        = bool
  default     = true
}

variable "enable_security_advisory_alert" {
  description = "Enable alert rule for security advisories"
  type        = bool
  default     = true
}

variable "action_group_short_name" {
  description = "Short name for the action group (max 12 characters)"
  type        = string
  default     = "SvcHealth"
  
  validation {
    condition     = length(var.action_group_short_name) <= 12 && length(var.action_group_short_name) >= 1
    error_message = "Action group short name must be between 1 and 12 characters."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose = "service-health-monitoring"
    ManagedBy = "terraform"
  }
}