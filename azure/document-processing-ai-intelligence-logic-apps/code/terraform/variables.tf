# Variables for the intelligent document processing solution

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "The location must be a valid Azure region name."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group. If not provided, will be auto-generated"
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment designation (e.g., dev, test, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.environment))
    error_message = "Environment must be 2-10 characters, lowercase letters and numbers only."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "docprocessing"
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,15}$", var.project_name))
    error_message = "Project name must be 3-15 characters, lowercase letters and numbers only."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Performance tier of the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Type of replication for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_account_access_tier" {
  description = "Access tier for the storage account"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_account_access_tier)
    error_message = "Storage account access tier must be either Hot or Cool."
  }
}

# Document Intelligence Configuration
variable "document_intelligence_sku" {
  description = "SKU for Azure AI Document Intelligence service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.document_intelligence_sku)
    error_message = "Document Intelligence SKU must be either F0 (free) or S0 (standard)."
  }
}

# Key Vault Configuration
variable "key_vault_sku" {
  description = "SKU for Azure Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either standard or premium."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted keys in Key Vault"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention days must be between 7 and 90."
  }
}

# Service Bus Configuration
variable "service_bus_sku" {
  description = "SKU for Azure Service Bus"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "Service Bus SKU must be either Basic, Standard, or Premium."
  }
}

variable "service_bus_queue_max_size" {
  description = "Maximum size of the Service Bus queue in MB"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.service_bus_queue_max_size >= 1024 && var.service_bus_queue_max_size <= 5120
    error_message = "Service Bus queue max size must be between 1024 and 5120 MB."
  }
}

variable "service_bus_message_ttl" {
  description = "Time to live for messages in the Service Bus queue (ISO 8601 format)"
  type        = string
  default     = "P7D"
  
  validation {
    condition     = can(regex("^P[0-9]+D$", var.service_bus_message_ttl))
    error_message = "Service Bus message TTL must be in ISO 8601 format (e.g., P7D for 7 days)."
  }
}

# Logic App Configuration
variable "logic_app_workflow_enabled" {
  description = "Whether the Logic App workflow is enabled"
  type        = bool
  default     = true
}

# Security Configuration
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access storage account (CIDR notation)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be in valid CIDR notation (e.g., 10.0.0.0/8)."
  }
}

variable "enable_public_access" {
  description = "Whether to enable public access to storage account"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_application_insights" {
  description = "Whether to enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "application_insights_type" {
  description = "Type of Application Insights instance"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either 'web' or 'other'."
  }
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "document-processing"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
  
  validation {
    condition     = length(var.tags) <= 15
    error_message = "Maximum of 15 tags allowed per resource."
  }
}