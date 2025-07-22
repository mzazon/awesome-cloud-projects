# Variables for Azure Service Discovery Infrastructure

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9-_()]{1,90}$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters and can contain alphanumeric, hyphens, underscores, and parentheses."
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
      "Canada Central", "Canada East", "North Europe", "West Europe",
      "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "Southeast Asia", "East Asia",
      "Japan East", "Japan West", "Korea Central", "India Central",
      "Brazil South"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "service-discovery"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "app_service_plan_sku" {
  description = "App Service Plan SKU"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1V2", "P2V2", "P3V2"], var.app_service_plan_sku)
    error_message = "App Service Plan SKU must be a valid consumption or premium plan SKU."
  }
}

variable "sql_server_admin_username" {
  description = "SQL Server administrator username"
  type        = string
  default     = "sqladmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{2,127}$", var.sql_server_admin_username))
    error_message = "SQL admin username must start with a letter and be 3-128 characters."
  }
}

variable "sql_server_admin_password" {
  description = "SQL Server administrator password"
  type        = string
  sensitive   = true
  default     = null
  
  validation {
    condition = var.sql_server_admin_password == null || can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[@$!%*?&])[A-Za-z\\d@$!%*?&]{8,128}$", var.sql_server_admin_password))
    error_message = "Password must be 8-128 characters with uppercase, lowercase, number, and special character."
  }
}

variable "sql_database_sku" {
  description = "SQL Database SKU name"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "S0", "S1", "S2", "P1", "P2"], var.sql_database_sku)
    error_message = "SQL Database SKU must be a valid service tier."
  }
}

variable "redis_sku_name" {
  description = "Redis Cache SKU name"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.redis_sku_name)
    error_message = "Redis SKU must be Basic, Standard, or Premium."
  }
}

variable "redis_sku_family" {
  description = "Redis Cache SKU family"
  type        = string
  default     = "C"
  
  validation {
    condition     = contains(["C", "P"], var.redis_sku_family)
    error_message = "Redis SKU family must be C (Basic/Standard) or P (Premium)."
  }
}

variable "redis_sku_capacity" {
  description = "Redis Cache SKU capacity"
  type        = number
  default     = 0
  
  validation {
    condition     = var.redis_sku_capacity >= 0 && var.redis_sku_capacity <= 6
    error_message = "Redis SKU capacity must be between 0 and 6."
  }
}

variable "function_app_runtime" {
  description = "Function App runtime stack"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "dotnet", "java", "python"], var.function_app_runtime)
    error_message = "Function App runtime must be node, dotnet, java, or python."
  }
}

variable "function_app_runtime_version" {
  description = "Function App runtime version"
  type        = string
  default     = "18"
  
  validation {
    condition     = can(regex("^[0-9.]+$", var.function_app_runtime_version))
    error_message = "Runtime version must be a valid version number."
  }
}

variable "enable_monitoring" {
  description = "Enable Application Insights monitoring"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable detailed logging for Function Apps"
  type        = bool
  default     = true
}

variable "health_check_interval" {
  description = "Health check interval in minutes"
  type        = number
  default     = 5
  
  validation {
    condition     = var.health_check_interval >= 1 && var.health_check_interval <= 60
    error_message = "Health check interval must be between 1 and 60 minutes."
  }
}

variable "service_registry_tables" {
  description = "List of Azure Tables to create for service registry"
  type        = list(string)
  default     = ["ServiceRegistry", "HealthStatus"]
  
  validation {
    condition     = length(var.service_registry_tables) > 0
    error_message = "At least one service registry table must be specified."
  }
}

variable "allowed_origins" {
  description = "CORS allowed origins for Function Apps"
  type        = list(string)
  default     = ["*"]
}

variable "enable_soft_delete" {
  description = "Enable soft delete for storage accounts"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "service-discovery"
    Environment = "dev"
    ManagedBy   = "terraform"
    Purpose     = "service-discovery"
  }
}