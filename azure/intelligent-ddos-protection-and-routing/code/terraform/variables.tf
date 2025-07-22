# Variables for Azure Adaptive Network Security Infrastructure
# This file defines all configurable parameters for the solution

# Resource naming and location variables
variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Italy North", "Australia East", "Australia Southeast", "East Asia",
      "Southeast Asia", "Japan East", "Japan West", "Korea Central",
      "India Central", "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group for all adaptive network security resources"
  type        = string
  default     = "rg-adaptive-network-security"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, hyphens, and underscores."
  }
}

variable "environment" {
  description = "Environment tag for resources (dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, production."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "adaptive-security"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Network configuration variables
variable "hub_vnet_address_space" {
  description = "Address space for the hub virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = length(var.hub_vnet_address_space) > 0
    error_message = "At least one address space must be specified for the hub VNet."
  }
}

variable "spoke_vnet_address_space" {
  description = "Address space for the spoke virtual network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
  
  validation {
    condition     = length(var.spoke_vnet_address_space) > 0
    error_message = "At least one address space must be specified for the spoke VNet."
  }
}

variable "route_server_subnet_prefix" {
  description = "Address prefix for the Route Server subnet (minimum /27)"
  type        = string
  default     = "10.0.1.0/27"
  
  validation {
    condition     = can(cidrhost(var.route_server_subnet_prefix, 0))
    error_message = "Route Server subnet prefix must be a valid CIDR block."
  }
}

variable "firewall_subnet_prefix" {
  description = "Address prefix for the Azure Firewall subnet (minimum /26)"
  type        = string
  default     = "10.0.2.0/26"
  
  validation {
    condition     = can(cidrhost(var.firewall_subnet_prefix, 0))
    error_message = "Firewall subnet prefix must be a valid CIDR block."
  }
}

variable "management_subnet_prefix" {
  description = "Address prefix for the management subnet"
  type        = string
  default     = "10.0.3.0/24"
  
  validation {
    condition     = can(cidrhost(var.management_subnet_prefix, 0))
    error_message = "Management subnet prefix must be a valid CIDR block."
  }
}

variable "application_subnet_prefix" {
  description = "Address prefix for the application subnet in spoke VNet"
  type        = string
  default     = "10.1.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.application_subnet_prefix, 0))
    error_message = "Application subnet prefix must be a valid CIDR block."
  }
}

variable "database_subnet_prefix" {
  description = "Address prefix for the database subnet in spoke VNet"
  type        = string
  default     = "10.1.2.0/24"
  
  validation {
    condition     = can(cidrhost(var.database_subnet_prefix, 0))
    error_message = "Database subnet prefix must be a valid CIDR block."
  }
}

# DDoS Protection configuration variables
variable "enable_ddos_protection" {
  description = "Enable Azure DDoS Protection Standard"
  type        = bool
  default     = true
}

# Azure Firewall configuration variables
variable "firewall_sku_tier" {
  description = "Azure Firewall SKU tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.firewall_sku_tier)
    error_message = "Firewall SKU tier must be either Standard or Premium."
  }
}

variable "firewall_threat_intel_mode" {
  description = "Azure Firewall threat intelligence mode"
  type        = string
  default     = "Alert"
  
  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.firewall_threat_intel_mode)
    error_message = "Threat intelligence mode must be Off, Alert, or Deny."
  }
}

# Monitoring and alerting configuration variables
variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "enable_flow_logs" {
  description = "Enable Network Security Group flow logs"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Number of days to retain flow logs"
  type        = number
  default     = 7
  
  validation {
    condition     = var.flow_logs_retention_days >= 1 && var.flow_logs_retention_days <= 365
    error_message = "Flow logs retention must be between 1 and 365 days."
  }
}

# Alert configuration variables
variable "enable_ddos_alerts" {
  description = "Enable DDoS attack detection alerts"
  type        = bool
  default     = true
}

variable "alert_email_addresses" {
  description = "List of email addresses to receive security alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.alert_email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid."
  }
}

variable "high_traffic_threshold" {
  description = "Threshold for high traffic volume alerts (packets per minute)"
  type        = number
  default     = 100000
  
  validation {
    condition     = var.high_traffic_threshold > 0
    error_message = "High traffic threshold must be greater than 0."
  }
}

# Resource tagging variables
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.additional_tags : can(regex("^[a-zA-Z0-9._-]+$", key))
    ])
    error_message = "Tag keys must contain only alphanumeric characters, periods, hyphens, and underscores."
  }
}

# Security configuration variables
variable "enable_network_watcher" {
  description = "Enable Network Watcher for network monitoring"
  type        = bool
  default     = true
}

variable "public_ip_sku" {
  description = "SKU for public IP addresses"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard"], var.public_ip_sku)
    error_message = "Public IP SKU must be either Basic or Standard."
  }
}

variable "public_ip_allocation_method" {
  description = "Allocation method for public IP addresses"
  type        = string
  default     = "Static"
  
  validation {
    condition     = contains(["Static", "Dynamic"], var.public_ip_allocation_method)
    error_message = "Public IP allocation method must be either Static or Dynamic."
  }
}