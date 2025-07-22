# Variables for Azure Disaster Recovery Infrastructure
# This file defines all customizable parameters for the disaster recovery solution

# General Configuration
variable "project_name" {
  description = "Name of the project - used for resource naming"
  type        = string
  default     = "dr-solution"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "disaster-recovery"
    ManagedBy   = "terraform"
    Environment = "dev"
  }
}

# Regional Configuration
variable "primary_location" {
  description = "Primary Azure region for production resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "Central US", "North Central US", "South Central US",
      "West Central US", "West US", "West US 2", "West US 3", "Canada Central",
      "Canada East", "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central", "Switzerland North",
      "Switzerland West", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "Korea South", "Central India", "South India",
      "West India", "UAE North", "South Africa North"
    ], var.primary_location)
    error_message = "Primary location must be a valid Azure region."
  }
}

variable "secondary_location" {
  description = "Secondary Azure region for disaster recovery"
  type        = string
  default     = "West US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "Central US", "North Central US", "South Central US",
      "West Central US", "West US", "West US 2", "West US 3", "Canada Central",
      "Canada East", "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central", "Switzerland North",
      "Switzerland West", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "Korea South", "Central India", "South India",
      "West India", "UAE North", "South Africa North"
    ], var.secondary_location)
    error_message = "Secondary location must be a valid Azure region."
  }
}

# Network Configuration
variable "primary_vnet_address_space" {
  description = "Address space for primary virtual network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
  
  validation {
    condition     = length(var.primary_vnet_address_space) > 0
    error_message = "At least one address space must be specified for primary VNet."
  }
}

variable "secondary_vnet_address_space" {
  description = "Address space for secondary virtual network"
  type        = list(string)
  default     = ["10.2.0.0/16"]
  
  validation {
    condition     = length(var.secondary_vnet_address_space) > 0
    error_message = "At least one address space must be specified for secondary VNet."
  }
}

variable "primary_subnet_address_prefix" {
  description = "Address prefix for primary subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "secondary_subnet_address_prefix" {
  description = "Address prefix for secondary subnet"
  type        = string
  default     = "10.2.1.0/24"
}

# Virtual Machine Configuration
variable "vm_size" {
  description = "Size of the virtual machines"
  type        = string
  default     = "Standard_B2s"
  
  validation {
    condition = contains([
      "Standard_B1s", "Standard_B2s", "Standard_B2ms", "Standard_B4ms",
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3",
      "Standard_E2s_v3", "Standard_E4s_v3", "Standard_E8s_v3"
    ], var.vm_size)
    error_message = "VM size must be a valid Azure VM size."
  }
}

variable "vm_admin_username" {
  description = "Admin username for the virtual machines"
  type        = string
  default     = "azureuser"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{2,20}$", var.vm_admin_username))
    error_message = "Admin username must be 3-20 characters long, start with a letter, and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "vm_admin_password" {
  description = "Admin password for the virtual machines"
  type        = string
  default     = "P@ssw0rd123!"
  sensitive   = true
  
  validation {
    condition     = length(var.vm_admin_password) >= 12 && can(regex("^.*[A-Z].*$", var.vm_admin_password)) && can(regex("^.*[a-z].*$", var.vm_admin_password)) && can(regex("^.*[0-9].*$", var.vm_admin_password)) && can(regex("^.*[^a-zA-Z0-9].*$", var.vm_admin_password))
    error_message = "Password must be at least 12 characters long and contain uppercase, lowercase, numbers, and special characters."
  }
}

variable "vm_image_publisher" {
  description = "Publisher of the VM image"
  type        = string
  default     = "MicrosoftWindowsServer"
}

variable "vm_image_offer" {
  description = "Offer of the VM image"
  type        = string
  default     = "WindowsServer"
}

variable "vm_image_sku" {
  description = "SKU of the VM image"
  type        = string
  default     = "2019-Datacenter"
}

variable "vm_image_version" {
  description = "Version of the VM image"
  type        = string
  default     = "latest"
}

variable "vm_storage_account_type" {
  description = "Storage account type for VM disks"
  type        = string
  default     = "Premium_LRS"
  
  validation {
    condition     = contains(["Premium_LRS", "StandardSSD_LRS", "Standard_LRS", "UltraSSD_LRS"], var.vm_storage_account_type)
    error_message = "Storage account type must be one of: Premium_LRS, StandardSSD_LRS, Standard_LRS, UltraSSD_LRS."
  }
}

# Recovery Services Configuration
variable "vault_storage_model_type" {
  description = "Storage model type for Recovery Services Vault"
  type        = string
  default     = "GeoRedundant"
  
  validation {
    condition     = contains(["GeoRedundant", "LocallyRedundant", "ReadAccessGeoZoneRedundant", "ZoneRedundant"], var.vault_storage_model_type)
    error_message = "Vault storage model type must be one of: GeoRedundant, LocallyRedundant, ReadAccessGeoZoneRedundant, ZoneRedundant."
  }
}

variable "vault_cross_region_restore_enabled" {
  description = "Enable cross-region restore for Recovery Services Vault"
  type        = bool
  default     = false
}

variable "vault_soft_delete_enabled" {
  description = "Enable soft delete for Recovery Services Vault"
  type        = bool
  default     = true
}

# Backup Policy Configuration
variable "backup_frequency" {
  description = "Backup frequency (Daily or Weekly)"
  type        = string
  default     = "Daily"
  
  validation {
    condition     = contains(["Daily", "Weekly"], var.backup_frequency)
    error_message = "Backup frequency must be either Daily or Weekly."
  }
}

variable "backup_time" {
  description = "Time for daily backups (HH:MM format)"
  type        = string
  default     = "02:00"
  
  validation {
    condition     = can(regex("^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$", var.backup_time))
    error_message = "Backup time must be in HH:MM format (24-hour)."
  }
}

variable "backup_retention_daily" {
  description = "Number of daily backups to retain"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_daily >= 7 && var.backup_retention_daily <= 9999
    error_message = "Daily backup retention must be between 7 and 9999 days."
  }
}

variable "backup_retention_weekly" {
  description = "Number of weekly backups to retain"
  type        = number
  default     = 12
  
  validation {
    condition     = var.backup_retention_weekly >= 1 && var.backup_retention_weekly <= 5163
    error_message = "Weekly backup retention must be between 1 and 5163 weeks."
  }
}

variable "backup_retention_monthly" {
  description = "Number of monthly backups to retain"
  type        = number
  default     = 12
  
  validation {
    condition     = var.backup_retention_monthly >= 1 && var.backup_retention_monthly <= 1188
    error_message = "Monthly backup retention must be between 1 and 1188 months."
  }
}

variable "backup_retention_yearly" {
  description = "Number of yearly backups to retain"
  type        = number
  default     = 10
  
  validation {
    condition     = var.backup_retention_yearly >= 1 && var.backup_retention_yearly <= 99
    error_message = "Yearly backup retention must be between 1 and 99 years."
  }
}

# Monitoring Configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, Premium, Standard, Standalone, Unlimited, CapacityReservation, PerGB2018."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain log analytics data"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "alert_email_address" {
  description = "Email address for disaster recovery alerts"
  type        = string
  default     = "admin@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email_address))
    error_message = "Alert email address must be a valid email address."
  }
}

# Automation Configuration
variable "automation_sku" {
  description = "SKU for Azure Automation Account"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Free"], var.automation_sku)
    error_message = "Automation SKU must be either Basic or Free."
  }
}

variable "enable_update_management" {
  description = "Enable Azure Update Management"
  type        = bool
  default     = true
}

variable "enable_change_tracking" {
  description = "Enable Change Tracking and Inventory"
  type        = bool
  default     = true
}

# Security Configuration
variable "network_security_rules" {
  description = "Custom network security rules"
  type = list(object({
    name                       = string
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = string
    source_port_range          = string
    destination_port_range     = string
    source_address_prefix      = string
    destination_address_prefix = string
  }))
  default = [
    {
      name                       = "AllowRDP"
      priority                   = 1000
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowWinRM"
      priority                   = 1001
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "5985-5986"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  ]
}

variable "enable_backup_encryption" {
  description = "Enable backup encryption using customer-managed keys"
  type        = bool
  default     = false
}

variable "enable_network_watcher" {
  description = "Enable Network Watcher for monitoring"
  type        = bool
  default     = true
}

# Cost Management
variable "enable_cost_alerts" {
  description = "Enable cost management alerts"
  type        = bool
  default     = true
}

variable "monthly_budget_amount" {
  description = "Monthly budget amount for cost alerts"
  type        = number
  default     = 500
  
  validation {
    condition     = var.monthly_budget_amount > 0
    error_message = "Monthly budget amount must be greater than 0."
  }
}