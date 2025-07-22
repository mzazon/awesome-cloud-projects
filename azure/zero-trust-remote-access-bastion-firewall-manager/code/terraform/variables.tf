# General configuration variables
variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Japan East", "Japan West",
      "Southeast Asia", "East Asia", "India Central",
      "Korea Central", "Brazil South", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase letters and numbers."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "zerotrust"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters and numbers."
  }
}

# Network configuration variables
variable "hub_vnet_address_space" {
  description = "Address space for the hub virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "bastion_subnet_address_prefix" {
  description = "Address prefix for Azure Bastion subnet (must be /26 or larger)"
  type        = string
  default     = "10.0.1.0/26"
  
  validation {
    condition     = can(cidrhost(var.bastion_subnet_address_prefix, 0))
    error_message = "Bastion subnet address prefix must be a valid CIDR block."
  }
}

variable "firewall_subnet_address_prefix" {
  description = "Address prefix for Azure Firewall subnet (must be /24 or larger)"
  type        = string
  default     = "10.0.2.0/24"
  
  validation {
    condition     = can(cidrhost(var.firewall_subnet_address_prefix, 0))
    error_message = "Firewall subnet address prefix must be a valid CIDR block."
  }
}

variable "spoke_vnets" {
  description = "Configuration for spoke virtual networks"
  type = map(object({
    address_space = list(string)
    subnets = map(object({
      address_prefix = string
    }))
  }))
  default = {
    prod = {
      address_space = ["10.1.0.0/16"]
      subnets = {
        workload = {
          address_prefix = "10.1.1.0/24"
        }
      }
    }
    dev = {
      address_space = ["10.2.0.0/16"]
      subnets = {
        workload = {
          address_prefix = "10.2.1.0/24"
        }
      }
    }
  }
}

# Bastion configuration variables
variable "bastion_sku" {
  description = "SKU for Azure Bastion (Basic or Standard)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard"], var.bastion_sku)
    error_message = "Bastion SKU must be either Basic or Standard."
  }
}

variable "bastion_scale_units" {
  description = "Number of scale units for Azure Bastion (2-50, only applies to Standard SKU)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.bastion_scale_units >= 2 && var.bastion_scale_units <= 50
    error_message = "Bastion scale units must be between 2 and 50."
  }
}

# Firewall configuration variables
variable "firewall_sku_tier" {
  description = "SKU tier for Azure Firewall (Standard or Premium)"
  type        = string
  default     = "Premium"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.firewall_sku_tier)
    error_message = "Firewall SKU tier must be either Standard or Premium."
  }
}

variable "firewall_threat_intel_mode" {
  description = "Threat intelligence mode for Azure Firewall (Off, Alert, Deny)"
  type        = string
  default     = "Alert"
  
  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.firewall_threat_intel_mode)
    error_message = "Firewall threat intelligence mode must be Off, Alert, or Deny."
  }
}

variable "enable_intrusion_detection" {
  description = "Enable intrusion detection and prevention (requires Premium SKU)"
  type        = bool
  default     = true
}

# Monitoring configuration variables
variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 7 and 730 days."
  }
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for Azure resources"
  type        = bool
  default     = true
}

# Policy configuration variables
variable "enforce_nsg_policy" {
  description = "Enforce Network Security Group policy on subnets"
  type        = bool
  default     = true
}

variable "deny_public_ip_policy" {
  description = "Deny creation of public IP addresses on VMs"
  type        = bool
  default     = true
}

# Resource tagging variables
variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Environment   = "production"
    Project       = "zero-trust-access"
    ManagedBy     = "terraform"
    CostCenter    = "security"
    Architecture  = "hub-spoke"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}