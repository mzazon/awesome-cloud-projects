# variables.tf
# Variable definitions for Azure Network Performance Monitoring solution

# General Configuration
variable "project_name" {
  description = "The name of the project, used for resource naming"
  type        = string
  default     = "network-monitoring"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "eastus"
  
  validation {
    condition = contains([
      "eastus", "eastus2", "westus", "westus2", "westus3", "centralus", "northcentralus", "southcentralus",
      "westcentralus", "canadacentral", "canadaeast", "brazilsouth", "northeurope", "westeurope",
      "uksouth", "ukwest", "francecentral", "germanynorth", "germanywestcentral", "norwayeast",
      "switzerlandnorth", "switzerlandwest", "swedencentral", "uaenorth", "southafricanorth",
      "australiaeast", "australiasoutheast", "eastasia", "southeastasia", "japaneast", "japanwest",
      "koreacentral", "koreasouth", "southindia", "westindia", "centralindia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, test, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase letters and numbers."
  }
}

# Resource Tags
variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "network-monitoring"
    Environment = "demo"
    CreatedBy   = "terraform"
  }
}

# Network Configuration
variable "vnet_address_space" {
  description = "The address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = can([for cidr in var.vnet_address_space : cidrhost(cidr, 0)])
    error_message = "All address spaces must be valid CIDR blocks."
  }
}

variable "subnet_address_prefixes" {
  description = "The address prefixes for the monitoring subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
  
  validation {
    condition     = can([for cidr in var.subnet_address_prefixes : cidrhost(cidr, 0)])
    error_message = "All subnet prefixes must be valid CIDR blocks."
  }
}

# Virtual Machine Configuration
variable "vm_size" {
  description = "The size of the virtual machines"
  type        = string
  default     = "Standard_B2s"
  
  validation {
    condition = contains([
      "Standard_B1s", "Standard_B1ms", "Standard_B2s", "Standard_B2ms", "Standard_B4ms",
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3", "Standard_D16s_v3",
      "Standard_E2s_v3", "Standard_E4s_v3", "Standard_E8s_v3", "Standard_E16s_v3"
    ], var.vm_size)
    error_message = "VM size must be a valid Azure VM size."
  }
}

variable "vm_admin_username" {
  description = "The admin username for the virtual machines"
  type        = string
  default     = "azureuser"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{0,63}$", var.vm_admin_username))
    error_message = "Admin username must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "vm_public_key" {
  description = "SSH public key for VM authentication. If not provided, a new key pair will be generated."
  type        = string
  default     = ""
  sensitive   = true
}

# Connection Monitor Configuration
variable "connection_monitor_test_frequency" {
  description = "Test frequency for connection monitor in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.connection_monitor_test_frequency >= 30 && var.connection_monitor_test_frequency <= 1800
    error_message = "Test frequency must be between 30 and 1800 seconds."
  }
}

variable "connection_monitor_success_threshold_latency" {
  description = "Success threshold for latency in milliseconds"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.connection_monitor_success_threshold_latency > 0
    error_message = "Success threshold latency must be greater than 0."
  }
}

variable "connection_monitor_success_threshold_failed_percent" {
  description = "Success threshold for failed checks percentage"
  type        = number
  default     = 20
  
  validation {
    condition     = var.connection_monitor_success_threshold_failed_percent >= 0 && var.connection_monitor_success_threshold_failed_percent <= 100
    error_message = "Success threshold failed percentage must be between 0 and 100."
  }
}

variable "external_endpoint_address" {
  description = "External endpoint address for connectivity testing"
  type        = string
  default     = "www.microsoft.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+$", var.external_endpoint_address))
    error_message = "External endpoint address must be a valid hostname or IP address."
  }
}

# Log Analytics Configuration
variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Storage account tier for flow logs and diagnostic data"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Alert Configuration
variable "enable_alerts" {
  description = "Enable monitoring alerts"
  type        = bool
  default     = true
}

variable "alert_email_address" {
  description = "Email address for alert notifications"
  type        = string
  default     = "admin@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email_address))
    error_message = "Alert email address must be a valid email address."
  }
}

variable "high_latency_threshold" {
  description = "High latency alert threshold in milliseconds"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.high_latency_threshold > 0
    error_message = "High latency threshold must be greater than 0."
  }
}

variable "connectivity_threshold" {
  description = "Connectivity alert threshold percentage"
  type        = number
  default     = 95
  
  validation {
    condition     = var.connectivity_threshold >= 0 && var.connectivity_threshold <= 100
    error_message = "Connectivity threshold must be between 0 and 100."
  }
}

# Flow Logs Configuration
variable "enable_flow_logs" {
  description = "Enable NSG flow logs"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Number of days to retain flow logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.flow_log_retention_days >= 1 && var.flow_log_retention_days <= 365
    error_message = "Flow log retention must be between 1 and 365 days."
  }
}

variable "flow_log_version" {
  description = "Version of NSG flow logs"
  type        = number
  default     = 2
  
  validation {
    condition     = contains([1, 2], var.flow_log_version)
    error_message = "Flow log version must be either 1 or 2."
  }
}

# Optional Configuration
variable "create_bastion" {
  description = "Create Azure Bastion for secure VM access"
  type        = bool
  default     = false
}

variable "enable_network_security_group_rules" {
  description = "Enable additional NSG rules for monitoring"
  type        = bool
  default     = true
}