# Variables for centralized application configuration management
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-config-mgmt"
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US",
      "Canada Central", "Canada East",
      "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast",
      "Japan East", "Japan West",
      "Korea Central", "Korea South",
      "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "app_config_name" {
  description = "Name of the Azure App Configuration store"
  type        = string
  default     = "ac-config"
}

variable "key_vault_name" {
  description = "Name of the Azure Key Vault"
  type        = string
  default     = "kv-secrets"
}

variable "app_service_plan_name" {
  description = "Name of the App Service Plan"
  type        = string
  default     = "asp-demo"
}

variable "web_app_name" {
  description = "Name of the Web App"
  type        = string
  default     = "wa-demo"
}

variable "app_service_sku" {
  description = "SKU for the App Service Plan"
  type        = string
  default     = "B1"
  
  validation {
    condition = contains([
      "F1", "D1", "B1", "B2", "B3", "S1", "S2", "S3", 
      "P1", "P2", "P3", "P1v2", "P2v2", "P3v2", "P1v3", "P2v3", "P3v3"
    ], var.app_service_sku)
    error_message = "App Service SKU must be a valid Azure App Service plan SKU."
  }
}

variable "app_config_sku" {
  description = "SKU for the App Configuration store"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["free", "standard"], var.app_config_sku)
    error_message = "App Configuration SKU must be either 'free' or 'standard'."
  }
}

variable "key_vault_sku" {
  description = "SKU for the Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "node_version" {
  description = "Node.js version for the Web App"
  type        = string
  default     = "18-lts"
  
  validation {
    condition = contains([
      "16-lts", "18-lts", "20-lts"
    ], var.node_version)
    error_message = "Node.js version must be a supported LTS version."
  }
}

variable "enable_soft_delete" {
  description = "Enable soft delete for Key Vault"
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted items in Key Vault"
  type        = number
  default     = 7
  
  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
}

variable "purpose" {
  description = "Purpose of the resources for tagging"
  type        = string
  default     = "config-management"
}

variable "app_settings" {
  description = "Application settings to be added to App Configuration"
  type = map(object({
    value = string
    label = string
  }))
  default = {
    "App:Name" = {
      value = "Demo Configuration App"
      label = "Production"
    }
    "App:Version" = {
      value = "1.0.0"
      label = "Production"
    }
    "Features:EnableLogging" = {
      value = "true"
      label = "Production"
    }
  }
}

variable "key_vault_secrets" {
  description = "Secrets to be added to Key Vault"
  type = map(object({
    value = string
  }))
  default = {
    "DatabaseConnection" = {
      value = "Server=db.example.com;Database=prod;Uid=admin;Pwd=SecureP@ssw0rd123;"
    }
    "ApiKey" = {
      value = "sk-1234567890abcdef1234567890abcdef"
    }
  }
  sensitive = true
}

variable "feature_flags" {
  description = "Feature flags to be added to App Configuration"
  type = map(object({
    enabled = bool
    label   = string
  }))
  default = {
    "BetaFeatures" = {
      enabled = true
      label   = "Production"
    }
  }
}

variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default     = {}
}