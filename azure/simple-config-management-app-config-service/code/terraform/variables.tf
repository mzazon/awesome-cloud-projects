# Variable Definitions for Azure Configuration Management Solution
# This file defines all input variables used in the Terraform configuration
# Variables are organized by resource type for better maintainability

# General Configuration Variables
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
      "Switzerland North", "Norway East", "Sweden Central"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must be lowercase alphanumeric characters only."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "config-mgmt"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be lowercase with hyphens only."
  }
}

# Resource Group Variables
variable "resource_group_name" {
  description = "Name of the resource group. If not provided, will be generated from project_name and environment"
  type        = string
  default     = null
}

# App Configuration Variables
variable "app_config_name" {
  description = "Name of the Azure App Configuration store. If not provided, will be generated"
  type        = string
  default     = null
  
  validation {
    condition = var.app_config_name == null ? true : (
      length(var.app_config_name) >= 5 && 
      length(var.app_config_name) <= 50 &&
      can(regex("^[a-zA-Z0-9-]+$", var.app_config_name))
    )
    error_message = "App Configuration name must be 5-50 characters and contain only letters, numbers, and hyphens."
  }
}

variable "app_config_sku" {
  description = "The SKU (pricing tier) of the App Configuration store"
  type        = string
  default     = "free"
  
  validation {
    condition     = contains(["free", "standard"], var.app_config_sku)
    error_message = "App Configuration SKU must be either 'free' or 'standard'."
  }
}

variable "app_config_local_auth_enabled" {
  description = "Whether local authentication (access keys) is enabled for App Configuration"
  type        = bool
  default     = false
}

variable "app_config_public_network_access" {
  description = "Whether public network access is enabled for App Configuration"
  type        = string
  default     = "Enabled"
  
  validation {
    condition     = contains(["Enabled", "Disabled"], var.app_config_public_network_access)
    error_message = "Public network access must be either 'Enabled' or 'Disabled'."
  }
}

# App Configuration Key-Value Settings
variable "configuration_values" {
  description = "Map of configuration key-value pairs to be stored in App Configuration"
  type = map(object({
    value        = string
    content_type = optional(string, "text/plain")
    label        = optional(string, null)
  }))
  
  default = {
    "DemoApp:Settings:Title" = {
      value        = "Configuration Management Demo"
      content_type = "text/plain"
    }
    "DemoApp:Settings:BackgroundColor" = {
      value        = "#2563eb"
      content_type = "text/plain"
    }
    "DemoApp:Settings:Message" = {
      value        = "Hello from Azure App Configuration!"
      content_type = "text/plain"
    }
    "DemoApp:Settings:RefreshInterval" = {
      value        = "30"
      content_type = "text/plain"
    }
  }
}

# App Service Variables
variable "app_service_name" {
  description = "Name of the Azure App Service. If not provided, will be generated"
  type        = string
  default     = null
  
  validation {
    condition = var.app_service_name == null ? true : (
      length(var.app_service_name) >= 2 && 
      length(var.app_service_name) <= 60 &&
      can(regex("^[a-zA-Z0-9-]+$", var.app_service_name))
    )
    error_message = "App Service name must be 2-60 characters and contain only letters, numbers, and hyphens."
  }
}

variable "app_service_plan_sku" {
  description = "The SKU (pricing tier) of the App Service Plan"
  type        = string
  default     = "F1"
  
  validation {
    condition = contains([
      "F1", "D1", # Free and Shared tiers
      "B1", "B2", "B3", # Basic tiers
      "S1", "S2", "S3", # Standard tiers
      "P1", "P2", "P3", "P1V2", "P2V2", "P3V2", "P1V3", "P2V3", "P3V3" # Premium tiers
    ], var.app_service_plan_sku)
    error_message = "App Service Plan SKU must be a valid pricing tier."
  }
}

variable "app_service_os_type" {
  description = "The operating system type for the App Service Plan"
  type        = string
  default     = "Linux"
  
  validation {
    condition     = contains(["Linux", "Windows"], var.app_service_os_type)
    error_message = "App Service OS type must be either 'Linux' or 'Windows'."
  }
}

variable "dotnet_version" {
  description = "The .NET version to use for the App Service"
  type        = string
  default     = "8.0"
  
  validation {
    condition     = contains(["6.0", "7.0", "8.0"], var.dotnet_version)
    error_message = ".NET version must be 6.0, 7.0, or 8.0."
  }
}

variable "always_on" {
  description = "Whether the App Service should always be on (not applicable for free tier)"
  type        = bool
  default     = false
}

# Monitoring and Logging Variables
variable "enable_application_insights" {
  description = "Whether to enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "application_insights_type" {
  description = "The type of Application Insights instance"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either 'web' or 'other'."
  }
}

# Security Variables
variable "managed_identity_enabled" {
  description = "Whether to enable system-assigned managed identity for the App Service"
  type        = bool
  default     = true
}

variable "https_only" {
  description = "Whether the App Service should only accept HTTPS requests"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "The minimum TLS version for the App Service"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, or 1.2."
  }
}

# Tagging Variables
variable "common_tags" {
  description = "Common tags to be applied to all resources"
  type        = map(string)
  default = {
    Purpose     = "recipe"
    Environment = "demo"
    ManagedBy   = "Terraform"
  }
}

# Deployment Configuration
variable "deploy_sample_app" {
  description = "Whether to deploy a sample ASP.NET Core application to demonstrate configuration management"
  type        = bool
  default     = false
}

variable "app_configuration_refresh_interval" {
  description = "The refresh interval in seconds for App Configuration updates"
  type        = number
  default     = 30
  
  validation {
    condition     = var.app_configuration_refresh_interval >= 1 && var.app_configuration_refresh_interval <= 3600
    error_message = "Refresh interval must be between 1 and 3600 seconds."
  }
}