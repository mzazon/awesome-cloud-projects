# Variables for Azure QR Code Generator Infrastructure
# Configure deployment settings and customize resource properties

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", "West Europe",
      "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India", "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group (will be created if it doesn't exist)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.resource_group_name == "" || can(regex("^[a-zA-Z0-9._\\-()]+[a-zA-Z0-9._\\-()]$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters long and can contain alphanumeric characters, periods, underscores, hyphens, and parentheses."
  }
}

variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
  default     = "qr-generator"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod) for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier (Standard or Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type (LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS)"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "blob_container_name" {
  description = "Name of the blob container for storing QR code images"
  type        = string
  default     = "qr-codes"
  
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.blob_container_name))
    error_message = "Container name must be 3-63 characters, start and end with lowercase letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_app_runtime" {
  description = "Runtime stack for the Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["python", "node", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function app runtime must be one of: python, node, dotnet, java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)*$", var.function_app_runtime_version))
    error_message = "Runtime version must be a valid version number (e.g., 3.11, 18, 6.0)."
  }
}

variable "function_timeout" {
  description = "Function execution timeout in minutes (1-10 for Consumption plan)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 10
    error_message = "Function timeout must be between 1 and 10 minutes for Consumption plan."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for function monitoring and logging"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain Application Insights logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration (use ['*'] for all origins in development)"
  type        = list(string)
  default     = ["*"]
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for storage account and function app"
  type        = string
  default     = "TLS1_2"
  
  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be one of: TLS1_0, TLS1_1, TLS1_2."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.tags) <= 15
    error_message = "Maximum of 15 tags allowed per resource."
  }
}