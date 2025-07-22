# Input variables for the real-time data processing infrastructure

variable "resource_group_name" {
  description = "Name of the resource group to create all resources in"
  type        = string
  default     = "rg-realtime-processing"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z]+$", var.environment))
    error_message = "Environment must contain only lowercase letters."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "realtime-processing"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "eventhub_namespace_sku" {
  description = "SKU for the Event Hubs namespace"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.eventhub_namespace_sku)
    error_message = "Event Hub namespace SKU must be Basic, Standard, or Premium."
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
  description = "Message retention period in days for Event Hub"
  type        = number
  default     = 1
  
  validation {
    condition     = var.eventhub_message_retention >= 1 && var.eventhub_message_retention <= 7
    error_message = "Event Hub message retention must be between 1 and 7 days."
  }
}

variable "function_app_runtime" {
  description = "Runtime for the Function App"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "dotnet", "python", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be node, dotnet, python, or java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "18"
}

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
    error_message = "Storage account replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

variable "function_app_service_plan_tier" {
  description = "Service plan tier for the Function App"
  type        = string
  default     = "Dynamic"
  
  validation {
    condition     = contains(["Dynamic", "Premium", "Standard"], var.function_app_service_plan_tier)
    error_message = "Function App service plan tier must be Dynamic, Premium, or Standard."
  }
}

variable "function_app_service_plan_size" {
  description = "Service plan size for the Function App"
  type        = string
  default     = "Y1"
}

variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "application_insights_retention_days" {
  description = "Data retention period in days for Application Insights"
  type        = number
  default     = 90
  
  validation {
    condition     = var.application_insights_retention_days >= 30 && var.application_insights_retention_days <= 730
    error_message = "Application Insights retention must be between 30 and 730 days."
  }
}

variable "enable_auto_scale" {
  description = "Enable auto-scaling for the Event Hub namespace"
  type        = bool
  default     = false
}

variable "maximum_throughput_units" {
  description = "Maximum throughput units for Event Hub namespace (only applies when auto-scale is enabled)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.maximum_throughput_units >= 1 && var.maximum_throughput_units <= 20
    error_message = "Maximum throughput units must be between 1 and 20."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Real-time data processing"
    Environment = "Demo"
    Recipe      = "implementing-real-time-data-processing-azure-functions-event-hubs"
  }
}

variable "function_app_always_on" {
  description = "Should the Function App be always on (not applicable for consumption plan)"
  type        = bool
  default     = false
}

variable "function_app_32bit" {
  description = "Should the Function App use 32-bit architecture"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "enable_https_only" {
  description = "Should the Function App only accept HTTPS requests"
  type        = bool
  default     = true
}