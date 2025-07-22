# Variables for Azure Hybrid Network Security Infrastructure
# This file defines all configurable variables for the hybrid network security solution

# General Configuration Variables
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition     = contains(["East US", "West US", "West Europe", "UK South", "Southeast Asia"], var.location)
    error_message = "Location must be a valid Azure region that supports Azure Firewall Premium and ExpressRoute."
  }
}

variable "environment" {
  description = "Environment identifier (e.g., dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, production."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "hybrid-sec"
  
  validation {
    condition     = length(var.resource_prefix) >= 3 && length(var.resource_prefix) <= 15
    error_message = "Resource prefix must be between 3 and 15 characters."
  }
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "HybridNetworkSecurity"
    Environment = "Production"
    Owner       = "NetworkTeam"
    CostCenter  = "IT-Infrastructure"
  }
}

# Network Configuration Variables
variable "hub_vnet_address_space" {
  description = "Address space for the hub virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = length(var.hub_vnet_address_space) > 0
    error_message = "Hub VNet address space must contain at least one CIDR block."
  }
}

variable "spoke_vnet_address_space" {
  description = "Address space for the spoke virtual network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
  
  validation {
    condition     = length(var.spoke_vnet_address_space) > 0
    error_message = "Spoke VNet address space must contain at least one CIDR block."
  }
}

variable "firewall_subnet_address_prefix" {
  description = "Address prefix for the Azure Firewall subnet (must be /24 or larger)"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrsubnet(var.firewall_subnet_address_prefix, 0, 0))
    error_message = "Firewall subnet address prefix must be a valid CIDR block."
  }
}

variable "gateway_subnet_address_prefix" {
  description = "Address prefix for the ExpressRoute Gateway subnet (must be /27 or larger)"
  type        = string
  default     = "10.0.2.0/27"
  
  validation {
    condition     = can(cidrsubnet(var.gateway_subnet_address_prefix, 0, 0))
    error_message = "Gateway subnet address prefix must be a valid CIDR block."
  }
}

variable "workload_subnet_address_prefix" {
  description = "Address prefix for the workload subnet in spoke network"
  type        = string
  default     = "10.1.1.0/24"
  
  validation {
    condition     = can(cidrsubnet(var.workload_subnet_address_prefix, 0, 0))
    error_message = "Workload subnet address prefix must be a valid CIDR block."
  }
}

variable "on_premises_address_space" {
  description = "Address space for on-premises networks (used for firewall rules)"
  type        = list(string)
  default     = ["192.168.0.0/16"]
  
  validation {
    condition     = length(var.on_premises_address_space) > 0
    error_message = "On-premises address space must contain at least one CIDR block."
  }
}

# Azure Firewall Configuration Variables
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

variable "firewall_dns_proxy_enabled" {
  description = "Enable DNS proxy on Azure Firewall"
  type        = bool
  default     = true
}

variable "firewall_idps_mode" {
  description = "IDPS mode for Azure Firewall Premium (Off, Alert, Deny)"
  type        = string
  default     = "Alert"
  
  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.firewall_idps_mode)
    error_message = "Firewall IDPS mode must be Off, Alert, or Deny."
  }
}

variable "allowed_web_fqdns" {
  description = "List of allowed FQDNs for web traffic"
  type        = list(string)
  default = [
    "*.microsoft.com",
    "*.azure.com",
    "*.office.com",
    "*.windows.net"
  ]
}

variable "allowed_ports" {
  description = "List of allowed ports for network rules"
  type        = list(string)
  default     = ["443", "80", "22", "3389"]
}

# ExpressRoute Configuration Variables
variable "expressroute_gateway_sku" {
  description = "SKU for ExpressRoute Gateway (Standard, HighPerformance, UltraPerformance)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "HighPerformance", "UltraPerformance"], var.expressroute_gateway_sku)
    error_message = "ExpressRoute Gateway SKU must be Standard, HighPerformance, or UltraPerformance."
  }
}

variable "expressroute_circuit_resource_id" {
  description = "Resource ID of existing ExpressRoute circuit (optional)"
  type        = string
  default     = ""
}

variable "create_expressroute_connection" {
  description = "Whether to create ExpressRoute connection (requires existing circuit)"
  type        = bool
  default     = false
}

# Monitoring Configuration Variables
variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standard", "Premium", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid pricing tier."
  }
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for Azure Firewall"
  type        = bool
  default     = true
}

variable "diagnostic_log_categories" {
  description = "List of diagnostic log categories to enable"
  type        = list(string)
  default = [
    "AzureFirewallApplicationRule",
    "AzureFirewallNetworkRule",
    "AzureFirewallDnsProxy",
    "AZFWIdpsSignature",
    "AZFWThreatIntel"
  ]
}

# Security Configuration Variables
variable "enable_forced_tunneling" {
  description = "Enable forced tunneling for Azure Firewall"
  type        = bool
  default     = false
}

variable "create_management_subnet" {
  description = "Create management subnet for Azure Firewall (required for forced tunneling)"
  type        = bool
  default     = false
}

variable "management_subnet_address_prefix" {
  description = "Address prefix for management subnet (required if create_management_subnet is true)"
  type        = string
  default     = "10.0.3.0/26"
}

# Route Table Configuration Variables
variable "disable_bgp_route_propagation" {
  description = "Disable BGP route propagation on route tables"
  type        = bool
  default     = false
}

variable "create_default_route_to_internet" {
  description = "Create default route to internet through firewall"
  type        = bool
  default     = true
}