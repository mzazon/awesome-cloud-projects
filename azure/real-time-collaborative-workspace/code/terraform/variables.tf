# Variables for Azure real-time collaborative applications infrastructure
# This file defines all configurable parameters for the deployment

# General Configuration
variable "location" {
  description = "The Azure region where all resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "collab-app"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "real-time-collaboration"
    ManagedBy   = "terraform"
    CostCenter  = "engineering"
  }
}

# Azure Communication Services Configuration
variable "acs_data_location" {
  description = "Data location for Azure Communication Services (affects data residency)"
  type        = string
  default     = "United States"
  
  validation {
    condition = contains([
      "United States",
      "Europe",
      "Asia Pacific",
      "Australia",
      "United Kingdom"
    ], var.acs_data_location)
    error_message = "ACS data location must be one of: United States, Europe, Asia Pacific, Australia, United Kingdom."
  }
}

# Azure Fluid Relay Configuration
variable "fluid_relay_sku" {
  description = "SKU for Azure Fluid Relay service"
  type        = string
  default     = "basic"
  
  validation {
    condition = contains(["basic", "standard"], var.fluid_relay_sku)
    error_message = "Fluid Relay SKU must be either 'basic' or 'standard'."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_containers" {
  description = "List of storage containers to create"
  type        = list(string)
  default     = ["whiteboards", "recordings", "user-profiles"]
  
  validation {
    condition = alltrue([
      for container in var.storage_containers :
      can(regex("^[a-z0-9-]+$", container))
    ])
    error_message = "Storage container names must contain only lowercase letters, numbers, and hyphens."
  }
}

# Key Vault Configuration
variable "key_vault_sku" {
  description = "SKU for Azure Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "key_vault_soft_delete_retention" {
  description = "Number of days to retain soft-deleted secrets in Key Vault"
  type        = number
  default     = 7
  
  validation {
    condition = var.key_vault_soft_delete_retention >= 7 && var.key_vault_soft_delete_retention <= 90
    error_message = "Key Vault soft delete retention must be between 7 and 90 days."
  }
}

# Azure Functions Configuration
variable "function_app_runtime" {
  description = "Runtime stack for Azure Functions"
  type        = string
  default     = "node"
  
  validation {
    condition = contains(["node", "dotnet", "python", "java"], var.function_app_runtime)
    error_message = "Function app runtime must be one of: node, dotnet, python, java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Azure Functions"
  type        = string
  default     = "18"
  
  validation {
    condition = can(regex("^[0-9.]+$", var.function_app_runtime_version))
    error_message = "Function app runtime version must be a valid version number."
  }
}

variable "function_app_functions_version" {
  description = "Azure Functions runtime version"
  type        = string
  default     = "4"
  
  validation {
    condition = contains(["3", "4"], var.function_app_functions_version)
    error_message = "Function app functions version must be either '3' or '4'."
  }
}

# Application Insights Configuration
variable "app_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition = contains(["web", "other"], var.app_insights_type)
    error_message = "Application Insights type must be either 'web' or 'other'."
  }
}

variable "app_insights_retention_days" {
  description = "Data retention period in days for Application Insights"
  type        = number
  default     = 30
  
  validation {
    condition = var.app_insights_retention_days >= 30 && var.app_insights_retention_days <= 730
    error_message = "Application Insights retention must be between 30 and 730 days."
  }
}

# Security Configuration
variable "allowed_ip_ranges" {
  description = "IP address ranges allowed to access Key Vault (empty list allows all)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip_range in var.allowed_ip_ranges :
      can(cidrhost(ip_range, 0))
    ])
    error_message = "All IP ranges must be valid CIDR notation."
  }
}

variable "enable_cors_all_origins" {
  description = "Enable CORS for all origins on Function App (not recommended for production)"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS (used when enable_cors_all_origins is false)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for origin in var.cors_allowed_origins :
      can(regex("^https?://", origin))
    ])
    error_message = "All CORS origins must be valid URLs starting with http:// or https://."
  }
}

# Resource Naming Configuration
variable "resource_name_prefix" {
  description = "Prefix for all resource names (will be combined with project_name)"
  type        = string
  default     = ""
  
  validation {
    condition = can(regex("^[a-z0-9-]*$", var.resource_name_prefix))
    error_message = "Resource name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "use_random_suffix" {
  description = "Whether to add a random suffix to resource names for uniqueness"
  type        = bool
  default     = true
}