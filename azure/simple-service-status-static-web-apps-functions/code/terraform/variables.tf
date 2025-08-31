# Variable definitions for Azure Static Web Apps service status infrastructure
# These variables allow customization of the deployment while maintaining best practices

variable "resource_group_name" {
  description = "The name of the Azure Resource Group where resources will be created"
  type        = string
  validation {
    condition     = length(var.resource_group_name) >= 3 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 3 and 90 characters long."
  }
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", 
      "West Central US", "Canada Central", "Canada East",
      "Brazil South", "UK South", "UK West", "West Europe",
      "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East",
      "Japan West", "Korea Central", "Southeast Asia",
      "East Asia", "India Central", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Static Web Apps."
  }
}

variable "static_web_app_name" {
  description = "The name of the Azure Static Web App. Must be globally unique"
  type        = string
  default     = null
  validation {
    condition = var.static_web_app_name == null || (
      length(var.static_web_app_name) >= 2 && 
      length(var.static_web_app_name) <= 60 &&
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.static_web_app_name))
    )
    error_message = "Static Web App name must be 2-60 characters, start and end with alphanumeric characters, and contain only letters, numbers, and hyphens."
  }
}

variable "sku_tier" {
  description = "The SKU tier for the Static Web App (Free or Standard)"
  type        = string
  default     = "Free"
  validation {
    condition     = contains(["Free", "Standard"], var.sku_tier)
    error_message = "SKU tier must be either 'Free' or 'Standard'."
  }
}

variable "sku_size" {
  description = "The SKU size for the Static Web App"
  type        = string
  default     = "Free"
  validation {
    condition     = contains(["Free", "Standard"], var.sku_size)
    error_message = "SKU size must be either 'Free' or 'Standard'."
  }
}

variable "app_location" {
  description = "The location of the app source code relative to the repository root"
  type        = string
  default     = "public"
}

variable "api_location" {
  description = "The location of the API source code relative to the repository root"
  type        = string
  default     = "api"
}

variable "output_location" {
  description = "The location of the built app content after build"
  type        = string
  default     = ""
}

variable "monitored_services" {
  description = "List of external services to monitor for status checks"
  type = list(object({
    name = string
    url  = string
  }))
  default = [
    {
      name = "GitHub API"
      url  = "https://api.github.com/status"
    },
    {
      name = "JSONPlaceholder"
      url  = "https://jsonplaceholder.typicode.com/posts/1"
    },
    {
      name = "HTTPBin"
      url  = "https://httpbin.org/status/200"
    }
  ]
  validation {
    condition     = length(var.monitored_services) > 0 && length(var.monitored_services) <= 20
    error_message = "Must provide between 1 and 20 services to monitor."
  }
}

variable "environment" {
  description = "The deployment environment (dev, staging, production)"
  type        = string
  default     = "demo"
  validation {
    condition     = contains(["dev", "staging", "production", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, production, demo."
  }
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default = {
    purpose     = "recipe"
    environment = "demo"
    managed-by  = "terraform"
  }
}

variable "enable_custom_domains" {
  description = "Whether to enable custom domain support (requires Standard SKU)"
  type        = bool
  default     = false
}

variable "functions_runtime" {
  description = "The runtime version for Azure Functions (node:18, node:20)"
  type        = string
  default     = "node:18"
  validation {
    condition     = contains(["node:18", "node:20"], var.functions_runtime)
    error_message = "Functions runtime must be either 'node:18' or 'node:20'."
  }
}