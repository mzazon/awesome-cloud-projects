# variables.tf
# Input variables for Azure real-time search application infrastructure

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "rg-realtimesearch-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_().]{1,90}$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters and can contain alphanumeric, hyphens, underscores, parentheses, and periods."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia",
      "Japan East", "Japan West", "Korea Central", "South India",
      "Central India", "Brazil South", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9]{0,8}$", var.prefix))
    error_message = "Prefix must be lowercase alphanumeric and max 8 characters."
  }
}

# Azure Cognitive Search configuration
variable "search_service_sku" {
  description = "SKU for Azure Cognitive Search service"
  type        = string
  default     = "basic"
  
  validation {
    condition     = contains(["free", "basic", "standard", "standard2", "standard3", "storage_optimized_l1", "storage_optimized_l2"], var.search_service_sku)
    error_message = "Search service SKU must be one of: free, basic, standard, standard2, standard3, storage_optimized_l1, storage_optimized_l2."
  }
}

variable "search_replica_count" {
  description = "Number of replicas for the search service"
  type        = number
  default     = 1
  
  validation {
    condition     = var.search_replica_count >= 1 && var.search_replica_count <= 12
    error_message = "Search replica count must be between 1 and 12."
  }
}

variable "search_partition_count" {
  description = "Number of partitions for the search service"
  type        = number
  default     = 1
  
  validation {
    condition     = contains([1, 2, 3, 4, 6, 12], var.search_partition_count)
    error_message = "Search partition count must be one of: 1, 2, 3, 4, 6, 12."
  }
}

# Azure SignalR Service configuration
variable "signalr_sku" {
  description = "SKU for Azure SignalR Service"
  type        = string
  default     = "Standard_S1"
  
  validation {
    condition     = contains(["Free_F1", "Standard_S1", "Premium_P1"], var.signalr_sku)
    error_message = "SignalR SKU must be one of: Free_F1, Standard_S1, Premium_P1."
  }
}

variable "signalr_capacity" {
  description = "Capacity units for SignalR Service"
  type        = number
  default     = 1
  
  validation {
    condition     = var.signalr_capacity >= 1 && var.signalr_capacity <= 100
    error_message = "SignalR capacity must be between 1 and 100."
  }
}

variable "signalr_service_mode" {
  description = "Service mode for SignalR Service"
  type        = string
  default     = "Serverless"
  
  validation {
    condition     = contains(["Default", "Serverless", "Classic"], var.signalr_service_mode)
    error_message = "SignalR service mode must be one of: Default, Serverless, Classic."
  }
}

# Azure Cosmos DB configuration
variable "cosmos_consistency_level" {
  description = "Consistency level for Cosmos DB"
  type        = string
  default     = "Session"
  
  validation {
    condition     = contains(["Eventual", "ConsistentPrefix", "Session", "BoundedStaleness", "Strong"], var.cosmos_consistency_level)
    error_message = "Cosmos DB consistency level must be one of: Eventual, ConsistentPrefix, Session, BoundedStaleness, Strong."
  }
}

variable "cosmos_throughput" {
  description = "Throughput for Cosmos DB container (RU/s)"
  type        = number
  default     = 400
  
  validation {
    condition     = var.cosmos_throughput >= 400 && var.cosmos_throughput <= 1000000
    error_message = "Cosmos DB throughput must be between 400 and 1,000,000 RU/s."
  }
}

variable "cosmos_enable_free_tier" {
  description = "Enable free tier for Cosmos DB (only one per subscription)"
  type        = bool
  default     = false
}

# Azure Storage Account configuration
variable "storage_account_tier" {
  description = "Tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Azure Function App configuration
variable "function_app_runtime" {
  description = "Runtime for the Function App"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["dotnet", "node", "python", "java", "powershell"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: dotnet, node, python, java, powershell."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "18"
}

variable "function_app_os_type" {
  description = "OS type for the Function App"
  type        = string
  default     = "linux"
  
  validation {
    condition     = contains(["linux", "windows"], var.function_app_os_type)
    error_message = "Function App OS type must be either linux or windows."
  }
}

# Event Grid configuration
variable "enable_event_grid_system_topic" {
  description = "Enable Event Grid system topic for storage account"
  type        = bool
  default     = true
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Purpose     = "real-time-search"
    Project     = "azure-cognitive-search-signalr"
    Owner       = "platform-team"
  }
}

# Networking configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for services"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "Allowed IP ranges for firewall rules"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Allow all IPs by default for demo purposes
}

# Monitoring configuration
variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}