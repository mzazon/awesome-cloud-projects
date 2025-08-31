# Variables Configuration for Azure File Backup Solution
# This file defines all configurable parameters for the backup automation infrastructure

# Basic Configuration Variables
variable "resource_group_name" {
  description = "Name of the Azure Resource Group to create"
  type        = string
  default     = "rg-backup-automation"
  
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
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
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India", "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Storage Account Configuration
variable "storage_account_name" {
  description = "Name of the Azure Storage Account (leave empty for auto-generation)"
  type        = string
  default     = ""
  
  validation {
    condition = var.storage_account_name == "" || (
      length(var.storage_account_name) >= 3 && 
      length(var.storage_account_name) <= 24 && 
      can(regex("^[a-z0-9]+$", var.storage_account_name))
    )
    error_message = "Storage account name must be 3-24 characters, lowercase letters and numbers only."
  }
}

variable "storage_account_tier" {
  description = "Performance tier of the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_replication_type" {
  description = "Type of replication for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_access_tier" {
  description = "Access tier for blob storage (Hot, Cool, or Archive)"
  type        = string
  default     = "Cool"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be either 'Hot' or 'Cool'."
  }
}

variable "container_name" {
  description = "Name of the blob container for backup files"
  type        = string
  default     = "backup-files"
  
  validation {
    condition = length(var.container_name) >= 3 && length(var.container_name) <= 63 && can(regex("^[a-z0-9-]+$", var.container_name))
    error_message = "Container name must be 3-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Logic Apps Configuration
variable "logic_app_name" {
  description = "Name of the Logic Apps workflow (leave empty for auto-generation)"
  type        = string
  default     = ""
  
  validation {
    condition = var.logic_app_name == "" || (
      length(var.logic_app_name) >= 1 && 
      length(var.logic_app_name) <= 80 && 
      can(regex("^[a-zA-Z0-9-_]+$", var.logic_app_name))
    )
    error_message = "Logic app name must be 1-80 characters, letters, numbers, hyphens, and underscores only."
  }
}

variable "backup_schedule_frequency" {
  description = "Frequency for backup schedule (Day, Week, Month)"
  type        = string
  default     = "Day"
  
  validation {
    condition     = contains(["Day", "Week", "Month"], var.backup_schedule_frequency)
    error_message = "Backup schedule frequency must be 'Day', 'Week', or 'Month'."
  }
}

variable "backup_schedule_interval" {
  description = "Interval for backup schedule (e.g., 1 for daily, 2 for every 2 days)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.backup_schedule_interval >= 1 && var.backup_schedule_interval <= 1000
    error_message = "Backup schedule interval must be between 1 and 1000."
  }
}

variable "backup_time_hour" {
  description = "Hour of day to run backup (0-23, 24-hour format)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.backup_time_hour >= 0 && var.backup_time_hour <= 23
    error_message = "Backup time hour must be between 0 and 23."
  }
}

variable "backup_time_minute" {
  description = "Minute of hour to run backup (0-59)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.backup_time_minute >= 0 && var.backup_time_minute <= 59
    error_message = "Backup time minute must be between 0 and 59."
  }
}

variable "time_zone" {
  description = "Time zone for backup schedule"
  type        = string
  default     = "Eastern Standard Time"
}

# Security Configuration
variable "enable_https_traffic_only" {
  description = "Enable HTTPS traffic only for storage account"
  type        = bool
  default     = true
}

variable "min_tls_version" {
  description = "Minimum TLS version for storage account"
  type        = string
  default     = "TLS1_2"
  
  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.min_tls_version)
    error_message = "Minimum TLS version must be TLS1_0, TLS1_1, or TLS1_2."
  }
}

variable "allow_blob_public_access" {
  description = "Allow public access to blob containers"
  type        = bool
  default     = false
}

# Resource Tagging
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Demo"
    Purpose     = "Backup"
    Project     = "FileAutomation"
    ManagedBy   = "Terraform"
  }
  
  validation {
    condition     = length(var.common_tags) <= 15
    error_message = "Maximum of 15 tags allowed per resource."
  }
}

# Advanced Configuration
variable "enable_storage_logging" {
  description = "Enable diagnostic logging for storage account"
  type        = bool
  default     = true
}

variable "enable_logic_apps_logging" {
  description = "Enable diagnostic logging for Logic Apps"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain diagnostic logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
  }
}

# Naming Convention Variables
variable "environment" {
  description = "Environment name for resource naming (dev, test, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "workload" {
  description = "Workload name for resource naming"
  type        = string
  default     = "backup"
  
  validation {
    condition     = length(var.workload) >= 2 && length(var.workload) <= 10
    error_message = "Workload name must be between 2 and 10 characters."
  }
}