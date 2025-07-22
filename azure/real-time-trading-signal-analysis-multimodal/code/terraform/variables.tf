# Variables for Azure Intelligent Financial Trading Signal Analysis Infrastructure
# This file defines all configurable parameters for the deployment

variable "resource_group_name" {
  description = "Name of the resource group where all resources will be created"
  type        = string
  default     = "rg-trading-signals"
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
      "Southeast Asia", "East Asia", "Japan East", "Japan West",
      "Australia East", "Australia Southeast"
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
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "trading-signals"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "owner" {
  description = "Owner of the resources for tagging purposes"
  type        = string
  default     = "trading-team"
}

variable "cost_center" {
  description = "Cost center for resource billing"
  type        = string
  default     = "quantitative-research"
}

# Azure AI Services Configuration
variable "cognitive_services_sku" {
  description = "SKU for Azure AI Services (Cognitive Services)"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0", "S1", "S2", "S3"], var.cognitive_services_sku)
    error_message = "Cognitive Services SKU must be one of: F0, S0, S1, S2, S3."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS."
  }
}

# Event Hubs Configuration
variable "event_hub_sku" {
  description = "SKU for Event Hubs namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.event_hub_sku)
    error_message = "Event Hub SKU must be one of: Basic, Standard, Premium."
  }
}

variable "event_hub_capacity" {
  description = "Throughput units for Event Hubs namespace"
  type        = number
  default     = 2
  
  validation {
    condition     = var.event_hub_capacity >= 1 && var.event_hub_capacity <= 20
    error_message = "Event Hub capacity must be between 1 and 20."
  }
}

variable "event_hub_partition_count" {
  description = "Number of partitions for Event Hub"
  type        = number
  default     = 8
  
  validation {
    condition     = var.event_hub_partition_count >= 2 && var.event_hub_partition_count <= 32
    error_message = "Event Hub partition count must be between 2 and 32."
  }
}

variable "event_hub_message_retention" {
  description = "Message retention in days for Event Hub"
  type        = number
  default     = 3
  
  validation {
    condition     = var.event_hub_message_retention >= 1 && var.event_hub_message_retention <= 7
    error_message = "Event Hub message retention must be between 1 and 7 days."
  }
}

# Stream Analytics Configuration
variable "stream_analytics_sku" {
  description = "SKU for Stream Analytics job"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "StandardV2"], var.stream_analytics_sku)
    error_message = "Stream Analytics SKU must be either Standard or StandardV2."
  }
}

variable "stream_analytics_streaming_units" {
  description = "Number of streaming units for Stream Analytics job"
  type        = number
  default     = 6
  
  validation {
    condition     = var.stream_analytics_streaming_units >= 1 && var.stream_analytics_streaming_units <= 120
    error_message = "Stream Analytics streaming units must be between 1 and 120."
  }
}

# Cosmos DB Configuration
variable "cosmos_db_consistency_level" {
  description = "Consistency level for Cosmos DB"
  type        = string
  default     = "Session"
  
  validation {
    condition = contains([
      "Eventual", "Session", "BoundedStaleness", "ConsistentPrefix", "Strong"
    ], var.cosmos_db_consistency_level)
    error_message = "Cosmos DB consistency level must be one of: Eventual, Session, BoundedStaleness, ConsistentPrefix, Strong."
  }
}

variable "cosmos_db_throughput" {
  description = "Throughput (RU/s) for Cosmos DB container"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.cosmos_db_throughput >= 400 && var.cosmos_db_throughput <= 100000
    error_message = "Cosmos DB throughput must be between 400 and 100000 RU/s."
  }
}

variable "cosmos_db_max_throughput" {
  description = "Maximum throughput (RU/s) for Cosmos DB container autoscaling"
  type        = number
  default     = 4000
  
  validation {
    condition     = var.cosmos_db_max_throughput >= 1000 && var.cosmos_db_max_throughput <= 100000
    error_message = "Cosmos DB max throughput must be between 1000 and 100000 RU/s."
  }
}

# Function App Configuration
variable "function_app_sku" {
  description = "SKU for Function App service plan"
  type        = string
  default     = "P1v2"
  
  validation {
    condition = contains([
      "Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2", "P1v3", "P2v3", "P3v3"
    ], var.function_app_sku)
    error_message = "Function App SKU must be a valid Azure Functions SKU."
  }
}

variable "function_app_os_type" {
  description = "Operating system type for Function App"
  type        = string
  default     = "Windows"
  
  validation {
    condition     = contains(["Windows", "Linux"], var.function_app_os_type)
    error_message = "Function App OS type must be either Windows or Linux."
  }
}

variable "function_app_runtime" {
  description = "Runtime for Function App"
  type        = string
  default     = "dotnet"
  
  validation {
    condition = contains([
      "dotnet", "node", "python", "java", "powershell"
    ], var.function_app_runtime)
    error_message = "Function App runtime must be one of: dotnet, node, python, java, powershell."
  }
}

variable "function_app_version" {
  description = "Runtime version for Function App"
  type        = string
  default     = "6"
}

# Service Bus Configuration
variable "service_bus_sku" {
  description = "SKU for Service Bus namespace"
  type        = string
  default     = "Premium"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "Service Bus SKU must be one of: Basic, Standard, Premium."
  }
}

variable "service_bus_capacity" {
  description = "Capacity for Service Bus Premium namespace"
  type        = number
  default     = 1
  
  validation {
    condition     = var.service_bus_capacity >= 1 && var.service_bus_capacity <= 16
    error_message = "Service Bus capacity must be between 1 and 16."
  }
}

# Security and Monitoring
variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for resources"
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

variable "enable_private_endpoints" {
  description = "Enable private endpoints for supported services"
  type        = bool
  default     = false
}

# Common tags applied to all resources
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}