# Input variables for Azure Weather Dashboard Infrastructure
# These variables allow customization of the deployment while maintaining
# sensible defaults for a beginner serverless weather dashboard

variable "location" {
  type        = string
  description = "The Azure region where resources will be deployed"
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Australia East", "Australia Southeast", "Southeast Asia", "East Asia",
      "Japan East", "Japan West", "Korea Central", "South India", "Central India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the Azure resource group (will be created if it doesn't exist)"
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name)) || var.resource_group_name == ""
    error_message = "Resource group name must be 1-90 characters and can contain alphanumeric, underscore, parentheses, hyphen, and period characters."
  }
}

variable "project_name" {
  type        = string
  description = "Name of the project, used as prefix for resource naming"
  default     = "weather-dashboard"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "static_web_app_sku_tier" {
  type        = string
  description = "SKU tier for the Static Web App (Free or Standard)"
  default     = "Free"
  
  validation {
    condition     = contains(["Free", "Standard"], var.static_web_app_sku_tier)
    error_message = "SKU tier must be either 'Free' or 'Standard'."
  }
}

variable "static_web_app_sku_size" {
  type        = string
  description = "SKU size for the Static Web App (Free or Standard)"
  default     = "Free"
  
  validation {
    condition     = contains(["Free", "Standard"], var.static_web_app_sku_size)
    error_message = "SKU size must be either 'Free' or 'Standard'."
  }
}

variable "openweather_api_key" {
  type        = string
  description = "OpenWeatherMap API key for weather data retrieval"
  default     = ""
  sensitive   = true
  
  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.openweather_api_key)) || var.openweather_api_key == ""
    error_message = "OpenWeatherMap API key must be a 32-character hexadecimal string."
  }
}

variable "preview_environments_enabled" {
  type        = bool
  description = "Enable preview (staging) environments for the Static Web App"
  default     = true
}

variable "configuration_file_changes_enabled" {
  type        = bool
  description = "Allow changes to the Static Web App configuration file"
  default     = true
}

variable "public_network_access_enabled" {
  type        = bool
  description = "Enable public network access to the Static Web App"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "A mapping of tags to assign to all resources"
  default = {
    "Environment" = "Development"
    "Project"     = "WeatherDashboard"
    "ManagedBy"   = "Terraform"
    "Purpose"     = "Demo"
  }
}

# GitHub repository configuration (optional)
variable "repository_url" {
  type        = string
  description = "GitHub repository URL for continuous deployment (optional)"
  default     = ""
}

variable "repository_branch" {
  type        = string
  description = "GitHub repository branch for deployment (optional)"
  default     = "main"
}

variable "repository_token" {
  type        = string
  description = "GitHub personal access token for repository access (optional)"
  default     = ""
  sensitive   = true
}

# Application configuration
variable "app_location" {
  type        = string
  description = "Path to the frontend application source code"
  default     = "/src"
}

variable "api_location" {
  type        = string
  description = "Path to the Azure Functions API source code"
  default     = "/api"
}

variable "output_location" {
  type        = string
  description = "Path to the built application output (empty for no build step)"
  default     = ""
}