# Variables for Azure Front Door Premium and Azure NetApp Files deployment

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-content-delivery"
}

variable "location_primary" {
  description = "Primary Azure region for resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location_primary))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "location_secondary" {
  description = "Secondary Azure region for resources"
  type        = string
  default     = "West Europe"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location_secondary))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition = contains(["dev", "staging", "prod", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, production."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "content-delivery"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Network Configuration
variable "vnet_address_space_primary" {
  description = "Address space for primary virtual network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
  
  validation {
    condition = length(var.vnet_address_space_primary) > 0
    error_message = "At least one address space must be provided."
  }
}

variable "vnet_address_space_secondary" {
  description = "Address space for secondary virtual network"
  type        = list(string)
  default     = ["10.2.0.0/16"]
  
  validation {
    condition = length(var.vnet_address_space_secondary) > 0
    error_message = "At least one address space must be provided."
  }
}

variable "anf_subnet_address_prefix_primary" {
  description = "Address prefix for Azure NetApp Files subnet in primary region"
  type        = string
  default     = "10.1.1.0/24"
}

variable "anf_subnet_address_prefix_secondary" {
  description = "Address prefix for Azure NetApp Files subnet in secondary region"
  type        = string
  default     = "10.2.1.0/24"
}

variable "pe_subnet_address_prefix_primary" {
  description = "Address prefix for private endpoint subnet in primary region"
  type        = string
  default     = "10.1.2.0/24"
}

variable "pe_subnet_address_prefix_secondary" {
  description = "Address prefix for private endpoint subnet in secondary region"
  type        = string
  default     = "10.2.2.0/24"
}

# Azure NetApp Files Configuration
variable "anf_capacity_pool_size" {
  description = "Size of the Azure NetApp Files capacity pool in TB"
  type        = number
  default     = 4
  
  validation {
    condition = var.anf_capacity_pool_size >= 4 && var.anf_capacity_pool_size <= 500
    error_message = "Capacity pool size must be between 4 and 500 TB."
  }
}

variable "anf_service_level" {
  description = "Service level for Azure NetApp Files (Standard, Premium, Ultra)"
  type        = string
  default     = "Premium"
  
  validation {
    condition = contains(["Standard", "Premium", "Ultra"], var.anf_service_level)
    error_message = "Service level must be one of: Standard, Premium, Ultra."
  }
}

variable "anf_volume_size" {
  description = "Size of the Azure NetApp Files volume in GB"
  type        = number
  default     = 1000
  
  validation {
    condition = var.anf_volume_size >= 100 && var.anf_volume_size <= 102400
    error_message = "Volume size must be between 100 GB and 102400 GB."
  }
}

variable "anf_volume_path" {
  description = "Volume path for Azure NetApp Files volume"
  type        = string
  default     = "content"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.anf_volume_path))
    error_message = "Volume path must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "anf_protocol_types" {
  description = "Protocol types for Azure NetApp Files volume"
  type        = list(string)
  default     = ["NFSv3"]
  
  validation {
    condition = length(var.anf_protocol_types) > 0
    error_message = "At least one protocol type must be specified."
  }
}

# Azure Front Door Configuration
variable "front_door_sku" {
  description = "SKU for Azure Front Door (Premium_AzureFrontDoor)"
  type        = string
  default     = "Premium_AzureFrontDoor"
  
  validation {
    condition = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.front_door_sku)
    error_message = "Front Door SKU must be either Standard_AzureFrontDoor or Premium_AzureFrontDoor."
  }
}

variable "front_door_endpoint_name" {
  description = "Name for the Front Door endpoint"
  type        = string
  default     = "content-endpoint"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.front_door_endpoint_name))
    error_message = "Endpoint name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "origin_host_header" {
  description = "Host header for origin requests"
  type        = string
  default     = "content.example.com"
}

variable "forwarding_protocol" {
  description = "Forwarding protocol for Front Door routes"
  type        = string
  default     = "HttpsOnly"
  
  validation {
    condition = contains(["HttpOnly", "HttpsOnly", "MatchRequest"], var.forwarding_protocol)
    error_message = "Forwarding protocol must be one of: HttpOnly, HttpsOnly, MatchRequest."
  }
}

# Load Balancer Configuration
variable "lb_private_ip_primary" {
  description = "Private IP address for load balancer in primary region"
  type        = string
  default     = "10.1.1.10"
}

variable "lb_private_ip_secondary" {
  description = "Private IP address for load balancer in secondary region"
  type        = string
  default     = "10.2.1.10"
}

# WAF Configuration
variable "waf_mode" {
  description = "WAF policy mode (Prevention, Detection)"
  type        = string
  default     = "Prevention"
  
  validation {
    condition = contains(["Prevention", "Detection"], var.waf_mode)
    error_message = "WAF mode must be either Prevention or Detection."
  }
}

variable "waf_managed_rule_set_version" {
  description = "Version of the managed rule set"
  type        = string
  default     = "2.1"
}

variable "rate_limit_threshold" {
  description = "Rate limit threshold for WAF"
  type        = number
  default     = 100
  
  validation {
    condition = var.rate_limit_threshold > 0 && var.rate_limit_threshold <= 10000
    error_message = "Rate limit threshold must be between 1 and 10000."
  }
}

variable "rate_limit_duration" {
  description = "Rate limit duration in minutes"
  type        = number
  default     = 1
  
  validation {
    condition = var.rate_limit_duration >= 1 && var.rate_limit_duration <= 60
    error_message = "Rate limit duration must be between 1 and 60 minutes."
  }
}

# Monitoring Configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains(["Free", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standalone."
  }
}

variable "log_analytics_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log retention must be between 7 and 730 days."
  }
}

# Tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    Project     = "content-delivery"
    ManagedBy   = "terraform"
  }
}