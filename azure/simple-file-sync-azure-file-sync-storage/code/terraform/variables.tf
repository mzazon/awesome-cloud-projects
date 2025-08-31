# Variables for Azure File Sync Infrastructure Deployment
# This file defines all configurable parameters for the file sync solution

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the Azure resource group to contain all resources"
  type        = string
  default     = null
  
  validation {
    condition = var.resource_group_name == null || (
      length(var.resource_group_name) >= 1 && 
      length(var.resource_group_name) <= 90 &&
      can(regex("^[a-zA-Z0-9._\\-()]+$", var.resource_group_name))
    )
    error_message = "Resource group name must be 1-90 characters long and contain only alphanumeric characters, periods, underscores, hyphens, and parentheses."
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
      "Canada Central", "Canada East", "Brazil South", "North Europe", 
      "West Europe", "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Asia Pacific East", "Asia Pacific Southeast",
      "Japan East", "Japan West", "Korea Central", "South India", "Central India",
      "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Storage Account Configuration
variable "storage_account_name" {
  description = "Name of the Azure Storage Account (will be suffixed with random string if not globally unique)"
  type        = string
  default     = null
  
  validation {
    condition = var.storage_account_name == null || (
      length(var.storage_account_name) >= 3 && 
      length(var.storage_account_name) <= 24 &&
      can(regex("^[a-z0-9]+$", var.storage_account_name))
    )
    error_message = "Storage account name must be 3-24 characters long and contain only lowercase letters and numbers."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "enable_large_file_share" {
  description = "Enable large file share support (up to 100 TiB)"
  type        = bool
  default     = true
}

variable "enable_https_traffic_only" {
  description = "Force HTTPS traffic only to storage account"
  type        = bool
  default     = true
}

variable "min_tls_version" {
  description = "Minimum TLS version for the storage account"
  type        = string
  default     = "TLS1_2"
  
  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.min_tls_version)
    error_message = "Minimum TLS version must be one of: TLS1_0, TLS1_1, TLS1_2."
  }
}

# Azure File Share Configuration
variable "file_share_name" {
  description = "Name of the Azure file share"
  type        = string
  default     = "companyfiles"
  
  validation {
    condition = (
      length(var.file_share_name) >= 3 && 
      length(var.file_share_name) <= 63 &&
      can(regex("^[a-z0-9-]+$", var.file_share_name)) &&
      !can(regex("^-", var.file_share_name)) &&
      !can(regex("-$", var.file_share_name)) &&
      !can(regex("--", var.file_share_name))
    )
    error_message = "File share name must be 3-63 characters long, contain only lowercase letters, numbers, and hyphens, and cannot start/end with hyphens or contain consecutive hyphens."
  }
}

variable "file_share_quota" {
  description = "Maximum size of the file share in GB"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.file_share_quota >= 1 && var.file_share_quota <= 102400
    error_message = "File share quota must be between 1 and 102,400 GB."
  }
}

variable "file_share_access_tier" {
  description = "File share access tier for performance and cost optimization"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool", "Premium"], var.file_share_access_tier)
    error_message = "File share access tier must be one of: Hot, Cool, Premium."
  }
}

# Storage Sync Service Configuration
variable "storage_sync_service_name" {
  description = "Name of the Azure File Sync service (will be suffixed with random string if not provided)"
  type        = string
  default     = null
  
  validation {
    condition = var.storage_sync_service_name == null || (
      length(var.storage_sync_service_name) >= 1 && 
      length(var.storage_sync_service_name) <= 260 &&
      can(regex("^[a-zA-Z0-9._-]+$", var.storage_sync_service_name))
    )
    error_message = "Storage sync service name must be 1-260 characters long and contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

# Sync Group Configuration
variable "sync_group_name" {
  description = "Name of the sync group within the Storage Sync Service"
  type        = string
  default     = "main-sync-group"
  
  validation {
    condition = (
      length(var.sync_group_name) >= 1 && 
      length(var.sync_group_name) <= 260 &&
      can(regex("^[a-zA-Z0-9._-]+$", var.sync_group_name))
    )
    error_message = "Sync group name must be 1-260 characters long and contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "cloud_endpoint_name" {
  description = "Name of the cloud endpoint within the sync group"
  type        = string
  default     = null
  
  validation {
    condition = var.cloud_endpoint_name == null || (
      length(var.cloud_endpoint_name) >= 1 && 
      length(var.cloud_endpoint_name) <= 260 &&
      can(regex("^[a-zA-Z0-9._-]+$", var.cloud_endpoint_name))
    )
    error_message = "Cloud endpoint name must be 1-260 characters long and contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

# Sample Files Configuration
variable "create_sample_files" {
  description = "Create sample files in the Azure file share for demonstration"
  type        = bool
  default     = true
}

variable "sample_files" {
  description = "Map of sample files to create in the Azure file share"
  type = map(object({
    content = string
    path    = string
  }))
  default = {
    welcome = {
      content = "Welcome to Azure File Sync!"
      path    = "welcome.txt"
    }
    sync_test = {
      content = "Sync test file created on timestamp placeholder"
      path    = "sync-test.txt"
    }
  }
}

# Network Security Configuration
variable "allow_nested_items_to_be_public" {
  description = "Allow containers and blobs to be configured for public access"
  type        = bool
  default     = false
}

variable "allowed_copy_scope" {
  description = "Restrict copy operations to the same subscription, resource group, or any"
  type        = string
  default     = "AAD"
  
  validation {
    condition     = contains(["AAD", "PrivateLink"], var.allowed_copy_scope)
    error_message = "Allowed copy scope must be either 'AAD' or 'PrivateLink'."
  }
}

# Resource Tagging
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "File Sync Demo"
    Environment = "Development"
    Recipe      = "simple-file-sync-azure-file-sync-storage"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to specific resources"
  type        = map(string)
  default     = {}
}

# Random Resource Naming
variable "use_random_suffix" {
  description = "Add random suffix to resource names to ensure uniqueness"
  type        = bool
  default     = true
}

variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 12
    error_message = "Random suffix length must be between 4 and 12 characters."
  }
}