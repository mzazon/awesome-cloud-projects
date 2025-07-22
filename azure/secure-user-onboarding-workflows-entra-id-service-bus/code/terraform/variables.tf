# Input Variables for User Onboarding Workflow Infrastructure
# This file defines all configurable parameters for the Azure user onboarding solution

# Environment Configuration
variable "environment" {
  description = "The environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition     = length(var.location) > 0
    error_message = "Location must not be empty."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "user-onboarding"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the resource group (will be created if not exists)"
  type        = string
  default     = ""
}

# Tagging Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "user-onboarding"
    Environment = "demo"
    Project     = "automation"
    ManagedBy   = "terraform"
  }
}

# Key Vault Configuration
variable "key_vault_sku" {
  description = "SKU for the Key Vault (standard or premium)"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault items"
  type        = number
  default     = 90
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection for Key Vault"
  type        = bool
  default     = false
}

# Service Bus Configuration
variable "service_bus_sku" {
  description = "SKU for the Service Bus namespace (Basic, Standard, Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "Service Bus SKU must be one of: Basic, Standard, Premium."
  }
}

variable "service_bus_capacity" {
  description = "Capacity for Premium Service Bus namespace (1, 2, 4, 8, 16)"
  type        = number
  default     = 1
  
  validation {
    condition     = contains([1, 2, 4, 8, 16], var.service_bus_capacity)
    error_message = "Service Bus capacity must be one of: 1, 2, 4, 8, 16."
  }
}

# Queue Configuration
variable "queue_max_delivery_count" {
  description = "Maximum number of delivery attempts for queue messages"
  type        = number
  default     = 5
  
  validation {
    condition     = var.queue_max_delivery_count >= 1 && var.queue_max_delivery_count <= 2000
    error_message = "Queue max delivery count must be between 1 and 2000."
  }
}

variable "queue_lock_duration" {
  description = "Lock duration for queue messages (ISO 8601 format)"
  type        = string
  default     = "PT5M"
  
  validation {
    condition     = can(regex("^PT[0-9]+M$", var.queue_lock_duration))
    error_message = "Queue lock duration must be in ISO 8601 format (e.g., PT5M for 5 minutes)."
  }
}

variable "queue_message_ttl" {
  description = "Time-to-live for queue messages (ISO 8601 format)"
  type        = string
  default     = "P14D"
  
  validation {
    condition     = can(regex("^P[0-9]+D$", var.queue_message_ttl))
    error_message = "Queue message TTL must be in ISO 8601 format (e.g., P14D for 14 days)."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Performance tier for the storage account (Standard or Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account (LRS, GRS, RAGRS, ZRS)"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_account_access_tier" {
  description = "Access tier for the storage account (Hot or Cool)"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_account_access_tier)
    error_message = "Storage account access tier must be either 'Hot' or 'Cool'."
  }
}

variable "storage_account_min_tls_version" {
  description = "Minimum TLS version for the storage account"
  type        = string
  default     = "TLS1_2"
  
  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.storage_account_min_tls_version)
    error_message = "Storage account minimum TLS version must be one of: TLS1_0, TLS1_1, TLS1_2."
  }
}

# Logic App Configuration
variable "logic_app_plan_sku" {
  description = "SKU for the Logic App Service Plan"
  type        = string
  default     = "WS1"
  
  validation {
    condition     = contains(["WS1", "WS2", "WS3"], var.logic_app_plan_sku)
    error_message = "Logic App plan SKU must be one of: WS1, WS2, WS3."
  }
}

variable "logic_app_plan_os_type" {
  description = "OS type for the Logic App Service Plan (Windows or Linux)"
  type        = string
  default     = "Windows"
  
  validation {
    condition     = contains(["Windows", "Linux"], var.logic_app_plan_os_type)
    error_message = "Logic App plan OS type must be either 'Windows' or 'Linux'."
  }
}

# Azure AD Application Configuration
variable "ad_app_display_name" {
  description = "Display name for the Azure AD application"
  type        = string
  default     = "User Onboarding Automation"
}

variable "ad_app_sign_in_audience" {
  description = "Sign-in audience for the Azure AD application"
  type        = string
  default     = "AzureADMyOrg"
  
  validation {
    condition = contains([
      "AzureADMyOrg",
      "AzureADMultipleOrgs",
      "AzureADandPersonalMicrosoftAccount",
      "PersonalMicrosoftAccount"
    ], var.ad_app_sign_in_audience)
    error_message = "Sign-in audience must be one of: AzureADMyOrg, AzureADMultipleOrgs, AzureADandPersonalMicrosoftAccount, PersonalMicrosoftAccount."
  }
}

# Security Configuration
variable "enable_rbac_authorization" {
  description = "Enable RBAC authorization for Key Vault"
  type        = bool
  default     = true
}

variable "enable_https_only" {
  description = "Enable HTTPS-only access for storage account"
  type        = bool
  default     = true
}

variable "enable_dead_lettering" {
  description = "Enable dead lettering for Service Bus queue"
  type        = bool
  default     = true
}

variable "enable_duplicate_detection" {
  description = "Enable duplicate detection for Service Bus topic"
  type        = bool
  default     = true
}

# Monitoring and Logging Configuration
variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain diagnostic logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
  }
}

# Network Security Configuration
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = []
}

variable "enable_private_endpoint" {
  description = "Enable private endpoints for supported resources"
  type        = bool
  default     = false
}

# Backup and Recovery Configuration
variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

# Cost Optimization Configuration
variable "auto_shutdown_enabled" {
  description = "Enable auto-shutdown for development environments"
  type        = bool
  default     = false
}

variable "auto_shutdown_time" {
  description = "Auto-shutdown time in 24-hour format (e.g., 1900 for 7:00 PM)"
  type        = string
  default     = "1900"
  
  validation {
    condition     = can(regex("^[0-2][0-9][0-5][0-9]$", var.auto_shutdown_time))
    error_message = "Auto-shutdown time must be in 24-hour format (e.g., 1900 for 7:00 PM)."
  }
}