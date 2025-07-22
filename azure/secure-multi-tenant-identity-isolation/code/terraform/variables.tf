# Input Variables for Multi-Tenant Customer Identity Isolation Infrastructure
# These variables allow customization of the deployment while maintaining security best practices

variable "location" {
  description = "The Azure region where all resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment designation for resource tagging and naming"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "multitenant-identity"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_group_name" {
  description = "Name of the main resource group for the multi-tenant infrastructure"
  type        = string
  default     = ""
}

variable "vnet_address_space" {
  description = "Address space for the virtual network in CIDR notation"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition = alltrue([
      for cidr in var.vnet_address_space : can(cidrhost(cidr, 0))
    ])
    error_message = "All address spaces must be valid CIDR blocks."
  }
}

variable "private_endpoint_subnet_address_prefix" {
  description = "Address prefix for the private endpoint subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.private_endpoint_subnet_address_prefix, 0))
    error_message = "Private endpoint subnet address prefix must be a valid CIDR block."
  }
}

variable "api_management_subnet_address_prefix" {
  description = "Address prefix for the API Management subnet"
  type        = string
  default     = "10.0.2.0/24"
  
  validation {
    condition     = can(cidrhost(var.api_management_subnet_address_prefix, 0))
    error_message = "API Management subnet address prefix must be a valid CIDR block."
  }
}

variable "apim_sku_name" {
  description = "SKU for the API Management instance"
  type        = string
  default     = "Developer_1"
  
  validation {
    condition = contains([
      "Developer_1", "Basic_1", "Basic_2", 
      "Standard_1", "Standard_2", 
      "Premium_1", "Premium_2", "Premium_3", "Premium_4"
    ], var.apim_sku_name)
    error_message = "API Management SKU must be a valid tier and capacity combination."
  }
}

variable "apim_publisher_name" {
  description = "Publisher name for the API Management instance"
  type        = string
  default     = "Multi-Tenant SaaS Provider"
}

variable "apim_publisher_email" {
  description = "Publisher email for the API Management instance"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.apim_publisher_email))
    error_message = "Publisher email must be a valid email address."
  }
}

variable "key_vault_sku" {
  description = "SKU for the Key Vault instance"
  type        = string
  default     = "premium"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains([
      "Free", "Standalone", "PerNode", "PerGB2018", "Premium"
    ], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid pricing tier."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

variable "tenant_configurations" {
  description = "Configuration for customer tenants including names and specific settings"
  type = map(object({
    display_name = string
    description  = string
    enabled      = bool
  }))
  default = {
    "tenant-a" = {
      display_name = "Customer A Identity Tenant"
      description  = "External ID tenant for Customer A with complete identity isolation"
      enabled      = true
    }
    "tenant-b" = {
      display_name = "Customer B Identity Tenant"
      description  = "External ID tenant for Customer B with complete identity isolation"
      enabled      = true
    }
  }
}

variable "enable_private_link_monitoring" {
  description = "Enable Azure Monitor Private Link Scope for secure monitoring"
  type        = bool
  default     = true
}

variable "enable_soft_delete" {
  description = "Enable soft delete for Key Vault (recommended for production)"
  type        = bool
  default     = true
}

variable "enable_purge_protection" {
  description = "Enable purge protection for Key Vault (recommended for production)"
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault items"
  type        = number
  default     = 90
  
  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

variable "enable_rbac_authorization" {
  description = "Enable RBAC authorization for Key Vault instead of access policies"
  type        = bool
  default     = true
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for all supported resources"
  type        = bool
  default     = true
}

variable "alert_enabled" {
  description = "Enable alerting for tenant isolation violations and security events"
  type        = bool
  default     = true
}

variable "alert_severity" {
  description = "Severity level for tenant isolation violation alerts"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alert_severity >= 0 && var.alert_severity <= 4
    error_message = "Alert severity must be between 0 (Critical) and 4 (Verbose)."
  }
}

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    Environment    = "production"
    Purpose       = "multi-tenant-isolation"
    SecurityLevel = "high"
    Compliance    = "enterprise"
  }
}