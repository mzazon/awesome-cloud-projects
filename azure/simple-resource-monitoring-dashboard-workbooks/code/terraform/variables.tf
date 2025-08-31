# Variables for Azure Resource Monitoring Dashboard with Workbooks
# This file defines all configurable parameters for the infrastructure deployment

variable "resource_group_name" {
  description = "Name of the Azure resource group to create. If not provided, a unique name will be generated."
  type        = string
  default     = ""
  
  validation {
    condition     = var.resource_group_name == "" || can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters and can contain alphanumeric characters, periods, underscores, hyphens, and parentheses."
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
      "Switzerland North", "Norway East", "Southeast Asia", "East Asia",
      "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "Please specify a valid Azure region."
  }
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace. If not provided, a unique name will be generated."
  type        = string
  default     = ""
  
  validation {
    condition     = var.log_analytics_workspace_name == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{2,61}[a-zA-Z0-9]$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must be 4-63 characters, start and end with alphanumeric characters, and can contain hyphens."
  }
}

variable "log_analytics_sku" {
  description = "SKU/pricing tier for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standalone, Standard, Premium."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain data in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "storage_account_name" {
  description = "Name of the storage account for demonstration. If not provided, a unique name will be generated."
  type        = string
  default     = ""
  
  validation {
    condition     = var.storage_account_name == "" || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters, lowercase letters and numbers only."
  }
}

variable "storage_account_tier" {
  description = "Performance tier of the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "app_service_plan_name" {
  description = "Name of the App Service Plan. If not provided, a unique name will be generated."
  type        = string
  default     = ""
  
  validation {
    condition     = var.app_service_plan_name == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,58}[a-zA-Z0-9]$", var.app_service_plan_name))
    error_message = "App Service Plan name must be 1-60 characters, start and end with alphanumeric characters, and can contain hyphens."
  }
}

variable "app_service_plan_sku_size" {
  description = "SKU size for the App Service Plan"
  type        = string
  default     = "F1"
  
  validation {
    condition     = contains(["F1", "D1", "B1", "B2", "B3", "S1", "S2", "S3", "P1", "P2", "P3"], var.app_service_plan_sku_size)
    error_message = "App Service Plan SKU must be one of the supported sizes."
  }
}

variable "web_app_name" {
  description = "Name of the Web App. If not provided, a unique name will be generated."
  type        = string
  default     = ""
  
  validation {
    condition     = var.web_app_name == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,58}[a-zA-Z0-9]$", var.web_app_name))
    error_message = "Web App name must be 1-60 characters, start and end with alphanumeric characters, and can contain hyphens."
  }
}

variable "workbook_display_name" {
  description = "Display name for the Azure Monitor Workbook"
  type        = string
  default     = "Resource Monitoring Dashboard"
  
  validation {
    condition     = length(var.workbook_display_name) > 0 && length(var.workbook_display_name) <= 256
    error_message = "Workbook display name must be between 1 and 256 characters."
  }
}

variable "environment" {
  description = "Environment tag for resources (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo, test."
  }
}

variable "purpose" {
  description = "Purpose tag for resources"
  type        = string
  default     = "monitoring"
}

variable "owner" {
  description = "Owner tag for resources"
  type        = string
  default     = "terraform"
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for resources to send data to Log Analytics"
  type        = bool
  default     = true
}

variable "enable_workbook_creation" {
  description = "Create the Azure Monitor Workbook with pre-configured queries"
  type        = bool
  default     = true
}