# Input Variables for Real-time Document Processing Infrastructure
# This file defines all configurable parameters for the solution

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = length(var.environment) <= 10
    error_message = "Environment name must be 10 characters or less."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US",
      "West Europe", "North Europe", "UK South", "UK West",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports all required services."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || length(var.resource_group_name) <= 64
    error_message = "Resource group name must be 64 characters or less."
  }
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "docprocessing"
  
  validation {
    condition     = length(var.project_name) <= 15 && can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must be 15 characters or less and contain only lowercase letters and numbers."
  }
}

variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default = {
    purpose     = "document-processing"
    environment = "demo"
    managed_by  = "terraform"
  }
}

# Event Hub Configuration
variable "eventhub_namespace_sku" {
  description = "SKU for the Event Hub namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.eventhub_namespace_sku)
    error_message = "Event Hub namespace SKU must be Basic, Standard, or Premium."
  }
}

variable "eventhub_namespace_capacity" {
  description = "Capacity units for the Event Hub namespace"
  type        = number
  default     = 1
  
  validation {
    condition     = var.eventhub_namespace_capacity >= 1 && var.eventhub_namespace_capacity <= 20
    error_message = "Event Hub namespace capacity must be between 1 and 20."
  }
}

variable "eventhub_partition_count" {
  description = "Number of partitions for the Event Hub"
  type        = number
  default     = 4
  
  validation {
    condition     = var.eventhub_partition_count >= 1 && var.eventhub_partition_count <= 32
    error_message = "Event Hub partition count must be between 1 and 32."
  }
}

variable "eventhub_message_retention" {
  description = "Message retention period in days"
  type        = number
  default     = 1
  
  validation {
    condition     = var.eventhub_message_retention >= 1 && var.eventhub_message_retention <= 7
    error_message = "Event Hub message retention must be between 1 and 7 days."
  }
}

# Cosmos DB Configuration
variable "cosmosdb_offer_type" {
  description = "Offer type for Cosmos DB"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard"], var.cosmosdb_offer_type)
    error_message = "Cosmos DB offer type must be Standard."
  }
}

variable "cosmosdb_consistency_level" {
  description = "Consistency level for Cosmos DB"
  type        = string
  default     = "Session"
  
  validation {
    condition = contains([
      "BoundedStaleness", "Eventual", "Session", "Strong", "ConsistentPrefix"
    ], var.cosmosdb_consistency_level)
    error_message = "Cosmos DB consistency level must be one of: BoundedStaleness, Eventual, Session, Strong, ConsistentPrefix."
  }
}

variable "cosmosdb_throughput" {
  description = "Request units (RU) for Cosmos DB collection"
  type        = number
  default     = 400
  
  validation {
    condition     = var.cosmosdb_throughput >= 400 && var.cosmosdb_throughput <= 100000
    error_message = "Cosmos DB throughput must be between 400 and 100,000 RU/s."
  }
}

variable "cosmosdb_enable_automatic_failover" {
  description = "Enable automatic failover for Cosmos DB"
  type        = bool
  default     = true
}

variable "cosmosdb_enable_multiple_write_locations" {
  description = "Enable multiple write locations for Cosmos DB"
  type        = bool
  default     = false
}

# AI Document Intelligence Configuration
variable "ai_document_sku" {
  description = "SKU for AI Document Intelligence service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.ai_document_sku)
    error_message = "AI Document Intelligence SKU must be F0 (free) or S0 (standard)."
  }
}

# Function App Configuration
variable "function_app_runtime" {
  description = "Runtime for the Function App"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "dotnet", "java", "python", "powershell"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: node, dotnet, java, python, powershell."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "18"
  
  validation {
    condition     = contains(["18", "16", "14"], var.function_app_runtime_version)
    error_message = "Function App runtime version must be supported for the selected runtime."
  }
}

variable "function_app_plan_type" {
  description = "Plan type for the Function App"
  type        = string
  default     = "Consumption"
  
  validation {
    condition     = contains(["Consumption", "Premium", "Dedicated"], var.function_app_plan_type)
    error_message = "Function App plan type must be Consumption, Premium, or Dedicated."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Application Insights Configuration
variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be web or other."
  }
}

variable "log_analytics_retention_in_days" {
  description = "Retention period for Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_in_days >= 30 && var.log_analytics_retention_in_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

# Security and Networking Configuration
variable "enable_public_access" {
  description = "Enable public access to resources (disable for production)"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access resources"
  type        = list(string)
  default     = []
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security"
  type        = bool
  default     = false
}

# Feature Flags
variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for all resources"
  type        = bool
  default     = true
}

variable "enable_change_feed_function" {
  description = "Deploy the change feed processing function"
  type        = bool
  default     = true
}

variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts for the solution"
  type        = bool
  default     = true
}