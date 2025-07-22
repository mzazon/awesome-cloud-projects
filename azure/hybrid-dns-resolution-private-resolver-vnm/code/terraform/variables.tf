# Variables for Azure Hybrid DNS Resolution Infrastructure
# This file defines all configurable parameters for the hybrid DNS solution

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
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia", "Central India",
      "South India", "West India", "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create for all resources"
  type        = string
  default     = ""
  
  validation {
    condition     = length(var.resource_group_name) <= 90
    error_message = "Resource group name must be 90 characters or less."
  }
}

variable "environment" {
  description = "Environment designation for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition = contains([
      "dev", "test", "staging", "prod", "demo"
    ], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "hybrid-dns"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Network Configuration Variables
variable "hub_vnet_address_space" {
  description = "Address space for the hub virtual network"
  type        = list(string)
  default     = ["10.10.0.0/16"]
  
  validation {
    condition     = length(var.hub_vnet_address_space) > 0
    error_message = "At least one address space must be specified for the hub VNet."
  }
}

variable "spoke1_vnet_address_space" {
  description = "Address space for the first spoke virtual network"
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

variable "spoke2_vnet_address_space" {
  description = "Address space for the second spoke virtual network"
  type        = list(string)
  default     = ["10.30.0.0/16"]
}

variable "dns_inbound_subnet_address_prefix" {
  description = "Address prefix for the DNS resolver inbound subnet"
  type        = string
  default     = "10.10.0.0/24"
  
  validation {
    condition     = can(cidrhost(var.dns_inbound_subnet_address_prefix, 0))
    error_message = "DNS inbound subnet address prefix must be a valid CIDR block."
  }
}

variable "dns_outbound_subnet_address_prefix" {
  description = "Address prefix for the DNS resolver outbound subnet"
  type        = string
  default     = "10.10.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.dns_outbound_subnet_address_prefix, 0))
    error_message = "DNS outbound subnet address prefix must be a valid CIDR block."
  }
}

variable "spoke1_subnet_address_prefix" {
  description = "Address prefix for the first spoke subnet"
  type        = string
  default     = "10.20.0.0/24"
}

variable "spoke2_subnet_address_prefix" {
  description = "Address prefix for the second spoke subnet"
  type        = string
  default     = "10.30.0.0/24"
}

# DNS Configuration Variables
variable "private_dns_zone_name" {
  description = "Name of the private DNS zone for Azure resources"
  type        = string
  default     = "azure.contoso.com"
  
  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.private_dns_zone_name))
    error_message = "Private DNS zone name must be a valid domain name with lowercase letters, numbers, dots, and hyphens."
  }
}

variable "onprem_dns_servers" {
  description = "List of on-premises DNS servers for forwarding rules"
  type = list(object({
    ip_address = string
    port       = optional(number, 53)
  }))
  default = [
    {
      ip_address = "10.100.0.2"
      port       = 53
    }
  ]
  
  validation {
    condition     = length(var.onprem_dns_servers) > 0
    error_message = "At least one on-premises DNS server must be specified."
  }
}

variable "onprem_domain_name" {
  description = "On-premises domain name for DNS forwarding rules"
  type        = string
  default     = "contoso.com"
  
  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.onprem_domain_name))
    error_message = "On-premises domain name must be a valid domain name with lowercase letters, numbers, dots, and hyphens."
  }
}

# Virtual Network Manager Configuration
variable "enable_direct_connectivity" {
  description = "Enable direct connectivity between spoke networks"
  type        = bool
  default     = false
}

variable "use_hub_gateway" {
  description = "Enable hub gateway usage for spoke networks"
  type        = bool
  default     = false
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains([
      "Standard", "Premium"
    ], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains([
      "LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"
    ], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Test VM Configuration
variable "create_test_vm" {
  description = "Whether to create a test VM for DNS validation"
  type        = bool
  default     = true
}

variable "vm_size" {
  description = "Size of the test virtual machine"
  type        = string
  default     = "Standard_B1s"
  
  validation {
    condition = contains([
      "Standard_B1s", "Standard_B1ms", "Standard_B2s", "Standard_B2ms",
      "Standard_DS1_v2", "Standard_DS2_v2", "Standard_D2s_v3"
    ], var.vm_size)
    error_message = "VM size must be a valid Azure VM size for testing purposes."
  }
}

variable "admin_username" {
  description = "Administrator username for the test VM"
  type        = string
  default     = "azureuser"
  
  validation {
    condition     = length(var.admin_username) >= 1 && length(var.admin_username) <= 20
    error_message = "Admin username must be between 1 and 20 characters."
  }
}

# Tagging Variables
variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    Purpose     = "Hybrid DNS Resolution"
    DeployedBy  = "Terraform"
    Recipe      = "Azure DNS Private Resolver with Virtual Network Manager"
  }
}

# Cost Management Variables
variable "enable_cost_alerts" {
  description = "Enable cost management alerts for the resource group"
  type        = bool
  default     = false
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD for cost alerts"
  type        = number
  default     = 100
  
  validation {
    condition     = var.monthly_budget_limit > 0
    error_message = "Monthly budget limit must be greater than 0."
  }
}