# Input variables for the Key Vault and App Service secrets management solution

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
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Southeast Asia", "East Asia",
      "Japan East", "Japan West", "Korea Central", "South India", "Central India"
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
    error_message = "Environment must be lowercase alphanumeric and no more than 10 characters."
  }
}

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "secrets-demo"
  
  validation {
    condition     = length(var.project_name) <= 15 && can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be lowercase, alphanumeric with hyphens, and no more than 15 characters."
  }
}

variable "app_service_sku" {
  description = "SKU for the App Service Plan"
  type = object({
    tier = string
    size = string
  })
  default = {
    tier = "Basic"
    size = "B1"
  }
  
  validation {
    condition = contains(["Free", "Shared", "Basic", "Standard", "Premium", "PremiumV2", "PremiumV3"], var.app_service_sku.tier)
    error_message = "App Service tier must be one of: Free, Shared, Basic, Standard, Premium, PremiumV2, PremiumV3."
  }
}

variable "node_version" {
  description = "Node.js version for the web application"
  type        = string
  default     = "18-lts"
  
  validation {
    condition = contains([
      "16-lts", "18-lts", "20-lts"
    ], var.node_version)
    error_message = "Node version must be one of: 16-lts, 18-lts, 20-lts."
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

variable "database_connection_string" {
  description = "Sample database connection string to store in Key Vault"
  type        = string
  default     = "Server=myserver.database.windows.net;Database=mydb;User=admin;Password=SecureP@ssw0rd123"
  sensitive   = true
}

variable "external_api_key" {
  description = "Sample external API key to store in Key Vault"
  type        = string
  default     = "sk-1234567890abcdef1234567890abcdef"
  sensitive   = true
}

variable "enable_rbac_authorization" {
  description = "Enable RBAC authorization for Key Vault instead of access policies"
  type        = bool
  default     = true
}

variable "purge_protection_enabled" {
  description = "Enable purge protection for Key Vault (recommended for production)"
  type        = bool
  default     = false
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain Key Vault after soft delete"
  type        = number
  default     = 7
  
  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "tutorial"
    Purpose     = "secrets-demo"
    ManagedBy   = "terraform"
  }
}