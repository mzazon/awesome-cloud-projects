# Core configuration variables
variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = null
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
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
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase alphanumeric characters."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "video-indexer"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase alphanumeric characters and hyphens."
  }
}

# Storage configuration
variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "blob_access_tier" {
  description = "Default access tier for blob storage"
  type        = string
  default     = "Hot"
  validation {
    condition     = contains(["Hot", "Cool"], var.blob_access_tier)
    error_message = "Blob access tier must be either Hot or Cool."
  }
}

# Cosmos DB configuration
variable "cosmos_consistency_level" {
  description = "Cosmos DB consistency level"
  type        = string
  default     = "Session"
  validation {
    condition = contains([
      "BoundedStaleness", "Eventual", "Session", "Strong", "ConsistentPrefix"
    ], var.cosmos_consistency_level)
    error_message = "Cosmos DB consistency level must be one of: BoundedStaleness, Eventual, Session, Strong, ConsistentPrefix."
  }
}

variable "cosmos_enable_serverless" {
  description = "Enable Cosmos DB serverless capacity mode"
  type        = bool
  default     = true
}

variable "cosmos_enable_automatic_failover" {
  description = "Enable automatic failover for Cosmos DB"
  type        = bool
  default     = false
}

# Function App configuration
variable "function_app_os_type" {
  description = "Operating system for Function App"
  type        = string
  default     = "linux"
  validation {
    condition     = contains(["linux", "windows"], var.function_app_os_type)
    error_message = "Function App OS type must be either linux or windows."
  }
}

variable "function_app_runtime" {
  description = "Runtime stack for Function App"
  type        = string
  default     = "node"
  validation {
    condition     = contains(["node", "python", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: node, python, dotnet, java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Function App"
  type        = string
  default     = "18"
}

# Video Indexer configuration
variable "video_indexer_account_id" {
  description = "Azure Video Indexer Account ID (required for deployment)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "video_indexer_api_key" {
  description = "Azure Video Indexer API Key (required for deployment)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "video_indexer_location" {
  description = "Video Indexer API location"
  type        = string
  default     = "trial"
  validation {
    condition = contains([
      "trial", "westus2", "eastus", "westeurope", "southeastasia",
      "australiaeast", "eastus2", "northeurope", "japaneast", "uksouth"
    ], var.video_indexer_location)
    error_message = "Video Indexer location must be a supported region."
  }
}

# Event Grid configuration
variable "event_grid_enable_public_network_access" {
  description = "Enable public network access for Event Grid topic"
  type        = bool
  default     = true
}

variable "event_grid_local_auth_enabled" {
  description = "Enable local authentication for Event Grid topic"
  type        = bool
  default     = true
}

# Monitoring and logging
variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "log_analytics_sku" {
  description = "Log Analytics workspace SKU"
  type        = string
  default     = "PerGB2018"
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standalone."
  }
}

variable "application_insights_type" {
  description = "Application Insights application type"
  type        = string
  default     = "web"
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either web or other."
  }
}

# Security and access control
variable "enable_soft_delete" {
  description = "Enable soft delete for storage containers"
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft deleted blobs"
  type        = number
  default     = 7
  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365
    error_message = "Soft delete retention days must be between 1 and 365."
  }
}

variable "enable_versioning" {
  description = "Enable blob versioning"
  type        = bool
  default     = false
}

# Resource tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "video-transcription"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Cost optimization
variable "function_app_always_on" {
  description = "Enable always on for Function App (not recommended for consumption plan)"
  type        = bool
  default     = false
}

variable "storage_lifecycle_management_enabled" {
  description = "Enable lifecycle management for storage account"
  type        = bool
  default     = true
}

variable "cool_storage_days" {
  description = "Days after last modification to move blobs to cool storage"
  type        = number
  default     = 30
  validation {
    condition     = var.cool_storage_days >= 1
    error_message = "Cool storage days must be at least 1."
  }
}

variable "archive_storage_days" {
  description = "Days after last modification to move blobs to archive storage"
  type        = number
  default     = 90
  validation {
    condition     = var.archive_storage_days >= 1
    error_message = "Archive storage days must be at least 1."
  }
}

variable "delete_storage_days" {
  description = "Days after last modification to delete blobs"
  type        = number
  default     = 365
  validation {
    condition     = var.delete_storage_days >= 1
    error_message = "Delete storage days must be at least 1."
  }
}