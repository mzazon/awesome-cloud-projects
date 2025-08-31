# Input variables for the URL shortener infrastructure
# These variables allow customization of the deployment without modifying the main configuration

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "East Asia",
      "Southeast Asia", "Japan East", "Japan West", "Korea Central",
      "Korea South", "India Central", "India South", "India West",
      "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = length(var.environment) <= 10 && can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must be lowercase alphanumeric and max 10 characters."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "urlshortener"
  
  validation {
    condition     = length(var.project_name) <= 15 && can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must be lowercase alphanumeric and max 15 characters."
  }
}

variable "storage_account_tier" {
  description = "Performance tier for the storage account"
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
    condition = contains([
      "LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"
    ], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "function_app_service_plan_sku" {
  description = "SKU for the Function App Service Plan (Y1 for Consumption)"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains([
      "Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2", "P1v3", "P2v3", "P3v3"
    ], var.function_app_service_plan_sku)
    error_message = "Function App service plan SKU must be a valid Azure Functions SKU."
  }
}

variable "function_runtime_version" {
  description = "Node.js runtime version for Azure Functions"
  type        = string
  default     = "~20"
  
  validation {
    condition     = contains(["~18", "~20"], var.function_runtime_version)
    error_message = "Function runtime version must be ~18 or ~20."
  }
}

variable "enable_application_insights" {
  description = "Whether to enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "table_name" {
  description = "Name of the Azure Table Storage table for URL mappings"
  type        = string
  default     = "urlmappings"
  
  validation {
    condition     = length(var.table_name) >= 3 && length(var.table_name) <= 63 && can(regex("^[a-zA-Z][a-zA-Z0-9]*$", var.table_name))
    error_message = "Table name must be 3-63 characters, start with a letter, and contain only alphanumeric characters."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "URL Shortener"
    Environment = "Development"
    Recipe      = "simple-url-shortener-functions-table"
  }
  
  validation {
    condition     = length(var.tags) <= 50
    error_message = "Maximum of 50 tags are allowed per resource."
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS on the Function App"
  type        = list(string)
  default     = ["*"]
}

variable "function_timeout" {
  description = "Timeout for function execution in seconds (max 600 for consumption plan)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 600
    error_message = "Function timeout must be between 1 and 600 seconds for consumption plan."
  }
}

variable "enable_https_only" {
  description = "Whether to enforce HTTPS only for the Function App"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for the Function App"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, or 1.2."
  }
}