# =============================================================================
# Input Variables
# =============================================================================
# This file defines all configurable parameters for the Simple Todo API
# infrastructure deployment, allowing customization of resource names,
# locations, and configuration settings.

# Resource Group Configuration
variable "resource_group_name" {
  description = "The name of the Azure resource group to create or use"
  type        = string
  default     = null
  
  validation {
    condition = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, hyphens, and parentheses."
  }
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Naming Configuration
variable "project_name" {
  description = "The name of the project, used as a prefix for resource names"
  type        = string
  default     = "todo-api"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  description = "The deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "The performance tier of the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "The replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_access_tier" {
  description = "The access tier for the storage account"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool", "Cold"], var.storage_access_tier)
    error_message = "Access tier must be one of: Hot, Cool, Cold."
  }
}

variable "min_tls_version" {
  description = "The minimum TLS version for the storage account"
  type        = string
  default     = "TLS1_2"
  
  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.min_tls_version)
    error_message = "TLS version must be one of: TLS1_0, TLS1_1, TLS1_2."
  }
}

# Function App Configuration
variable "function_app_service_plan_sku" {
  description = "The SKU for the Function App service plan (Y1 for Consumption)"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2"], var.function_app_service_plan_sku)
    error_message = "SKU must be one of: Y1 (Consumption), EP1/EP2/EP3 (Premium), P1v2/P2v2/P3v2 (Dedicated)."
  }
}

variable "node_version" {
  description = "The Node.js version for the Function App"
  type        = string
  default     = "~18"
  
  validation {
    condition     = contains(["~14", "~16", "~18", "~20"], var.node_version)
    error_message = "Node version must be one of: ~14, ~16, ~18, ~20."
  }
}

variable "functions_extension_version" {
  description = "The Azure Functions runtime version"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~3", "~4"], var.functions_extension_version)
    error_message = "Functions extension version must be ~3 or ~4."
  }
}

variable "always_on" {
  description = "Should the Function App be always on? (Not available for Consumption plan)"
  type        = bool
  default     = false
}

# Table Storage Configuration
variable "table_name" {
  description = "The name of the storage table for todo items"
  type        = string
  default     = "todos"
  
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9]{2,62}$", var.table_name))
    error_message = "Table name must be 3-63 characters, start with a letter, and contain only alphanumeric characters."
  }
}

# Application Insights Configuration
variable "enable_application_insights" {
  description = "Whether to enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "application_insights_retention_days" {
  description = "The retention period for Application Insights data in days"
  type        = number
  default     = 90
  
  validation {
    condition     = var.application_insights_retention_days >= 30 && var.application_insights_retention_days <= 730
    error_message = "Retention days must be between 30 and 730."
  }
}

# Security Configuration
variable "https_only" {
  description = "Should the Function App be accessible via HTTPS only?"
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Should public network access be enabled for the storage account?"
  type        = bool
  default     = true
}

variable "shared_access_key_enabled" {
  description = "Should shared access keys be enabled for the storage account?"
  type        = bool
  default     = true
}

# CORS Configuration
variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "cors_support_credentials" {
  description = "Should CORS support credentials?"
  type        = bool
  default     = false
}

# Tags Configuration
variable "tags" {
  description = "A mapping of tags to assign to all resources"
  type        = map(string)
  default = {
    Project     = "Simple Todo API"
    Environment = "Development"
    ManagedBy   = "Terraform"
    Purpose     = "Serverless Todo API Demo"
  }
}

# Advanced Configuration
variable "function_app_zip_deploy_file" {
  description = "Path to the ZIP file containing the Function App code"
  type        = string
  default     = null
}

variable "daily_memory_time_quota" {
  description = "The daily memory time quota for the Function App (consumption plan only)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.daily_memory_time_quota >= 0
    error_message = "Daily memory time quota must be 0 or greater."
  }
}

variable "enable_builtin_logging" {
  description = "Should built-in logging be enabled for the Function App?"
  type        = bool
  default     = true
}

variable "client_certificate_enabled" {
  description = "Should client certificates be enabled for the Function App?"
  type        = bool
  default     = false
}

# Health Check Configuration
variable "health_check_path" {
  description = "The path for health check endpoint"
  type        = string
  default     = null
}

variable "health_check_eviction_time_in_min" {
  description = "Time in minutes after which unhealthy instances are removed from load balancer"
  type        = number
  default     = null
  
  validation {
    condition = var.health_check_eviction_time_in_min == null || (
      var.health_check_eviction_time_in_min >= 2 && 
      var.health_check_eviction_time_in_min <= 10
    )
    error_message = "Health check eviction time must be between 2 and 10 minutes."
  }
}