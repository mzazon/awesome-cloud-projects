# Variables for Azure Spatial Computing Infrastructure
# This file defines all configurable parameters for the spatial computing solution
# including Azure Remote Rendering and Azure Spatial Anchors configuration

# Resource naming and location variables
variable "project_name" {
  description = "Name of the spatial computing project (used for resource naming)"
  type        = string
  default     = "spatialcomputing"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters and numbers."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Mixed Reality services."
  }
}

# Resource group configuration
variable "resource_group_name" {
  description = "Name of the Azure resource group (leave empty for auto-generation)"
  type        = string
  default     = ""
}

# Azure Remote Rendering configuration
variable "remote_rendering_sku" {
  description = "SKU for Azure Remote Rendering account"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["S1"], var.remote_rendering_sku)
    error_message = "Remote Rendering SKU must be S1 (Standard)."
  }
}

variable "remote_rendering_account_name" {
  description = "Name for Azure Remote Rendering account (leave empty for auto-generation)"
  type        = string
  default     = ""
}

# Azure Spatial Anchors configuration
variable "spatial_anchors_sku" {
  description = "SKU for Azure Spatial Anchors account"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["S1"], var.spatial_anchors_sku)
    error_message = "Spatial Anchors SKU must be S1 (Standard)."
  }
}

variable "spatial_anchors_account_name" {
  description = "Name for Azure Spatial Anchors account (leave empty for auto-generation)"
  type        = string
  default     = ""
}

# Storage configuration for 3D assets
variable "storage_account_name" {
  description = "Name for Azure Storage account (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "blob_container_name" {
  description = "Name of the blob container for 3D models"
  type        = string
  default     = "3dmodels"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.blob_container_name))
    error_message = "Container name must start and end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

# Service Principal configuration
variable "create_service_principal" {
  description = "Whether to create a service principal for application authentication"
  type        = bool
  default     = true
}

variable "service_principal_display_name" {
  description = "Display name for the service principal (leave empty for auto-generation)"
  type        = string
  default     = ""
}

# Collaboration and scaling configuration
variable "max_concurrent_users" {
  description = "Maximum number of concurrent users for collaborative sessions"
  type        = number
  default     = 8
  
  validation {
    condition     = var.max_concurrent_users >= 1 && var.max_concurrent_users <= 50
    error_message = "Maximum concurrent users must be between 1 and 50."
  }
}

variable "session_timeout_minutes" {
  description = "Default session timeout in minutes"
  type        = number
  default     = 30
  
  validation {
    condition     = var.session_timeout_minutes >= 5 && var.session_timeout_minutes <= 480
    error_message = "Session timeout must be between 5 and 480 minutes (8 hours)."
  }
}

# Cost management and monitoring
variable "enable_monitoring" {
  description = "Enable Azure Monitor and Application Insights for the solution"
  type        = bool
  default     = true
}

variable "enable_cost_alerts" {
  description = "Enable cost alerts for the resource group"
  type        = bool
  default     = true
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD for cost alerts"
  type        = number
  default     = 500
  
  validation {
    condition     = var.monthly_budget_limit > 0
    error_message = "Monthly budget limit must be greater than 0."
  }
}

# Security and access control
variable "allowed_ip_ranges" {
  description = "List of IP address ranges allowed to access storage account"
  type        = list(string)
  default     = []
}

variable "enable_storage_encryption" {
  description = "Enable storage account encryption with customer-managed keys"
  type        = bool
  default     = false
}

variable "enable_soft_delete" {
  description = "Enable soft delete for blob storage"
  type        = bool
  default     = true
}

# Development and Unity configuration
variable "unity_project_path" {
  description = "Path to Unity project directory for configuration generation"
  type        = string
  default     = "./unity-spatial-app"
}

variable "enable_unity_config_generation" {
  description = "Generate Unity configuration files automatically"
  type        = bool
  default     = true
}

# Tags for resource organization
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    purpose       = "spatial-computing"
    cost-center   = "innovation"
    environment   = "demo"
    workload-type = "mixed-reality"
  }
}

# Advanced networking configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for storage and other services"
  type        = bool
  default     = false
}

variable "virtual_network_id" {
  description = "ID of existing virtual network for private endpoints (optional)"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "ID of existing subnet for private endpoints (optional)"
  type        = string
  default     = ""
}