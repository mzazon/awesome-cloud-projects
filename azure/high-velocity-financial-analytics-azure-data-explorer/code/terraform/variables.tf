# Variable Definitions for Financial Market Data Processing Infrastructure
# This file defines all configurable parameters for the Azure infrastructure

# Basic Configuration Variables
variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "Central US",
      "North Europe", "West Europe", "UK South", "UK West",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Azure Data Explorer."
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
  description = "Project name for resource naming"
  type        = string
  default     = "financial-market-data"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the resource group (if not provided, will be auto-generated)"
  type        = string
  default     = ""
}

# Azure Data Explorer Configuration
variable "adx_cluster_name" {
  description = "Name of the Azure Data Explorer cluster (if not provided, will be auto-generated)"
  type        = string
  default     = ""
}

variable "adx_sku_name" {
  description = "SKU name for Azure Data Explorer cluster"
  type        = string
  default     = "Dev(No SLA)_Standard_D11_v2"
  
  validation {
    condition = contains([
      "Dev(No SLA)_Standard_D11_v2",
      "Standard_D11_v2",
      "Standard_D12_v2",
      "Standard_D13_v2",
      "Standard_D14_v2"
    ], var.adx_sku_name)
    error_message = "ADX SKU must be a valid Azure Data Explorer SKU."
  }
}

variable "adx_sku_tier" {
  description = "SKU tier for Azure Data Explorer cluster"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard"], var.adx_sku_tier)
    error_message = "ADX SKU tier must be either Basic or Standard."
  }
}

variable "adx_capacity" {
  description = "Number of instances for Azure Data Explorer cluster"
  type        = number
  default     = 1
  
  validation {
    condition     = var.adx_capacity >= 1 && var.adx_capacity <= 10
    error_message = "ADX capacity must be between 1 and 10."
  }
}

variable "adx_database_name" {
  description = "Name of the Azure Data Explorer database"
  type        = string
  default     = "MarketData"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.adx_database_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "adx_hot_cache_period" {
  description = "Hot cache period for ADX database (ISO 8601 duration)"
  type        = string
  default     = "P7D"
  
  validation {
    condition     = can(regex("^P\\d+D$", var.adx_hot_cache_period))
    error_message = "Hot cache period must be in ISO 8601 duration format (e.g., P7D for 7 days)."
  }
}

variable "adx_soft_delete_period" {
  description = "Soft delete period for ADX database (ISO 8601 duration)"
  type        = string
  default     = "P30D"
  
  validation {
    condition     = can(regex("^P\\d+D$", var.adx_soft_delete_period))
    error_message = "Soft delete period must be in ISO 8601 duration format (e.g., P30D for 30 days)."
  }
}

# Event Hubs Configuration
variable "eventhub_namespace_name" {
  description = "Name of the Event Hubs namespace (if not provided, will be auto-generated)"
  type        = string
  default     = ""
}

variable "eventhub_namespace_sku" {
  description = "SKU for Event Hubs namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.eventhub_namespace_sku)
    error_message = "Event Hubs namespace SKU must be Basic, Standard, or Premium."
  }
}

variable "eventhub_namespace_capacity" {
  description = "Throughput units for Event Hubs namespace"
  type        = number
  default     = 2
  
  validation {
    condition     = var.eventhub_namespace_capacity >= 1 && var.eventhub_namespace_capacity <= 20
    error_message = "Event Hubs namespace capacity must be between 1 and 20."
  }
}

variable "eventhub_auto_inflate_enabled" {
  description = "Enable auto-inflate for Event Hubs namespace"
  type        = bool
  default     = true
}

variable "eventhub_auto_inflate_maximum_throughput_units" {
  description = "Maximum throughput units for auto-inflate"
  type        = number
  default     = 10
  
  validation {
    condition     = var.eventhub_auto_inflate_maximum_throughput_units >= 1 && var.eventhub_auto_inflate_maximum_throughput_units <= 40
    error_message = "Maximum throughput units must be between 1 and 40."
  }
}

variable "market_data_hub_partition_count" {
  description = "Number of partitions for market data Event Hub"
  type        = number
  default     = 8
  
  validation {
    condition     = var.market_data_hub_partition_count >= 1 && var.market_data_hub_partition_count <= 32
    error_message = "Market data hub partition count must be between 1 and 32."
  }
}

variable "trading_events_hub_partition_count" {
  description = "Number of partitions for trading events Event Hub"
  type        = number
  default     = 4
  
  validation {
    condition     = var.trading_events_hub_partition_count >= 1 && var.trading_events_hub_partition_count <= 32
    error_message = "Trading events hub partition count must be between 1 and 32."
  }
}

variable "eventhub_message_retention" {
  description = "Message retention in days for Event Hubs"
  type        = number
  default     = 1
  
  validation {
    condition     = var.eventhub_message_retention >= 1 && var.eventhub_message_retention <= 7
    error_message = "Event Hub message retention must be between 1 and 7 days."
  }
}

# Azure Functions Configuration
variable "function_app_name" {
  description = "Name of the Function App (if not provided, will be auto-generated)"
  type        = string
  default     = ""
}

variable "function_app_service_plan_sku" {
  description = "SKU for Function App Service Plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_service_plan_sku)
    error_message = "Function App service plan SKU must be Y1 (Consumption), EP1, EP2, or EP3 (Premium)."
  }
}

variable "function_app_runtime_version" {
  description = "Python runtime version for Function App"
  type        = string
  default     = "3.9"
  
  validation {
    condition     = contains(["3.8", "3.9", "3.10", "3.11"], var.function_app_runtime_version)
    error_message = "Function App runtime version must be a supported Python version."
  }
}

# Storage Account Configuration
variable "storage_account_name" {
  description = "Name of the storage account (if not provided, will be auto-generated)"
  type        = string
  default     = ""
}

variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be a valid Azure replication option."
  }
}

# Event Grid Configuration
variable "event_grid_topic_name" {
  description = "Name of the Event Grid topic (if not provided, will be auto-generated)"
  type        = string
  default     = ""
}

variable "event_grid_input_schema" {
  description = "Input schema for Event Grid topic"
  type        = string
  default     = "EventGridSchema"
  
  validation {
    condition     = contains(["EventGridSchema", "CustomInputSchema", "CloudEventSchemaV1_0"], var.event_grid_input_schema)
    error_message = "Event Grid input schema must be a valid schema type."
  }
}

# Application Insights Configuration
variable "application_insights_name" {
  description = "Name of the Application Insights instance (if not provided, will be auto-generated)"
  type        = string
  default     = ""
}

variable "application_insights_application_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_application_type)
    error_message = "Application Insights application type must be web or other."
  }
}

# Log Analytics Configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if not provided, will be auto-generated)"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Standard", "Premium"], var.log_analytics_workspace_sku)
    error_message = "Log Analytics workspace SKU must be a valid pricing tier."
  }
}

variable "log_analytics_retention_in_days" {
  description = "Data retention in days for Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_in_days >= 30 && var.log_analytics_retention_in_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

# Security and Access Configuration
variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for all resources"
  type        = bool
  default     = true
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for secure access"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR blocks."
  }
}

# Tags Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "FinancialMarketData"
    Environment = "Demo"
    ManagedBy   = "Terraform"
  }
}

# Cost Management Configuration
variable "enable_cost_alerts" {
  description = "Enable cost management alerts"
  type        = bool
  default     = true
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD for cost alerts"
  type        = number
  default     = 500
  
  validation {
    condition     = var.monthly_budget_limit > 0
    error_message = "Monthly budget limit must be greater than 0."
  }
}