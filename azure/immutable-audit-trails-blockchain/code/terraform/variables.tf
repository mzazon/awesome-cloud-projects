# Variables for Azure Confidential Ledger Audit Trail Infrastructure
# This file defines all customizable parameters for the audit trail solution

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  validation {
    condition     = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group for audit trail resources"
  type        = string
  default     = "rg-audit-trail"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.()]+$", var.resource_group_name))
    error_message = "Resource group name must follow Azure naming conventions."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "audit-trail"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Confidential Ledger Configuration
variable "ledger_type" {
  description = "Type of Confidential Ledger (Public or Private)"
  type        = string
  default     = "Public"
  validation {
    condition     = contains(["Public", "Private"], var.ledger_type)
    error_message = "Ledger type must be either 'Public' or 'Private'."
  }
}

# Key Vault Configuration
variable "key_vault_sku" {
  description = "SKU for Key Vault (standard or premium)"
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "key_vault_retention_days" {
  description = "Number of days to retain deleted Key Vault objects"
  type        = number
  default     = 90
  validation {
    condition     = var.key_vault_retention_days >= 7 && var.key_vault_retention_days <= 90
    error_message = "Key Vault retention days must be between 7 and 90."
  }
}

# Event Hub Configuration
variable "event_hub_sku" {
  description = "SKU for Event Hub Namespace (Basic, Standard, Dedicated)"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Basic", "Standard", "Dedicated"], var.event_hub_sku)
    error_message = "Event Hub SKU must be Basic, Standard, or Dedicated."
  }
}

variable "event_hub_capacity" {
  description = "Throughput units for Event Hub Namespace"
  type        = number
  default     = 1
  validation {
    condition     = var.event_hub_capacity >= 1 && var.event_hub_capacity <= 20
    error_message = "Event Hub capacity must be between 1 and 20."
  }
}

variable "event_hub_partition_count" {
  description = "Number of partitions for Event Hub"
  type        = number
  default     = 4
  validation {
    condition     = var.event_hub_partition_count >= 1 && var.event_hub_partition_count <= 32
    error_message = "Event Hub partition count must be between 1 and 32."
  }
}

variable "event_hub_retention_days" {
  description = "Message retention period in days for Event Hub"
  type        = number
  default     = 1
  validation {
    condition     = var.event_hub_retention_days >= 1 && var.event_hub_retention_days <= 7
    error_message = "Event Hub retention days must be between 1 and 7."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Storage account tier (Standard or Premium)"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be LRS, GRS, RAGRS, or ZRS."
  }
}

variable "storage_container_name" {
  description = "Name of the storage container for audit archives"
  type        = string
  default     = "audit-archive"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.storage_container_name))
    error_message = "Storage container name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Logic App Configuration
variable "logic_app_definition" {
  description = "Logic App workflow definition as JSON string"
  type        = string
  default     = null
}

# Security Configuration
variable "admin_object_ids" {
  description = "List of Azure AD object IDs for admin users"
  type        = list(string)
  default     = []
}

variable "reader_object_ids" {
  description = "List of Azure AD object IDs for read-only users"
  type        = list(string)
  default     = []
}

# Tagging Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "audit-trail"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Advanced Configuration
variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for resources"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic settings"
  type        = string
  default     = null
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security"
  type        = bool
  default     = false
}

variable "virtual_network_id" {
  description = "Virtual network ID for private endpoints"
  type        = string
  default     = null
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoints"
  type        = string
  default     = null
}