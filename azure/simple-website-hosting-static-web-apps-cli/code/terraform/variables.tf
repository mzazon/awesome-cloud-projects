# Input Variables for Azure Static Web Apps Infrastructure
# This file defines all configurable parameters for the static website hosting solution

# Basic Configuration Variables
variable "resource_group_name" {
  description = "Name of the Azure Resource Group to create for hosting all resources"
  type        = string
  default     = "rg-staticweb"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
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
      "Canada Central", "Canada East", "Brazil South", "North Europe", 
      "West Europe", "UK South", "UK West", "France Central", "Germany West Central",
      "Norway East", "Switzerland North", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "Central India", "South India",
      "West India", "Japan East", "Japan West", "Korea Central", "Korea South",
      "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region name."
  }
}

# Static Web App Configuration
variable "static_web_app_name" {
  description = "Name of the Azure Static Web App resource"
  type        = string
  default     = "swa-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.static_web_app_name))
    error_message = "Static Web App name must contain only alphanumeric characters and hyphens."
  }
}

variable "static_web_app_sku_tier" {
  description = "Pricing tier for Azure Static Web Apps (Free or Standard)"
  type        = string
  default     = "Free"
  
  validation {
    condition     = contains(["Free", "Standard"], var.static_web_app_sku_tier)
    error_message = "SKU tier must be either 'Free' or 'Standard'."
  }
}

variable "static_web_app_sku_size" {
  description = "SKU size for Azure Static Web Apps"
  type        = string
  default     = "Free"
  
  validation {
    condition     = contains(["Free", "Standard"], var.static_web_app_sku_size)
    error_message = "SKU size must be either 'Free' or 'Standard'."
  }
}

# GitHub Integration (Optional)
variable "github_repository_url" {
  description = "GitHub repository URL for automated deployments (optional)"
  type        = string
  default     = null
  
  validation {
    condition = var.github_repository_url == null || can(regex("^https://github.com/[^/]+/[^/]+$", var.github_repository_url))
    error_message = "GitHub repository URL must be in format: https://github.com/owner/repo"
  }
}

variable "github_branch" {
  description = "GitHub branch for automated deployments"
  type        = string
  default     = "main"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._/-]+$", var.github_branch))
    error_message = "GitHub branch name must contain only valid branch characters."
  }
}

variable "github_app_location" {
  description = "Path to application source code in the repository"
  type        = string
  default     = "/"
  
  validation {
    condition     = can(regex("^/.*", var.github_app_location))
    error_message = "App location must start with a forward slash."
  }
}

variable "github_api_location" {
  description = "Path to API source code in the repository (optional for static sites)"
  type        = string
  default     = null
}

variable "github_output_location" {
  description = "Path to built application output (for build tools like npm, yarn)"
  type        = string
  default     = ""
}

# Deployment Configuration
variable "app_artifact_location" {
  description = "Path to the application artifacts after build"
  type        = string
  default     = "/"
}

variable "api_artifact_location" {
  description = "Path to the API artifacts after build (optional)"
  type        = string
  default     = null
}

# Custom Domain Configuration (Optional)
variable "custom_domain" {
  description = "Custom domain name for the static web app (optional)"
  type        = string
  default     = null
  
  validation {
    condition = var.custom_domain == null || can(regex("^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.custom_domain))
    error_message = "Custom domain must be a valid domain name (e.g., example.com or www.example.com)."
  }
}

# Security and Performance Configuration
variable "enable_staging_environment" {
  description = "Enable staging environment for preview deployments"
  type        = bool
  default     = true
}

variable "preview_environments_enabled" {
  description = "Enable preview environments for pull requests"
  type        = bool
  default     = true
}

# Tagging Configuration
variable "tags" {
  description = "Tags to apply to all resources for organization and cost management"
  type        = map(string)
  default = {
    Environment = "demo"
    Purpose     = "recipe"
    ManagedBy   = "terraform"
  }
  
  validation {
    condition     = length(var.tags) <= 50
    error_message = "Maximum of 50 tags are allowed per resource."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

# Resource Naming Configuration
variable "name_suffix" {
  description = "Suffix to append to resource names for uniqueness (auto-generated if not provided)"
  type        = string
  default     = null
  
  validation {
    condition = var.name_suffix == null || can(regex("^[a-z0-9]+$", var.name_suffix))
    error_message = "Name suffix must contain only lowercase alphanumeric characters."
  }
}

# Build and Deployment Configuration
variable "build_properties" {
  description = "Build configuration for Static Web Apps"
  type = object({
    skip_github_action_workflow_generation = optional(bool, false)
    skip_api_build                         = optional(bool, true)
  })
  default = {
    skip_github_action_workflow_generation = false
    skip_api_build                         = true
  }
}

# App Settings (Environment Variables)
variable "app_settings" {
  description = "Application settings (environment variables) for the Static Web App"
  type        = map(string)
  default     = {}
  sensitive   = true
}