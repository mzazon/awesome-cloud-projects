# Variable Definitions for Multi-Channel Communication Platform
# This file defines all configurable variables for the Terraform deployment

variable "location" {
  description = "The Azure region where all resources will be deployed"
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
      "Japan West", "Korea Central", "South India", "Central India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "The name of the resource group for all communication platform resources"
  type        = string
  default     = "rg-multi-channel-comms"
  
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }
}

variable "environment" {
  description = "The deployment environment (development, staging, production)"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "project_name" {
  description = "The name of the project for resource naming and tagging"
  type        = string
  default     = "multi-channel-comms"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "communication_services_data_location" {
  description = "The data residency location for Azure Communication Services"
  type        = string
  default     = "United States"
  
  validation {
    condition = contains([
      "United States", "Europe", "Australia", "United Kingdom"
    ], var.communication_services_data_location)
    error_message = "Data location must be one of: United States, Europe, Australia, United Kingdom."
  }
}

variable "cosmos_db_consistency_level" {
  description = "The consistency level for Cosmos DB (Session recommended for communication platforms)"
  type        = string
  default     = "Session"
  
  validation {
    condition = contains([
      "Eventual", "ConsistentPrefix", "Session", "BoundedStaleness", "Strong"
    ], var.cosmos_db_consistency_level)
    error_message = "Consistency level must be one of: Eventual, ConsistentPrefix, Session, BoundedStaleness, Strong."
  }
}

variable "cosmos_db_max_staleness_prefix" {
  description = "The maximum staleness prefix for BoundedStaleness consistency level"
  type        = number
  default     = 100000
  
  validation {
    condition     = var.cosmos_db_max_staleness_prefix >= 10 && var.cosmos_db_max_staleness_prefix <= 2147483647
    error_message = "Max staleness prefix must be between 10 and 2147483647."
  }
}

variable "cosmos_db_max_interval_in_seconds" {
  description = "The maximum lag time in seconds for BoundedStaleness consistency level"
  type        = number
  default     = 300
  
  validation {
    condition     = var.cosmos_db_max_interval_in_seconds >= 5 && var.cosmos_db_max_interval_in_seconds <= 86400
    error_message = "Max interval must be between 5 and 86400 seconds."
  }
}

variable "function_app_plan_sku" {
  description = "The SKU for the Function App service plan (Y1 for consumption plan)"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains([
      "Y1", "EP1", "EP2", "EP3", "P1V2", "P2V2", "P3V2", "P1V3", "P2V3", "P3V3"
    ], var.function_app_plan_sku)
    error_message = "Function App plan SKU must be a valid Azure Functions plan size."
  }
}

variable "storage_account_tier" {
  description = "The performance tier for the storage account (Standard or Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "The replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains([
      "LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"
    ], var.storage_account_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "enable_cosmos_db_backup" {
  description = "Whether to enable automatic backup for Cosmos DB"
  type        = bool
  default     = true
}

variable "cosmos_db_backup_interval_in_minutes" {
  description = "Backup interval in minutes for Cosmos DB (240-1440 minutes)"
  type        = number
  default     = 240
  
  validation {
    condition     = var.cosmos_db_backup_interval_in_minutes >= 240 && var.cosmos_db_backup_interval_in_minutes <= 1440
    error_message = "Backup interval must be between 240 and 1440 minutes."
  }
}

variable "cosmos_db_backup_retention_in_hours" {
  description = "Backup retention period in hours for Cosmos DB (8-720 hours)"
  type        = number
  default     = 168 # 7 days
  
  validation {
    condition     = var.cosmos_db_backup_retention_in_hours >= 8 && var.cosmos_db_backup_retention_in_hours <= 720
    error_message = "Backup retention must be between 8 and 720 hours."
  }
}

variable "enable_function_app_insights" {
  description = "Whether to enable Application Insights for Function App monitoring"
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "multi-channel-communication-platform"
    Environment = "development"
    ManagedBy   = "terraform"
    Purpose     = "customer-communication"
  }
  
  validation {
    condition     = alltrue([for k, v in var.tags : can(regex("^.{1,512}$", k)) && can(regex("^.{0,256}$", v))])
    error_message = "Tag keys must be 1-512 characters and values must be 0-256 characters."
  }
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access the Function App (empty list allows all)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR notation."
  }
}

variable "function_app_always_on" {
  description = "Whether to keep the Function App always on (only applicable for non-consumption plans)"
  type        = bool
  default     = false
}

variable "random_suffix_length" {
  description = "Length of the random suffix for resource names to ensure uniqueness"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 3 && var.random_suffix_length <= 8
    error_message = "Random suffix length must be between 3 and 8 characters."
  }
}