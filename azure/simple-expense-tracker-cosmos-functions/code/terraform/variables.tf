# Variables for Azure Expense Tracker Infrastructure
# This file defines all configurable parameters for the expense tracking solution

# General Configuration Variables
variable "resource_group_name" {
  description = "Name of the Azure Resource Group. If not provided, a random name will be generated."
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, hyphens, and underscores."
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
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment designation (dev, staging, prod) used for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "expense-tracker"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# Cosmos DB Configuration Variables
variable "cosmos_db_account_name" {
  description = "Name of the Cosmos DB account. If not provided, a random name will be generated."
  type        = string
  default     = null
  
  validation {
    condition     = var.cosmos_db_account_name == null || (length(var.cosmos_db_account_name) >= 3 && length(var.cosmos_db_account_name) <= 44 && can(regex("^[a-z0-9-]+$", var.cosmos_db_account_name)))
    error_message = "Cosmos DB account name must be 3-44 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cosmos_db_database_name" {
  description = "Name of the Cosmos DB database for storing expense data"
  type        = string
  default     = "ExpenseDB"
  
  validation {
    condition     = length(var.cosmos_db_database_name) >= 1 && length(var.cosmos_db_database_name) <= 255
    error_message = "Database name must be between 1 and 255 characters."
  }
}

variable "cosmos_db_container_name" {
  description = "Name of the Cosmos DB container for storing expense documents"
  type        = string
  default     = "Expenses"
  
  validation {
    condition     = length(var.cosmos_db_container_name) >= 1 && length(var.cosmos_db_container_name) <= 255
    error_message = "Container name must be between 1 and 255 characters."
  }
}

variable "cosmos_db_consistency_level" {
  description = "Consistency level for Cosmos DB operations"
  type        = string
  default     = "Session"
  
  validation {
    condition     = contains(["Strong", "BoundedStaleness", "Session", "ConsistentPrefix", "Eventual"], var.cosmos_db_consistency_level)
    error_message = "Consistency level must be one of: Strong, BoundedStaleness, Session, ConsistentPrefix, Eventual."
  }
}

# Function App Configuration Variables
variable "function_app_name" {
  description = "Name of the Azure Function App. If not provided, a random name will be generated."
  type        = string
  default     = null
  
  validation {
    condition     = var.function_app_name == null || (length(var.function_app_name) >= 2 && length(var.function_app_name) <= 60 && can(regex("^[a-zA-Z0-9-]+$", var.function_app_name)))
    error_message = "Function App name must be 2-60 characters long and contain only alphanumeric characters and hyphens."
  }
}

variable "function_app_runtime" {
  description = "Runtime stack for the Azure Function App"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["dotnet", "java", "node", "powershell", "python"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: dotnet, java, node, powershell, python."
  }
}

variable "function_app_runtime_version" {
  description = "Version of the runtime stack for the Azure Function App"
  type        = string
  default     = "~18"
  
  validation {
    condition     = can(regex("^~?[0-9]+$", var.function_app_runtime_version))
    error_message = "Runtime version must be a number, optionally prefixed with ~."
  }
}

variable "functions_extension_version" {
  description = "Version of the Azure Functions runtime"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~3", "~4"], var.functions_extension_version)
    error_message = "Functions extension version must be ~3 or ~4."
  }
}

# Storage Account Configuration Variables
variable "storage_account_name" {
  description = "Name of the storage account for the Function App. If not provided, a random name will be generated."
  type        = string
  default     = null
  
  validation {
    condition     = var.storage_account_name == null || (length(var.storage_account_name) >= 3 && length(var.storage_account_name) <= 24 && can(regex("^[a-z0-9]+$", var.storage_account_name)))
    error_message = "Storage account name must be 3-24 characters long and contain only lowercase letters and numbers."
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

# Tagging Variables
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.tags) <= 50
    error_message = "Cannot specify more than 50 tags."
  }
}

# Cost Management Variables
variable "enable_monitoring" {
  description = "Enable Application Insights monitoring for the Function App"
  type        = bool
  default     = true
}

variable "daily_quota_gb" {
  description = "Daily data volume quota in GB for Application Insights (0 = no limit)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.daily_quota_gb >= 0 && var.daily_quota_gb <= 1000
    error_message = "Daily quota must be between 0 and 1000 GB."
  }
}