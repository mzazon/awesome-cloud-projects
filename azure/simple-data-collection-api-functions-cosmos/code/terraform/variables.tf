# Variable definitions for Azure Data Collection API infrastructure

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9-_]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, hyphens, and underscores."
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
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "Central India", "South India", "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
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

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "data-api"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cosmos_database_name" {
  description = "Name of the Cosmos DB database"
  type        = string
  default     = "DataCollectionDB"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.cosmos_database_name))
    error_message = "Database name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "cosmos_container_name" {
  description = "Name of the Cosmos DB container"
  type        = string
  default     = "records"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.cosmos_container_name))
    error_message = "Container name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "cosmos_throughput" {
  description = "Provisioned throughput for Cosmos DB container (RU/s)"
  type        = number
  default     = 400
  
  validation {
    condition     = var.cosmos_throughput >= 400 && var.cosmos_throughput <= 1000000
    error_message = "Cosmos DB throughput must be between 400 and 1,000,000 RU/s."
  }
}

variable "cosmos_consistency_level" {
  description = "Cosmos DB consistency level"
  type        = string
  default     = "Session"
  
  validation {
    condition = contains([
      "BoundedStaleness", "Eventual", "Session", "Strong", "ConsistentPrefix"
    ], var.cosmos_consistency_level)
    error_message = "Consistency level must be one of: BoundedStaleness, Eventual, Session, Strong, ConsistentPrefix."
  }
}

variable "function_app_runtime" {
  description = "Runtime for the Azure Function App"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "python", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function app runtime must be one of: node, python, dotnet, java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Azure Function App"
  type        = string
  default     = "20"
  
  validation {
    condition     = can(regex("^[0-9.]+$", var.function_app_runtime_version))
    error_message = "Runtime version must be a valid version number."
  }
}

variable "storage_account_tier" {
  description = "Storage account tier"
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
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "enable_backup" {
  description = "Enable automatic backup for Cosmos DB"
  type        = bool
  default     = true
}

variable "backup_interval_in_minutes" {
  description = "Backup interval in minutes for Cosmos DB"
  type        = number
  default     = 240
  
  validation {
    condition     = var.backup_interval_in_minutes >= 60 && var.backup_interval_in_minutes <= 1440
    error_message = "Backup interval must be between 60 and 1440 minutes."
  }
}

variable "backup_retention_in_hours" {
  description = "Backup retention in hours for Cosmos DB"
  type        = number
  default     = 168
  
  validation {
    condition     = var.backup_retention_in_hours >= 8 && var.backup_retention_in_hours <= 720
    error_message = "Backup retention must be between 8 and 720 hours."
  }
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default = {
    Purpose     = "recipe"
    Environment = "demo"
    Project     = "simple-data-collection-api"
  }
}