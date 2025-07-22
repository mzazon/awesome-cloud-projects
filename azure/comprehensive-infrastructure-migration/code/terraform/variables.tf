# General Configuration Variables
variable "source_region" {
  description = "Azure region for source resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "West US 2", "Central US", "North Central US", "South Central US",
      "West Central US", "East US 2", "West US", "West US 3", "Canada Central",
      "Canada East", "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West", "Korea Central",
      "India Central", "South Africa North", "UAE North"
    ], var.source_region)
    error_message = "The source_region must be a valid Azure region."
  }
}

variable "target_region" {
  description = "Azure region for target (migrated) resources"
  type        = string
  default     = "West US 2"
  
  validation {
    condition = contains([
      "East US", "West US 2", "Central US", "North Central US", "South Central US",
      "West Central US", "East US 2", "West US", "West US 3", "Canada Central",
      "Canada East", "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West", "Korea Central",
      "India Central", "South Africa North", "UAE North"
    ], var.target_region)
    error_message = "The target_region must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "test"
  
  validation {
    condition     = length(var.environment) > 0 && length(var.environment) <= 10
    error_message = "Environment must be between 1 and 10 characters."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "migration-demo"
  
  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 20
    error_message = "Project name must be between 1 and 20 characters."
  }
}

# Virtual Machine Configuration Variables
variable "vm_size" {
  description = "Size of the virtual machine to create for migration testing"
  type        = string
  default     = "Standard_B2s"
  
  validation {
    condition = contains([
      "Standard_B1s", "Standard_B1ms", "Standard_B2s", "Standard_B2ms",
      "Standard_B4ms", "Standard_D2s_v3", "Standard_D4s_v3", "Standard_E2s_v3"
    ], var.vm_size)
    error_message = "VM size must be a valid Azure VM size suitable for testing."
  }
}

variable "vm_admin_username" {
  description = "Administrator username for the virtual machine"
  type        = string
  default     = "azureuser"
  
  validation {
    condition     = length(var.vm_admin_username) >= 3 && length(var.vm_admin_username) <= 20
    error_message = "VM admin username must be between 3 and 20 characters."
  }
}

variable "vm_admin_password" {
  description = "Administrator password for the virtual machine"
  type        = string
  sensitive   = true
  default     = null
  
  validation {
    condition = var.vm_admin_password == null || (
      length(var.vm_admin_password) >= 12 &&
      can(regex("[A-Z]", var.vm_admin_password)) &&
      can(regex("[a-z]", var.vm_admin_password)) &&
      can(regex("[0-9]", var.vm_admin_password)) &&
      can(regex("[^A-Za-z0-9]", var.vm_admin_password))
    )
    error_message = "VM admin password must be at least 12 characters and contain uppercase, lowercase, numeric, and special characters."
  }
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file for Linux VM authentication"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# Network Configuration Variables
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = length(var.vnet_address_space) > 0
    error_message = "At least one address space must be specified for the virtual network."
  }
}

variable "subnet_address_prefix" {
  description = "Address prefix for the default subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.subnet_address_prefix, 0))
    error_message = "Subnet address prefix must be a valid CIDR block."
  }
}

# Update Manager Configuration Variables
variable "maintenance_window_start_time" {
  description = "Start time for maintenance window (HH:MM format in UTC)"
  type        = string
  default     = "03:00"
  
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window_start_time))
    error_message = "Maintenance window start time must be in HH:MM format (24-hour)."
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

variable "maintenance_window_day" {
  description = "Day of the week for maintenance window"
  type        = string
  default     = "Saturday"
  
  validation {
    condition = contains([
      "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ], var.maintenance_window_day)
    error_message = "Maintenance window day must be a valid day of the week."
  }
}

variable "patch_classifications" {
  description = "Linux patch classifications to install"
  type        = list(string)
  default     = ["Critical", "Security"]
  
  validation {
    condition = length(var.patch_classifications) > 0 && alltrue([
      for classification in var.patch_classifications : contains([
        "Critical", "Security", "Other"
      ], classification)
    ])
    error_message = "Patch classifications must be valid values: Critical, Security, Other."
  }
}

variable "reboot_setting" {
  description = "Reboot setting for patch installation"
  type        = string
  default     = "IfRequired"
  
  validation {
    condition     = contains(["IfRequired", "Never", "Always"], var.reboot_setting)
    error_message = "Reboot setting must be one of: IfRequired, Never, Always."
  }
}

# Log Analytics Configuration Variables
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["PerGB2018", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid pricing tier."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

# Tagging Variables
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_backup" {
  description = "Enable Azure Backup for virtual machines"
  type        = bool
  default     = false
}

variable "enable_monitoring" {
  description = "Enable Azure Monitor for virtual machines"
  type        = bool
  default     = true
}