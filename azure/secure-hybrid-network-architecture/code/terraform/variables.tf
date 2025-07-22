# General Configuration Variables
variable "location" {
  type        = string
  description = "Azure region for all resources"
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase letters and numbers."
  }
}

variable "project_name" {
  type        = string
  description = "Project name used for resource naming"
  default     = "hybrid-network"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Network Configuration Variables
variable "hub_vnet_address_space" {
  type        = list(string)
  description = "Address space for the hub virtual network"
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = length(var.hub_vnet_address_space) > 0
    error_message = "At least one address space must be specified for the hub VNet."
  }
}

variable "spoke_vnet_address_space" {
  type        = list(string)
  description = "Address space for the spoke virtual network"
  default     = ["10.1.0.0/16"]
  
  validation {
    condition     = length(var.spoke_vnet_address_space) > 0
    error_message = "At least one address space must be specified for the spoke VNet."
  }
}

variable "gateway_subnet_address_prefix" {
  type        = string
  description = "Address prefix for the gateway subnet (minimum /27)"
  default     = "10.0.1.0/27"
  
  validation {
    condition     = can(cidrhost(var.gateway_subnet_address_prefix, 0))
    error_message = "Gateway subnet address prefix must be a valid CIDR block."
  }
}

variable "application_subnet_address_prefix" {
  type        = string
  description = "Address prefix for the application subnet"
  default     = "10.1.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.application_subnet_address_prefix, 0))
    error_message = "Application subnet address prefix must be a valid CIDR block."
  }
}

variable "private_endpoint_subnet_address_prefix" {
  type        = string
  description = "Address prefix for the private endpoint subnet"
  default     = "10.1.2.0/24"
  
  validation {
    condition     = can(cidrhost(var.private_endpoint_subnet_address_prefix, 0))
    error_message = "Private endpoint subnet address prefix must be a valid CIDR block."
  }
}

# VPN Gateway Configuration Variables
variable "vpn_gateway_sku" {
  type        = string
  description = "SKU for the VPN Gateway (Basic, VpnGw1, VpnGw2, VpnGw3, VpnGw4, VpnGw5)"
  default     = "Basic"
  
  validation {
    condition = contains([
      "Basic", "VpnGw1", "VpnGw2", "VpnGw3", "VpnGw4", "VpnGw5",
      "VpnGw1AZ", "VpnGw2AZ", "VpnGw3AZ", "VpnGw4AZ", "VpnGw5AZ"
    ], var.vpn_gateway_sku)
    error_message = "VPN Gateway SKU must be a valid Azure VPN Gateway SKU."
  }
}

variable "vpn_type" {
  type        = string
  description = "VPN type for the gateway (RouteBased or PolicyBased)"
  default     = "RouteBased"
  
  validation {
    condition     = contains(["RouteBased", "PolicyBased"], var.vpn_type)
    error_message = "VPN type must be either RouteBased or PolicyBased."
  }
}

variable "enable_bgp" {
  type        = bool
  description = "Enable BGP for the VPN Gateway"
  default     = false
}

variable "on_premises_gateway_ip" {
  type        = string
  description = "Public IP address of the on-premises VPN gateway (optional for simulation)"
  default     = null
  
  validation {
    condition     = var.on_premises_gateway_ip == null || can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.on_premises_gateway_ip))
    error_message = "On-premises gateway IP must be a valid IPv4 address or null."
  }
}

variable "on_premises_address_space" {
  type        = list(string)
  description = "Address space for on-premises networks"
  default     = ["192.168.0.0/16"]
  
  validation {
    condition     = length(var.on_premises_address_space) > 0
    error_message = "At least one on-premises address space must be specified."
  }
}

# Key Vault Configuration Variables
variable "key_vault_sku" {
  type        = string
  description = "SKU for the Key Vault (standard or premium)"
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either standard or premium."
  }
}

variable "enable_rbac_authorization" {
  type        = bool
  description = "Enable RBAC authorization for Key Vault"
  default     = true
}

variable "key_vault_soft_delete_retention_days" {
  type        = number
  description = "Number of days to retain soft-deleted Key Vault items"
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention days must be between 7 and 90."
  }
}

# Storage Account Configuration Variables
variable "storage_account_tier" {
  type        = string
  description = "Performance tier for the storage account (Standard or Premium)"
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  type        = string
  description = "Replication type for the storage account"
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be a valid Azure replication type."
  }
}

variable "storage_account_kind" {
  type        = string
  description = "Kind of storage account (Storage, StorageV2, BlobStorage, FileStorage, BlockBlobStorage)"
  default     = "StorageV2"
  
  validation {
    condition     = contains(["Storage", "StorageV2", "BlobStorage", "FileStorage", "BlockBlobStorage"], var.storage_account_kind)
    error_message = "Storage account kind must be a valid Azure storage account kind."
  }
}

# Virtual Machine Configuration Variables
variable "enable_test_vm" {
  type        = bool
  description = "Enable creation of test virtual machine"
  default     = true
}

variable "vm_size" {
  type        = string
  description = "Size of the test virtual machine"
  default     = "Standard_B2s"
  
  validation {
    condition     = can(regex("^Standard_[A-Z][0-9]+[a-z]*$", var.vm_size))
    error_message = "VM size must be a valid Azure VM size."
  }
}

variable "vm_admin_username" {
  type        = string
  description = "Admin username for the test virtual machine"
  default     = "azureuser"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,19}$", var.vm_admin_username))
    error_message = "VM admin username must start with a letter and be 1-20 characters long."
  }
}

variable "vm_disable_password_authentication" {
  type        = bool
  description = "Disable password authentication for the VM (SSH key authentication only)"
  default     = true
}

# Resource Tagging Variables
variable "additional_tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}

variable "enable_private_dns_zones" {
  type        = bool
  description = "Enable creation of private DNS zones for private endpoints"
  default     = true
}

variable "create_local_network_gateway" {
  type        = bool
  description = "Create local network gateway for on-premises connection simulation"
  default     = false
}