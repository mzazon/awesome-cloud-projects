# Input Variables for Azure Network Security Orchestration
# This file defines all configurable parameters for the solution

variable "resource_group_name" {
  description = "Name of the Azure resource group to create"
  type        = string
  default     = "rg-security-orchestration"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,90}$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters and contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India", "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.environment))
    error_message = "Environment must be 2-10 characters and contain only lowercase letters and numbers."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "security-orchestration"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Security Orchestration"
    Environment = "Demo"
    ManagedBy   = "Terraform"
  }
}

# Network Configuration Variables
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = can([for cidr in var.vnet_address_space : cidrhost(cidr, 0)])
    error_message = "All values in vnet_address_space must be valid CIDR notation."
  }
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for subnets"
  type        = map(string)
  default = {
    protected = "10.0.1.0/24"
    management = "10.0.2.0/24"
  }
  
  validation {
    condition     = can([for prefix in values(var.subnet_address_prefixes) : cidrhost(prefix, 0)])
    error_message = "All subnet address prefixes must be valid CIDR notation."
  }
}

# Security Configuration Variables
variable "allowed_source_addresses" {
  description = "List of allowed source IP addresses for management access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition     = can([for addr in var.allowed_source_addresses : cidrhost(addr, 0)])
    error_message = "All allowed source addresses must be valid CIDR notation."
  }
}

variable "threat_intel_api_key" {
  description = "API key for threat intelligence service (stored in Key Vault)"
  type        = string
  default     = "sample-api-key-for-threat-feeds"
  sensitive   = true
}

# Storage Configuration Variables
variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Key Vault Configuration Variables
variable "key_vault_sku" {
  description = "SKU for Key Vault"
  type        = string
  default     = "standard"
  
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
    error_message = "Key Vault soft delete retention days must be between 7 and 90."
  }
}

# Log Analytics Configuration Variables
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standalone, Standard, Premium."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain Log Analytics data"
  type        = number
  default     = 90
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}

# Logic Apps Configuration Variables
variable "logic_app_state" {
  description = "State of the Logic Apps workflow"
  type        = string
  default     = "Enabled"
  
  validation {
    condition     = contains(["Enabled", "Disabled"], var.logic_app_state)
    error_message = "Logic Apps state must be either 'Enabled' or 'Disabled'."
  }
}

# Monitoring Configuration Variables
variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for all resources"
  type        = bool
  default     = true
}

variable "diagnostic_logs_retention_days" {
  description = "Number of days to retain diagnostic logs"
  type        = number
  default     = 90
  
  validation {
    condition     = var.diagnostic_logs_retention_days >= 1 && var.diagnostic_logs_retention_days <= 365
    error_message = "Diagnostic logs retention days must be between 1 and 365."
  }
}

# Security Rules Configuration
variable "default_security_rules" {
  description = "Default security rules to apply to Network Security Groups"
  type = map(object({
    priority                     = number
    direction                    = string
    access                      = string
    protocol                    = string
    source_port_range           = string
    destination_port_range      = string
    source_address_prefix       = string
    destination_address_prefix  = string
    description                 = string
  }))
  default = {
    allow_https_inbound = {
      priority                   = 1000
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
      description                = "Allow HTTPS inbound traffic"
    }
    allow_ssh_inbound = {
      priority                   = 1010
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
      description                = "Allow SSH inbound traffic"
    }
    deny_all_inbound = {
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
      description                = "Deny all other inbound traffic"
    }
  }
}

# Random Suffix Configuration
variable "use_random_suffix" {
  description = "Use random suffix for resource names to ensure uniqueness"
  type        = bool
  default     = true
}