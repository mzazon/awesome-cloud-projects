# Variables for Azure Serverless Graph Analytics Infrastructure
# These variables allow customization of the deployment for different environments

variable "resource_group_name" {
  description = "Name of the Azure Resource Group for graph analytics resources"
  type        = string
  default     = "rg-graph-analytics"
  
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

variable "cosmos_account_name" {
  description = "Name of the Azure Cosmos DB account (will be suffixed with random string)"
  type        = string
  default     = "cosmos-graph"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cosmos_account_name))
    error_message = "Cosmos DB account name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cosmos_database_name" {
  description = "Name of the Cosmos DB Gremlin database"
  type        = string
  default     = "GraphAnalytics"
}

variable "cosmos_graph_name" {
  description = "Name of the Cosmos DB Gremlin graph container"
  type        = string
  default     = "RelationshipGraph"
}

variable "cosmos_throughput" {
  description = "Cosmos DB graph container throughput (RU/s)"
  type        = number
  default     = 400
  
  validation {
    condition     = var.cosmos_throughput >= 400 && var.cosmos_throughput <= 1000000
    error_message = "Cosmos DB throughput must be between 400 and 1,000,000 RU/s."
  }
}

variable "function_app_name" {
  description = "Name of the Azure Function App (will be suffixed with random string)"
  type        = string
  default     = "func-graph"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.function_app_name))
    error_message = "Function App name must contain only letters, numbers, and hyphens."
  }
}

variable "storage_account_name" {
  description = "Name of the storage account (will be suffixed with random string)"
  type        = string
  default     = "stgraph"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.storage_account_name))
    error_message = "Storage account name must contain only lowercase letters and numbers."
  }
}

variable "event_grid_topic_name" {
  description = "Name of the Event Grid topic (will be suffixed with random string)"
  type        = string
  default     = "eg-graph"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.event_grid_topic_name))
    error_message = "Event Grid topic name must contain only letters, numbers, and hyphens."
  }
}

variable "app_insights_name" {
  description = "Name of the Application Insights instance (will be suffixed with random string)"
  type        = string
  default     = "ai-graph"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.app_insights_name))
    error_message = "Application Insights name must contain only letters, numbers, and hyphens."
  }
}

variable "cosmos_consistency_level" {
  description = "Cosmos DB consistency level"
  type        = string
  default     = "Session"
  
  validation {
    condition     = contains(["Eventual", "ConsistentPrefix", "Session", "BoundedStaleness", "Strong"], var.cosmos_consistency_level)
    error_message = "Consistency level must be one of: Eventual, ConsistentPrefix, Session, BoundedStaleness, Strong."
  }
}

variable "function_runtime" {
  description = "Azure Functions runtime stack"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "dotnet", "python", "java"], var.function_runtime)
    error_message = "Function runtime must be one of: node, dotnet, python, java."
  }
}

variable "function_runtime_version" {
  description = "Azure Functions runtime version"
  type        = string
  default     = "18"
  
  validation {
    condition     = contains(["18", "16", "14"], var.function_runtime_version)
    error_message = "Function runtime version must be one of: 18, 16, 14."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "graph-analytics"
    Environment = "demo"
    Solution    = "serverless-graph-analytics"
    ManagedBy   = "terraform"
  }
}

variable "cosmos_enable_automatic_failover" {
  description = "Enable automatic failover for Cosmos DB"
  type        = bool
  default     = false
}

variable "cosmos_enable_multiple_write_locations" {
  description = "Enable multiple write locations for Cosmos DB"
  type        = bool
  default     = false
}

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

variable "enable_monitoring" {
  description = "Enable comprehensive monitoring and alerting"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 1 and 730."
  }
}