# Variables for Azure Confidential Computing and Managed HSM deployment

variable "resource_group_name" {
  description = "Name of the resource group for confidential computing resources"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-._])*[a-zA-Z0-9]$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, hyphens, and must not end with a period."
  }
}

variable "location" {
  description = "Azure region for deploying confidential computing resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "West Europe", "North Europe", "Southeast Asia",
      "Australia East", "UK South", "Canada Central", "Japan East"
    ], var.location)
    error_message = "Location must be a region that supports Azure Confidential Computing."
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "confcomp"
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.project_name))
    error_message = "Project name must be 3-10 characters, lowercase alphanumeric only."
  }
}

# Confidential VM Configuration
variable "vm_size" {
  description = "Size of the confidential virtual machine"
  type        = string
  default     = "Standard_DC4as_v5"
  
  validation {
    condition = contains([
      "Standard_DC2as_v5", "Standard_DC4as_v5", "Standard_DC8as_v5", "Standard_DC16as_v5",
      "Standard_DC32as_v5", "Standard_DC48as_v5", "Standard_DC64as_v5", "Standard_DC96as_v5",
      "Standard_EC2as_v5", "Standard_EC4as_v5", "Standard_EC8as_v5", "Standard_EC16as_v5",
      "Standard_EC32as_v5", "Standard_EC48as_v5", "Standard_EC64as_v5", "Standard_EC96as_v5"
    ], var.vm_size)
    error_message = "VM size must be a supported Azure Confidential Computing VM size."
  }
}

variable "admin_username" {
  description = "Administrator username for the confidential VM"
  type        = string
  default     = "azureuser"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{2,19}$", var.admin_username))
    error_message = "Admin username must be 3-20 characters, start with a letter, and contain only alphanumeric characters."
  }
}

variable "vm_image" {
  description = "Virtual machine image configuration for confidential VM"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-confidential-vm-jammy"
    sku       = "22_04-lts-cvm"
    version   = "latest"
  }
}

# Managed HSM Configuration
variable "hsm_sku" {
  description = "SKU for Azure Managed HSM"
  type        = string
  default     = "Standard_B1"
  
  validation {
    condition     = contains(["Standard_B1"], var.hsm_sku)
    error_message = "HSM SKU must be a valid Managed HSM SKU."
  }
}

variable "hsm_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted HSM"
  type        = number
  default     = 7
  
  validation {
    condition     = var.hsm_soft_delete_retention_days >= 7 && var.hsm_soft_delete_retention_days <= 90
    error_message = "HSM soft delete retention must be between 7 and 90 days."
  }
}

# Key Vault Configuration
variable "key_vault_sku" {
  description = "SKU for Azure Key Vault"
  type        = string
  default     = "premium"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Security Configuration
variable "enable_purge_protection" {
  description = "Enable purge protection for Key Vault and Managed HSM"
  type        = bool
  default     = false
}

variable "enable_rbac_authorization" {
  description = "Enable RBAC authorization for Key Vault"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR blocks."
  }
}

# Attestation Configuration
variable "attestation_policy" {
  description = "Custom attestation policy for SEV-SNP VMs"
  type        = string
  default     = null
}

# Networking Configuration
variable "create_virtual_network" {
  description = "Whether to create a new virtual network"
  type        = bool
  default     = true
}

variable "virtual_network_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for subnets"
  type = object({
    vm_subnet      = list(string)
    bastion_subnet = list(string)
  })
  default = {
    vm_subnet      = ["10.0.1.0/24"]
    bastion_subnet = ["10.0.2.0/24"]
  }
}

# Monitoring and Logging
variable "enable_diagnostics" {
  description = "Enable diagnostic logging for resources"
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

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Confidential Computing"
    Environment = "Demo"
    Recipe      = "azure-confidential-computing-hsm"
  }
}