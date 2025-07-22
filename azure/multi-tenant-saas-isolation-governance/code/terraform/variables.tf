# Common variables for the multi-tenant SaaS platform
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Norway East", "Switzerland North", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "Central India", "South India", "West India"
    ], var.location)
    error_message = "Please specify a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., development, staging, production)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "saas"
  
  validation {
    condition     = length(var.resource_prefix) <= 10 && can(regex("^[a-z0-9]+$", var.resource_prefix))
    error_message = "Resource prefix must be 10 characters or less and contain only lowercase letters and numbers."
  }
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Multi-Tenant SaaS Platform"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}

# Tenant configuration variables
variable "sample_tenants" {
  description = "Configuration for sample tenants to be created"
  type = map(object({
    name        = string
    environment = string
    admin_email = string
  }))
  default = {
    tenant001 = {
      name        = "Contoso Corp"
      environment = "production"
      admin_email = "admin@contoso.com"
    }
    tenant002 = {
      name        = "Fabrikam Inc"
      environment = "production"
      admin_email = "admin@fabrikam.com"
    }
  }
}

# Workload Identity variables
variable "workload_identity_issuer" {
  description = "The issuer URL for workload identity federation"
  type        = string
  default     = "https://sts.windows.net/"
}

variable "workload_identity_subject" {
  description = "The subject claim for workload identity federation"
  type        = string
  default     = "system:serviceaccount:tenant-namespace:tenant-workload"
}

variable "workload_identity_audience" {
  description = "The audience for workload identity federation"
  type        = string
  default     = "api://AzureADTokenExchange"
}

# Key Vault configuration
variable "key_vault_sku" {
  description = "SKU for the Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain deleted keys in Key Vault"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

# Log Analytics workspace variables
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standalone, Standard, Premium."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 90
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

# Network security variables
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access Key Vault"
  type        = list(string)
  default     = []
}

variable "enable_public_network_access" {
  description = "Enable public network access to Key Vault"
  type        = bool
  default     = true
}

# Policy assignment variables
variable "policy_assignment_enforcement_mode" {
  description = "Enforcement mode for policy assignments"
  type        = string
  default     = "Default"
  
  validation {
    condition     = contains(["Default", "DoNotEnforce"], var.policy_assignment_enforcement_mode)
    error_message = "Policy assignment enforcement mode must be either 'Default' or 'DoNotEnforce'."
  }
}

# Tenant resource configuration
variable "tenant_storage_account_tier" {
  description = "Performance tier for tenant storage accounts"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.tenant_storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "tenant_storage_replication_type" {
  description = "Replication type for tenant storage accounts"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.tenant_storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "tenant_vnet_address_space" {
  description = "Address space for tenant virtual networks"
  type        = string
  default     = "10.0.0.0/16"
}

variable "tenant_subnet_address_prefix" {
  description = "Address prefix for tenant subnets"
  type        = string
  default     = "10.0.1.0/24"
}