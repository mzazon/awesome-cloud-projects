# variables.tf - Input variables for the zero-trust backup security solution
# This file defines all configurable parameters for the Terraform deployment

# Basic Configuration Variables
variable "location" {
  description = "The Azure region where resources will be deployed"
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
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase letters and numbers."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "zerotrust-backup"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Azure Tenant Configuration
variable "tenant_id" {
  description = "Azure Active Directory tenant ID"
  type        = string
  
  validation {
    condition     = can(regex("^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$", var.tenant_id))
    error_message = "Tenant ID must be a valid GUID format."
  }
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  
  validation {
    condition     = can(regex("^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$", var.subscription_id))
    error_message = "Subscription ID must be a valid GUID format."
  }
}

# Resource Naming Variables
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = ""
}

variable "key_vault_name" {
  description = "Name of the Key Vault (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "workload_identity_name" {
  description = "Name of the workload identity (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "recovery_vault_name" {
  description = "Name of the Recovery Services Vault (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "storage_account_name" {
  description = "Name of the storage account (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "vm_name" {
  description = "Name of the test virtual machine (leave empty for auto-generation)"
  type        = string
  default     = ""
}

# Network Configuration Variables
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition = length(var.vnet_address_space) > 0
    error_message = "At least one address space must be provided."
  }
}

variable "subnet_address_prefix" {
  description = "Address prefix for the subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition = can(cidrhost(var.subnet_address_prefix, 0))
    error_message = "Subnet address prefix must be a valid CIDR block."
  }
}

# Virtual Machine Configuration Variables
variable "vm_size" {
  description = "Size of the virtual machine"
  type        = string
  default     = "Standard_B2s"
  
  validation {
    condition = can(regex("^Standard_", var.vm_size))
    error_message = "VM size must be a valid Azure VM size."
  }
}

variable "vm_admin_username" {
  description = "Administrator username for the virtual machine"
  type        = string
  default     = "azureuser"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.vm_admin_username))
    error_message = "Admin username must start with a letter and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "vm_admin_password" {
  description = "Administrator password for the virtual machine"
  type        = string
  sensitive   = true
  default     = "SecurePassword123!"
  
  validation {
    condition     = length(var.vm_admin_password) >= 12
    error_message = "Password must be at least 12 characters long."
  }
}

variable "vm_source_image_reference" {
  description = "Source image reference for the virtual machine"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
}

# Key Vault Configuration Variables
variable "key_vault_sku" {
  description = "SKU for the Key Vault"
  type        = string
  default     = "premium"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault objects"
  type        = number
  default     = 90
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

# Recovery Services Vault Configuration Variables
variable "recovery_vault_storage_mode_type" {
  description = "Storage mode type for the Recovery Services Vault"
  type        = string
  default     = "GeoRedundant"
  
  validation {
    condition     = contains(["GeoRedundant", "LocallyRedundant", "ReadAccessGeoRedundant"], var.recovery_vault_storage_mode_type)
    error_message = "Storage mode type must be GeoRedundant, LocallyRedundant, or ReadAccessGeoRedundant."
  }
}

variable "recovery_vault_cross_region_restore_enabled" {
  description = "Enable cross-region restore for the Recovery Services Vault"
  type        = bool
  default     = true
}

variable "recovery_vault_soft_delete_enabled" {
  description = "Enable soft delete for the Recovery Services Vault"
  type        = bool
  default     = true
}

# Storage Account Configuration Variables
variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
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
    error_message = "Storage account access tier must be either 'Hot' or 'Cool'."
  }
}

variable "storage_account_min_tls_version" {
  description = "Minimum TLS version for the storage account"
  type        = string
  default     = "TLS1_2"
  
  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.storage_account_min_tls_version)
    error_message = "Minimum TLS version must be TLS1_0, TLS1_1, or TLS1_2."
  }
}

# Backup Policy Configuration Variables
variable "backup_policy_vm_daily_retention_days" {
  description = "Number of days to retain daily VM backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_policy_vm_daily_retention_days >= 1 && var.backup_policy_vm_daily_retention_days <= 9999
    error_message = "Daily retention days must be between 1 and 9999."
  }
}

variable "backup_policy_vm_weekly_retention_weeks" {
  description = "Number of weeks to retain weekly VM backups"
  type        = number
  default     = 12
  
  validation {
    condition     = var.backup_policy_vm_weekly_retention_weeks >= 1 && var.backup_policy_vm_weekly_retention_weeks <= 5163
    error_message = "Weekly retention weeks must be between 1 and 5163."
  }
}

variable "backup_policy_vm_monthly_retention_months" {
  description = "Number of months to retain monthly VM backups"
  type        = number
  default     = 12
  
  validation {
    condition     = var.backup_policy_vm_monthly_retention_months >= 1 && var.backup_policy_vm_monthly_retention_months <= 1188
    error_message = "Monthly retention months must be between 1 and 1188."
  }
}

variable "backup_policy_vm_schedule_run_times" {
  description = "Time of day to run VM backups (HH:MM format)"
  type        = list(string)
  default     = ["02:00"]
  
  validation {
    condition = length(var.backup_policy_vm_schedule_run_times) > 0
    error_message = "At least one backup time must be specified."
  }
}

# Federated Identity Configuration Variables
variable "federated_identity_credentials" {
  description = "List of federated identity credentials to create"
  type = list(object({
    name        = string
    issuer      = string
    subject     = string
    audience    = list(string)
    description = string
  }))
  default = [
    {
      name        = "github-actions-fed-cred"
      issuer      = "https://token.actions.githubusercontent.com"
      subject     = "repo:organization/repository:ref:refs/heads/main"
      audience    = ["api://AzureADTokenExchange"]
      description = "Federated credential for GitHub Actions backup automation"
    },
    {
      name        = "k8s-backup-fed-cred"
      issuer      = "https://kubernetes.default.svc.cluster.local"
      subject     = "system:serviceaccount:backup-system:backup-operator"
      audience    = ["api://AzureADTokenExchange"]
      description = "Federated credential for Kubernetes backup operations"
    }
  ]
}

# Tagging Variables
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose         = "zero-trust-backup"
    Environment     = "demo"
    SecurityLevel   = "high"
    Compliance      = "required"
    CreatedBy       = "terraform"
    ProjectName     = "zerotrust-backup"
  }
}

# Feature Flags
variable "enable_vm_creation" {
  description = "Enable creation of test virtual machine"
  type        = bool
  default     = true
}

variable "enable_backup_protection" {
  description = "Enable backup protection for the test VM"
  type        = bool
  default     = true
}

variable "enable_federated_credentials" {
  description = "Enable creation of federated identity credentials"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable monitoring and Log Analytics workspace"
  type        = bool
  default     = true
}

# Security Configuration Variables
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access Key Vault"
  type        = list(string)
  default     = []
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint for Key Vault"
  type        = bool
  default     = false
}

variable "certificate_validity_months" {
  description = "Validity period in months for generated certificates"
  type        = number
  default     = 12
  
  validation {
    condition     = var.certificate_validity_months >= 1 && var.certificate_validity_months <= 24
    error_message = "Certificate validity must be between 1 and 24 months."
  }
}