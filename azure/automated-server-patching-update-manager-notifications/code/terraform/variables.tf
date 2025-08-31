# Variable Definitions for Automated Server Patching with Update Manager
# This file defines input variables for customizing the deployment

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "patch-demo"
  
  validation {
    condition     = length(var.resource_prefix) <= 10 && can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must be 10 characters or less and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", "West Europe",
      "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment tag for resource organization (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "admin_username" {
  description = "Administrator username for the virtual machine"
  type        = string
  default     = "azureuser"
  
  validation {
    condition     = length(var.admin_username) >= 3 && length(var.admin_username) <= 20
    error_message = "Admin username must be between 3 and 20 characters."
  }
}

variable "admin_password" {
  description = "Administrator password for the virtual machine (should be complex)"
  type        = string
  default     = "TempPassword123!"
  sensitive   = true
  
  validation {
    condition     = length(var.admin_password) >= 12
    error_message = "Admin password must be at least 12 characters long."
  }
}

variable "vm_size" {
  description = "Size of the virtual machine for patching demonstration"
  type        = string
  default     = "Standard_B2s"
  
  validation {
    condition = contains([
      "Standard_B1s", "Standard_B1ms", "Standard_B2s", "Standard_B2ms",
      "Standard_D2s_v3", "Standard_D2s_v4", "Standard_D2s_v5",
      "Standard_E2s_v3", "Standard_E2s_v4", "Standard_E2s_v5"
    ], var.vm_size)
    error_message = "VM size must be a valid Azure VM size suitable for demonstration purposes."
  }
}

variable "notification_email" {
  description = "Email address for receiving patch deployment notifications"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "maintenance_window_start_time" {
  description = "Start time for maintenance window in ISO 8601 format (e.g., 2025-08-02T02:00:00)"
  type        = string
  default     = "2025-08-02T02:00:00"
  
  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}$", var.maintenance_window_start_time))
    error_message = "Maintenance window start time must be in ISO 8601 format (YYYY-MM-DDTHH:MM:SS)."
  }
}

variable "maintenance_window_duration" {
  description = "Duration of maintenance window in hours"
  type        = number
  default     = 2
  
  validation {
    condition     = var.maintenance_window_duration >= 1 && var.maintenance_window_duration <= 6
    error_message = "Maintenance window duration must be between 1 and 6 hours."
  }
}

variable "maintenance_window_time_zone" {
  description = "Time zone for maintenance window scheduling"
  type        = string
  default     = "Eastern Standard Time"
  
  validation {
    condition = contains([
      "Eastern Standard Time", "Central Standard Time", "Mountain Standard Time",
      "Pacific Standard Time", "UTC", "GMT Standard Time", "Central European Standard Time"
    ], var.maintenance_window_time_zone)
    error_message = "Time zone must be a valid Windows time zone identifier."
  }
}

variable "patch_classifications" {
  description = "List of Windows update classifications to include in patching"
  type        = list(string)
  default     = ["Critical", "Security", "Updates"]
  
  validation {
    condition = alltrue([
      for classification in var.patch_classifications :
      contains(["Critical", "Security", "Updates", "ServicePacks", "Tools", "FeaturePacks"], classification)
    ])
    error_message = "Patch classifications must be valid Windows Update classifications."
  }
}

variable "reboot_setting" {
  description = "Reboot behavior after patch installation (IfRequired, NeverReboot, AlwaysReboot)"
  type        = string
  default     = "IfRequired"
  
  validation {
    condition     = contains(["IfRequired", "NeverReboot", "AlwaysReboot"], var.reboot_setting)
    error_message = "Reboot setting must be one of: IfRequired, NeverReboot, AlwaysReboot."
  }
}

variable "maintenance_recurrence" {
  description = "Recurrence pattern for maintenance window (Day, Week, Month)"
  type        = string
  default     = "Week"
  
  validation {
    condition     = contains(["Day", "Week", "Month"], var.maintenance_recurrence)
    error_message = "Maintenance recurrence must be one of: Day, Week, Month."
  }
}

variable "maintenance_week_days" {
  description = "Days of the week for maintenance (applicable when recurrence is Week)"
  type        = list(string)
  default     = ["Saturday"]
  
  validation {
    condition = alltrue([
      for day in var.maintenance_week_days :
      contains(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"], day)
    ])
    error_message = "Week days must be valid day names."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "AutomatedPatching"
    ManagedBy   = "Terraform"
    Recipe      = "automated-server-patching-update-manager-notifications"
  }
}