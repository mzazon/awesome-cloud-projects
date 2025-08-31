# Input Variables for Azure Password Generator Infrastructure
# This file defines all configurable parameters for the infrastructure deployment

# Resource Naming and Location Variables

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East",
      "Japan West", "Korea Central", "India Central", "UAE North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group to create. If not provided, a name will be generated."
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod) used for resource naming and tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,10}$", var.environment))
    error_message = "Environment must be 2-10 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "password-gen"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,15}$", var.project_name))
    error_message = "Project name must be 3-15 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

# Key Vault Configuration Variables

variable "key_vault_sku" {
  description = "SKU for the Key Vault (standard or premium)"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "key_vault_retention_days" {
  description = "Number of days to retain deleted secrets in Key Vault (7-90 days)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_retention_days >= 7 && var.key_vault_retention_days <= 90
    error_message = "Key Vault retention days must be between 7 and 90."
  }
}

variable "enable_purge_protection" {
  description = "Enable purge protection for Key Vault (recommended for production)"
  type        = bool
  default     = false
}

# Function App Configuration Variables

variable "function_app_runtime" {
  description = "Runtime for the Function App"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "dotnet", "python", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: node, dotnet, python, java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "20"
}

variable "storage_account_tier" {
  description = "Storage account tier for Function App (Standard or Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication)
    error_message = "Storage account replication must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Security and Access Configuration Variables

variable "allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "enable_https_only" {
  description = "Force HTTPS-only access to Function App"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for Function App"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be one of: 1.0, 1.1, 1.2."
  }
}

# Additional Access Control Variables

variable "key_vault_access_policies" {
  description = "Additional access policies for Key Vault beyond the Function App managed identity"
  type = list(object({
    tenant_id = string
    object_id = string
    secret_permissions = list(string)
    key_permissions    = list(string)
    certificate_permissions = list(string)
  }))
  default = []
}

# Monitoring and Logging Variables

variable "enable_application_insights" {
  description = "Enable Application Insights for Function App monitoring"
  type        = bool
  default     = true
}

variable "application_insights_type" {
  description = "Application Insights application type"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either 'web' or 'other'."
  }
}

# Resource Tagging Variables

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Function App Configuration Variables

variable "function_app_settings" {
  description = "Additional application settings for the Function App"
  type        = map(string)
  default     = {}
  sensitive   = true
}