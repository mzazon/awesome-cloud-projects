variable "location" {
  description = "The Azure region where all resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Norway East", "Switzerland North", "UAE North", "South Africa North",
      "East Asia", "Southeast Asia", "Australia East", "Australia Southeast",
      "Central India", "South India", "West India", "Japan East", "Japan West",
      "Korea Central", "Korea South"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create"
  type        = string
  default     = "rg-event-driven-containers"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "storage_account_name" {
  description = "Name of the storage account (will be made globally unique)"
  type        = string
  default     = "steventcontainers"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.storage_account_name)) && length(var.storage_account_name) >= 3 && length(var.storage_account_name) <= 18
    error_message = "Storage account name must be between 3-18 characters, contain only lowercase letters and numbers."
  }
}

variable "container_registry_name" {
  description = "Name of the container registry (will be made globally unique)"
  type        = string
  default     = "acreventcontainers"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9]+$", var.container_registry_name)) && length(var.container_registry_name) >= 5 && length(var.container_registry_name) <= 45
    error_message = "Container registry name must be between 5-45 characters, contain only alphanumeric characters."
  }
}

variable "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  type        = string
  default     = "egt-container-events"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.event_grid_topic_name)) && length(var.event_grid_topic_name) >= 3 && length(var.event_grid_topic_name) <= 50
    error_message = "Event Grid topic name must be between 3-50 characters, contain only alphanumeric characters and hyphens."
  }
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = "law-containers"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.log_analytics_workspace_name)) && length(var.log_analytics_workspace_name) >= 4 && length(var.log_analytics_workspace_name) <= 63
    error_message = "Log Analytics workspace name must be between 4-63 characters, contain only alphanumeric characters and hyphens."
  }
}

variable "function_app_name" {
  description = "Name of the function app (will be made globally unique)"
  type        = string
  default     = "func-event-processor"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.function_app_name)) && length(var.function_app_name) >= 2 && length(var.function_app_name) <= 55
    error_message = "Function app name must be between 2-55 characters, contain only alphanumeric characters and hyphens."
  }
}

variable "container_cpu" {
  description = "CPU allocation for container instances"
  type        = number
  default     = 0.5
  
  validation {
    condition     = contains([0.5, 1, 2, 4], var.container_cpu)
    error_message = "Container CPU must be one of: 0.5, 1, 2, or 4."
  }
}

variable "container_memory" {
  description = "Memory allocation for container instances (in GB)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.container_memory >= 1 && var.container_memory <= 16
    error_message = "Container memory must be between 1 and 16 GB."
  }
}

variable "container_restart_policy" {
  description = "Restart policy for container instances"
  type        = string
  default     = "OnFailure"
  
  validation {
    condition     = contains(["Always", "Never", "OnFailure"], var.container_restart_policy)
    error_message = "Container restart policy must be one of: Always, Never, or OnFailure."
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
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

variable "container_registry_sku" {
  description = "SKU for the container registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container registry SKU must be one of: Basic, Standard, or Premium."
  }
}

variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "Premium", "Standard", "Standalone", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, Premium, Standard, Standalone, or PerGB2018."
  }
}

variable "event_grid_event_retention_time" {
  description = "Event retention time in minutes for Event Grid"
  type        = number
  default     = 1440
  
  validation {
    condition     = var.event_grid_event_retention_time >= 1 && var.event_grid_event_retention_time <= 1440
    error_message = "Event Grid event retention time must be between 1 and 1440 minutes."
  }
}

variable "event_grid_max_delivery_attempts" {
  description = "Maximum delivery attempts for Event Grid events"
  type        = number
  default     = 3
  
  validation {
    condition     = var.event_grid_max_delivery_attempts >= 1 && var.event_grid_max_delivery_attempts <= 30
    error_message = "Event Grid max delivery attempts must be between 1 and 30."
  }
}

variable "enable_container_insights" {
  description = "Enable Container Insights for monitoring"
  type        = bool
  default     = true
}

variable "enable_storage_encryption" {
  description = "Enable storage account encryption"
  type        = bool
  default     = true
}

variable "enable_https_traffic_only" {
  description = "Enable HTTPS traffic only for storage account"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Purpose     = "event-driven-containers"
    ManagedBy   = "terraform"
  }
}