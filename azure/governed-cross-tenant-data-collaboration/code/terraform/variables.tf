# Core deployment variables
variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase letters and numbers."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "datashare"
  
  validation {
    condition = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters and numbers."
  }
}

# Provider tenant configuration
variable "provider_tenant_id" {
  description = "Azure AD tenant ID for the data provider"
  type        = string
  
  validation {
    condition = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.provider_tenant_id))
    error_message = "Provider tenant ID must be a valid UUID."
  }
}

variable "provider_subscription_id" {
  description = "Azure subscription ID for the data provider"
  type        = string
  
  validation {
    condition = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.provider_subscription_id))
    error_message = "Provider subscription ID must be a valid UUID."
  }
}

# Consumer tenant configuration
variable "consumer_tenant_id" {
  description = "Azure AD tenant ID for the data consumer"
  type        = string
  
  validation {
    condition = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.consumer_tenant_id))
    error_message = "Consumer tenant ID must be a valid UUID."
  }
}

variable "consumer_subscription_id" {
  description = "Azure subscription ID for the data consumer"
  type        = string
  
  validation {
    condition = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.consumer_subscription_id))
    error_message = "Consumer subscription ID must be a valid UUID."
  }
}

# Storage configuration
variable "storage_account_tier" {
  description = "Storage account tier (Standard or Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be a valid Azure storage replication option."
  }
}

variable "enable_hierarchical_namespace" {
  description = "Enable hierarchical namespace for Azure Data Lake Storage Gen2"
  type        = bool
  default     = true
}

# Data Share configuration
variable "data_share_name" {
  description = "Name of the data share"
  type        = string
  default     = "cross-tenant-dataset"
}

variable "data_share_description" {
  description = "Description of the data share"
  type        = string
  default     = "Cross-tenant collaborative dataset for secure data sharing"
}

variable "data_share_terms" {
  description = "Terms and conditions for the data share"
  type        = string
  default     = "Standard data sharing terms apply. Data usage must comply with organizational policies."
}

# Purview configuration
variable "purview_sku" {
  description = "Purview account SKU (capacity units)"
  type        = string
  default     = "Standard_4"
  
  validation {
    condition = contains(["Standard_4", "Standard_16"], var.purview_sku)
    error_message = "Purview SKU must be Standard_4 or Standard_16."
  }
}

variable "purview_managed_resource_group_name" {
  description = "Name of the managed resource group for Purview"
  type        = string
  default     = null
}

# Networking configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security"
  type        = bool
  default     = false
}

variable "virtual_network_address_space" {
  description = "Address space for the virtual network (if private endpoints enabled)"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for subnets (if private endpoints enabled)"
  type        = map(string)
  default = {
    storage = "10.0.1.0/24"
    purview = "10.0.2.0/24"
    datashare = "10.0.3.0/24"
  }
}

# Tagging configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Cross-tenant data collaboration"
    ManagedBy   = "Terraform"
    Environment = "dev"
  }
}

# B2B collaboration configuration
variable "consumer_email" {
  description = "Email address of the consumer for B2B invitation"
  type        = string
  default     = ""
  
  validation {
    condition = var.consumer_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.consumer_email))
    error_message = "Consumer email must be a valid email address or empty string."
  }
}

# Security configuration
variable "enable_soft_delete" {
  description = "Enable soft delete for storage accounts"
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft deleted data"
  type        = number
  default     = 7
  
  validation {
    condition = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365
    error_message = "Soft delete retention days must be between 1 and 365."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for storage accounts"
  type        = bool
  default     = true
}

# Monitoring configuration
variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for monitoring"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic logs"
  type        = string
  default     = null
}