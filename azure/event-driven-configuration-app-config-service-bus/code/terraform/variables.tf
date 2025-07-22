# Input Variables for Event-Driven Configuration Management Solution
# This file defines all configurable parameters for the Terraform deployment

variable "resource_group_name" {
  description = "Name of the Azure resource group to create"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9_-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "Central US", "North Central US", "South Central US", "West Central US",
      "North Europe", "West Europe", "UK South", "UK West", "France Central", "Germany West Central",
      "Canada Central", "Canada East", "Brazil South", "Australia East", "Australia Southeast",
      "Southeast Asia", "East Asia", "Japan East", "Japan West", "Korea Central", "South India", "Central India"
    ], var.location)
    error_message = "The location must be a valid Azure region."
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
  description = "Name of the project for resource naming"
  type        = string
  default     = "config-management"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "app_configuration_sku" {
  description = "SKU for Azure App Configuration (free or standard)"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["free", "standard"], var.app_configuration_sku)
    error_message = "App Configuration SKU must be either 'free' or 'standard'."
  }
}

variable "service_bus_sku" {
  description = "SKU for Azure Service Bus namespace (Basic, Standard, Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "Service Bus SKU must be one of: Basic, Standard, Premium."
  }
}

variable "function_app_service_plan_sku" {
  description = "SKU for Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_service_plan_sku)
    error_message = "Function App service plan SKU must be one of: Y1 (Consumption), EP1, EP2, EP3 (Elastic Premium)."
  }
}

variable "storage_account_tier" {
  description = "Performance tier for storage account (Standard or Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "enable_public_network_access" {
  description = "Enable public network access for App Configuration"
  type        = bool
  default     = true
}

variable "service_bus_topic_max_size_in_megabytes" {
  description = "Maximum size of Service Bus topic in megabytes"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.service_bus_topic_max_size_in_megabytes >= 1024 && var.service_bus_topic_max_size_in_megabytes <= 81920
    error_message = "Service Bus topic max size must be between 1024 and 81920 megabytes."
  }
}

variable "service_bus_subscription_max_delivery_count" {
  description = "Maximum number of delivery attempts for Service Bus subscription messages"
  type        = number
  default     = 10
  
  validation {
    condition     = var.service_bus_subscription_max_delivery_count >= 1 && var.service_bus_subscription_max_delivery_count <= 2000
    error_message = "Service Bus subscription max delivery count must be between 1 and 2000."
  }
}

variable "service_bus_subscription_lock_duration" {
  description = "Lock duration for Service Bus subscription messages (ISO 8601 duration format)"
  type        = string
  default     = "PT5M"
  
  validation {
    condition     = can(regex("^PT[0-9]+M$", var.service_bus_subscription_lock_duration))
    error_message = "Service Bus subscription lock duration must be in ISO 8601 format (e.g., PT5M for 5 minutes)."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Function App"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~3", "~4"], var.function_app_runtime_version)
    error_message = "Function App runtime version must be either '~3' or '~4'."
  }
}

variable "function_app_node_version" {
  description = "Node.js version for Function App"
  type        = string
  default     = "18"
  
  validation {
    condition     = contains(["14", "16", "18"], var.function_app_node_version)
    error_message = "Function App Node.js version must be one of: 14, 16, 18."
  }
}

variable "logic_app_enabled" {
  description = "Enable Azure Logic Apps for complex configuration workflows"
  type        = bool
  default     = true
}

variable "sample_configuration_keys" {
  description = "Sample configuration keys to create in App Configuration"
  type = map(object({
    value        = string
    content_type = string
  }))
  default = {
    "config/web/app-title" = {
      value        = "My Web Application"
      content_type = "text/plain"
    }
    "config/api/max-connections" = {
      value        = "100"
      content_type = "application/json"
    }
    "config/worker/batch-size" = {
      value        = "50"
      content_type = "application/json"
    }
  }
}

variable "feature_flags" {
  description = "Feature flags to create in App Configuration"
  type = map(object({
    enabled     = bool
    description = string
  }))
  default = {
    "config/features/enable-notifications" = {
      enabled     = true
      description = "Enable notification system"
    }
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Configuration Management"
    Environment = "Demo"
    Architecture = "Event-Driven"
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 4 and 10 characters."
  }
}