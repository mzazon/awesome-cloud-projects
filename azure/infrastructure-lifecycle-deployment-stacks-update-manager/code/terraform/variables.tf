# Variables for Azure Infrastructure Lifecycle Management
# This file defines all configurable parameters for the deployment

variable "location" {
  description = "The Azure region where all resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Italy North", "Spain Central", "Israel Central", "UAE North",
      "South Africa North", "Australia East", "Australia Southeast",
      "Australia Central", "Japan East", "Japan West", "Korea Central",
      "Korea South", "Southeast Asia", "East Asia", "Central India",
      "South India", "West India", "Jio India West"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group where all resources will be created"
  type        = string
  default     = ""
  
  validation {
    condition     = var.resource_group_name == "" || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name can only contain alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "admin_username" {
  description = "Administrator username for virtual machines"
  type        = string
  default     = "azureuser"
  
  validation {
    condition     = length(var.admin_username) >= 1 && length(var.admin_username) <= 64
    error_message = "Admin username must be between 1 and 64 characters."
  }
}

variable "admin_password" {
  description = "Administrator password for virtual machines"
  type        = string
  sensitive   = true
  
  validation {
    condition     = can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[@$!%*?&])[A-Za-z\\d@$!%*?&]{12,}$", var.admin_password))
    error_message = "Password must be at least 12 characters with uppercase, lowercase, number, and special character."
  }
}

variable "vm_size" {
  description = "Size of the virtual machines in the scale set"
  type        = string
  default     = "Standard_B2s"
  
  validation {
    condition = contains([
      "Standard_B1s", "Standard_B1ms", "Standard_B2s", "Standard_B2ms",
      "Standard_B4ms", "Standard_B8ms", "Standard_D2s_v3", "Standard_D4s_v3",
      "Standard_D8s_v3", "Standard_D16s_v3", "Standard_D32s_v3"
    ], var.vm_size)
    error_message = "VM size must be a valid Azure VM size."
  }
}

variable "vm_instances" {
  description = "Number of virtual machine instances in the scale set"
  type        = number
  default     = 2
  
  validation {
    condition     = var.vm_instances >= 1 && var.vm_instances <= 1000
    error_message = "VM instances must be between 1 and 1000."
  }
}

variable "vnet_address_space" {
  description = "Address space for the virtual network (CIDR notation)"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "VNet address space must be a valid CIDR block."
  }
}

variable "subnet_address_prefix" {
  description = "Address prefix for the web subnet (CIDR notation)"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.subnet_address_prefix, 0))
    error_message = "Subnet address prefix must be a valid CIDR block."
  }
}

variable "maintenance_window_start_time" {
  description = "Start time for maintenance window (format: YYYY-MM-DD HH:MM)"
  type        = string
  default     = "2024-01-01 02:00"
  
  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}$", var.maintenance_window_start_time))
    error_message = "Start time must be in format YYYY-MM-DD HH:MM."
  }
}

variable "maintenance_window_duration" {
  description = "Duration of maintenance window in hours"
  type        = string
  default     = "03:00"
  
  validation {
    condition     = can(regex("^\\d{2}:\\d{2}$", var.maintenance_window_duration))
    error_message = "Duration must be in format HH:MM."
  }
}

variable "maintenance_window_day" {
  description = "Day of the week for maintenance window"
  type        = string
  default     = "Sunday"
  
  validation {
    condition = contains([
      "Monday", "Tuesday", "Wednesday", "Thursday", 
      "Friday", "Saturday", "Sunday"
    ], var.maintenance_window_day)
    error_message = "Day must be a valid day of the week."
  }
}

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    Purpose     = "recipe"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

variable "enable_monitoring" {
  description = "Enable monitoring and diagnostic settings"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 7 and 730."
  }
}

variable "enable_auto_scale" {
  description = "Enable auto-scaling for the virtual machine scale set"
  type        = bool
  default     = false
}

variable "min_capacity" {
  description = "Minimum number of instances when auto-scaling is enabled"
  type        = number
  default     = 2
  
  validation {
    condition     = var.min_capacity >= 1 && var.min_capacity <= 1000
    error_message = "Minimum capacity must be between 1 and 1000."
  }
}

variable "max_capacity" {
  description = "Maximum number of instances when auto-scaling is enabled"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_capacity >= 1 && var.max_capacity <= 1000
    error_message = "Maximum capacity must be between 1 and 1000."
  }
}

variable "enable_deployment_stack_protection" {
  description = "Enable deny settings for deployment stack resource protection"
  type        = bool
  default     = true
}

variable "custom_script_uri" {
  description = "URI to custom script for VM initialization (optional)"
  type        = string
  default     = ""
}

variable "linux_patch_classification" {
  description = "Linux patch classifications to include in maintenance configuration"
  type        = list(string)
  default     = ["Critical", "Security"]
  
  validation {
    condition = alltrue([
      for item in var.linux_patch_classification : contains([
        "Critical", "Security", "Other"
      ], item)
    ])
    error_message = "Linux patch classification must contain only: Critical, Security, Other."
  }
}