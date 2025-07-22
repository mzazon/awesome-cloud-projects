# Variable Definitions for Azure Chaos Studio and Application Insights Recipe
# This file defines all input variables used throughout the Terraform configuration

# Basic Configuration Variables
variable "location" {
  description = "The Azure region where all resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create. If not provided, a random name will be generated"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase letters and numbers."
  }
}

# Monitoring Configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace. If not provided, a random name will be generated"
  type        = string
  default     = ""
}

variable "log_analytics_sku" {
  description = "The SKU of the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains(["PerGB2018", "Premium", "Standard", "Standalone", "Unlimited"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: PerGB2018, Premium, Standard, Standalone, Unlimited."
  }
}

variable "log_analytics_retention_days" {
  description = "The number of days to retain log data in the workspace"
  type        = number
  default     = 30
  
  validation {
    condition = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "application_insights_name" {
  description = "Name of the Application Insights component. If not provided, a random name will be generated"
  type        = string
  default     = ""
}

variable "application_insights_type" {
  description = "The type of Application Insights component"
  type        = string
  default     = "web"
  
  validation {
    condition = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be 'web' or 'other'."
  }
}

# Virtual Machine Configuration
variable "vm_name" {
  description = "Name of the virtual machine for chaos testing. If not provided, a random name will be generated"
  type        = string
  default     = ""
}

variable "vm_size" {
  description = "Size of the virtual machine"
  type        = string
  default     = "Standard_B2s"
  
  validation {
    condition = can(regex("^Standard_[A-Za-z0-9_]+$", var.vm_size))
    error_message = "VM size must be a valid Azure VM size (e.g., Standard_B2s)."
  }
}

variable "vm_admin_username" {
  description = "Administrator username for the virtual machine"
  type        = string
  default     = "azureuser"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.vm_admin_username))
    error_message = "VM admin username must start with a letter and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "vm_disable_password_authentication" {
  description = "Whether to disable password authentication and use SSH keys only"
  type        = bool
  default     = true
}

variable "vm_os_disk_caching" {
  description = "Caching type for the OS disk"
  type        = string
  default     = "ReadWrite"
  
  validation {
    condition = contains(["None", "ReadOnly", "ReadWrite"], var.vm_os_disk_caching)
    error_message = "OS disk caching must be one of: None, ReadOnly, ReadWrite."
  }
}

variable "vm_os_disk_storage_account_type" {
  description = "Storage account type for the OS disk"
  type        = string
  default     = "Standard_LRS"
  
  validation {
    condition = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "UltraSSD_LRS"], var.vm_os_disk_storage_account_type)
    error_message = "OS disk storage account type must be one of: Standard_LRS, StandardSSD_LRS, Premium_LRS, UltraSSD_LRS."
  }
}

# Networking Configuration
variable "vnet_name" {
  description = "Name of the virtual network. If not provided, a random name will be generated"
  type        = string
  default     = ""
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition = length(var.vnet_address_space) > 0
    error_message = "At least one address space must be provided for the virtual network."
  }
}

variable "subnet_name" {
  description = "Name of the subnet for virtual machines"
  type        = string
  default     = "default"
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for the subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
  
  validation {
    condition = length(var.subnet_address_prefixes) > 0
    error_message = "At least one address prefix must be provided for the subnet."
  }
}

variable "public_ip_allocation_method" {
  description = "Allocation method for the public IP address"
  type        = string
  default     = "Static"
  
  validation {
    condition = contains(["Static", "Dynamic"], var.public_ip_allocation_method)
    error_message = "Public IP allocation method must be either 'Static' or 'Dynamic'."
  }
}

variable "public_ip_sku" {
  description = "SKU for the public IP address"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Basic", "Standard"], var.public_ip_sku)
    error_message = "Public IP SKU must be either 'Basic' or 'Standard'."
  }
}

# Security Configuration
variable "network_security_group_name" {
  description = "Name of the network security group. If not provided, a random name will be generated"
  type        = string
  default     = ""
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access to the virtual machine"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = length(var.ssh_allowed_cidr_blocks) > 0
    error_message = "At least one CIDR block must be provided for SSH access."
  }
}

# Chaos Studio Configuration
variable "managed_identity_name" {
  description = "Name of the user-assigned managed identity for Chaos Studio. If not provided, a random name will be generated"
  type        = string
  default     = ""
}

variable "chaos_experiment_name" {
  description = "Name of the chaos experiment. If not provided, a random name will be generated"
  type        = string
  default     = ""
}

variable "chaos_experiment_duration" {
  description = "Duration of the chaos experiment in ISO 8601 format (e.g., PT5M for 5 minutes)"
  type        = string
  default     = "PT5M"
  
  validation {
    condition = can(regex("^PT[0-9]+[MH]$", var.chaos_experiment_duration))
    error_message = "Chaos experiment duration must be in ISO 8601 format (e.g., PT5M, PT1H)."
  }
}

variable "chaos_experiment_enabled" {
  description = "Whether to create and enable the chaos experiment"
  type        = bool
  default     = true
}

# Alert Configuration
variable "action_group_name" {
  description = "Name of the action group for alerts. If not provided, a random name will be generated"
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Email address for chaos experiment alerts"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address."
  }
}

variable "cpu_threshold_percent" {
  description = "CPU percentage threshold for alerts"
  type        = number
  default     = 80
  
  validation {
    condition = var.cpu_threshold_percent >= 1 && var.cpu_threshold_percent <= 100
    error_message = "CPU threshold must be between 1 and 100 percent."
  }
}

# Tagging Configuration
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "chaos-testing"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}