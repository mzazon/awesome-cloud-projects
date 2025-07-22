# Core Infrastructure Variables
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
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group for AVD infrastructure"
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    Project     = "Azure Virtual Desktop"
    ManagedBy   = "Terraform"
    Purpose     = "Virtual Desktop Infrastructure"
  }
}

# Networking Variables
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "avd_subnet_address_prefix" {
  description = "Address prefix for the AVD subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "bastion_subnet_address_prefix" {
  description = "Address prefix for the Azure Bastion subnet"
  type        = string
  default     = "10.0.2.0/27"
  
  validation {
    condition     = can(cidrnetmask(var.bastion_subnet_address_prefix)) && tonumber(split("/", var.bastion_subnet_address_prefix)[1]) >= 26
    error_message = "Bastion subnet must be at least /27 in size."
  }
}

# Azure Virtual Desktop Variables
variable "host_pool_type" {
  description = "Type of the host pool (Personal or Pooled)"
  type        = string
  default     = "Pooled"
  
  validation {
    condition     = contains(["Personal", "Pooled"], var.host_pool_type)
    error_message = "Host pool type must be either Personal or Pooled."
  }
}

variable "load_balancer_type" {
  description = "Load balancer type for pooled host pools"
  type        = string
  default     = "BreadthFirst"
  
  validation {
    condition     = contains(["BreadthFirst", "DepthFirst"], var.load_balancer_type)
    error_message = "Load balancer type must be either BreadthFirst or DepthFirst."
  }
}

variable "max_session_limit" {
  description = "Maximum number of sessions per session host"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_session_limit >= 1 && var.max_session_limit <= 50
    error_message = "Max session limit must be between 1 and 50."
  }
}

variable "start_vm_on_connect" {
  description = "Enable start VM on connect feature"
  type        = bool
  default     = false
}

variable "preferred_app_group_type" {
  description = "Preferred application group type for the host pool"
  type        = string
  default     = "Desktop"
  
  validation {
    condition     = contains(["Desktop", "RailApplications"], var.preferred_app_group_type)
    error_message = "Preferred app group type must be either Desktop or RailApplications."
  }
}

# Session Host Variables
variable "session_host_count" {
  description = "Number of session host VMs to create"
  type        = number
  default     = 2
  
  validation {
    condition     = var.session_host_count >= 1 && var.session_host_count <= 10
    error_message = "Session host count must be between 1 and 10."
  }
}

variable "session_host_vm_size" {
  description = "Size of the session host virtual machines"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "session_host_image" {
  description = "VM image configuration for session hosts"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-11"
    sku       = "win11-22h2-ent"
    version   = "latest"
  }
}

variable "session_host_admin_username" {
  description = "Administrator username for session host VMs"
  type        = string
  default     = "avdadmin"
  
  validation {
    condition     = length(var.session_host_admin_username) >= 3 && length(var.session_host_admin_username) <= 20
    error_message = "Admin username must be between 3 and 20 characters."
  }
}

variable "session_host_admin_password" {
  description = "Administrator password for session host VMs (if not using Key Vault)"
  type        = string
  default     = null
  sensitive   = true
}

# Azure Bastion Variables
variable "bastion_sku" {
  description = "SKU for Azure Bastion"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard"], var.bastion_sku)
    error_message = "Bastion SKU must be either Basic or Standard."
  }
}

variable "bastion_copy_paste_enabled" {
  description = "Enable copy/paste feature for Azure Bastion"
  type        = bool
  default     = true
}

variable "bastion_file_copy_enabled" {
  description = "Enable file copy feature for Azure Bastion (Standard SKU only)"
  type        = bool
  default     = false
}

variable "bastion_ip_connect_enabled" {
  description = "Enable IP connect feature for Azure Bastion (Standard SKU only)"
  type        = bool
  default     = false
}

variable "bastion_shareable_link_enabled" {
  description = "Enable shareable link feature for Azure Bastion (Standard SKU only)"
  type        = bool
  default     = false
}

variable "bastion_tunneling_enabled" {
  description = "Enable tunneling feature for Azure Bastion (Standard SKU only)"
  type        = bool
  default     = false
}

# Key Vault Variables
variable "key_vault_sku_name" {
  description = "SKU name for the Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku_name)
    error_message = "Key Vault SKU must be either standard or premium."
  }
}

variable "key_vault_enabled_for_disk_encryption" {
  description = "Enable Key Vault for disk encryption"
  type        = bool
  default     = true
}

variable "key_vault_enabled_for_template_deployment" {
  description = "Enable Key Vault for template deployment"
  type        = bool
  default     = true
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection for Key Vault"
  type        = bool
  default     = false
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault items"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

# Certificate Variables
variable "certificate_subject" {
  description = "Subject for the SSL certificate"
  type        = string
  default     = null
}

variable "certificate_validity_months" {
  description = "Validity period for the SSL certificate in months"
  type        = number
  default     = 12
  
  validation {
    condition     = var.certificate_validity_months >= 1 && var.certificate_validity_months <= 120
    error_message = "Certificate validity must be between 1 and 120 months."
  }
}

# Active Directory Variables
variable "domain_name" {
  description = "Active Directory domain name for domain join (optional)"
  type        = string
  default     = null
}

variable "domain_user_upn" {
  description = "Domain user UPN for domain join operations"
  type        = string
  default     = null
}

variable "domain_password" {
  description = "Domain user password for domain join operations"
  type        = string
  default     = null
  sensitive   = true
}

variable "ou_path" {
  description = "Organizational Unit path for domain-joined VMs"
  type        = string
  default     = null
}

# Naming Convention Variables
variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "avd"
  
  validation {
    condition     = length(var.name_prefix) <= 10 && can(regex("^[a-z0-9]+$", var.name_prefix))
    error_message = "Name prefix must be lowercase alphanumeric and max 10 characters."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 3 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 3 and 10."
  }
}