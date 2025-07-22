# Input variables for Azure PWA infrastructure deployment
# These variables allow customization of the deployment without modifying the main configuration

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US",
      "Canada Central", "Canada East",
      "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "Sweden Central",
      "Australia East", "Australia Southeast",
      "Japan East", "Japan West",
      "Korea Central", "Korea South",
      "Southeast Asia", "East Asia",
      "Central India", "South India", "West India",
      "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming and tagging"
  type        = string
  default     = "azure-pwa"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "github_repository_url" {
  description = "GitHub repository URL for Static Web App source code"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^https://github.com/[^/]+/[^/]+$", var.github_repository_url)) || var.github_repository_url == ""
    error_message = "GitHub repository URL must be in the format: https://github.com/username/repository"
  }
}

variable "github_branch" {
  description = "GitHub branch for Static Web App deployment"
  type        = string
  default     = "main"
  
  validation {
    condition     = length(var.github_branch) > 0 && length(var.github_branch) <= 250
    error_message = "GitHub branch name must be between 1 and 250 characters."
  }
}

variable "app_location" {
  description = "Location of the application source code within the repository"
  type        = string
  default     = "src"
  
  validation {
    condition     = length(var.app_location) > 0
    error_message = "App location cannot be empty."
  }
}

variable "api_location" {
  description = "Location of the API source code within the repository"
  type        = string
  default     = "src/api"
  
  validation {
    condition     = length(var.api_location) > 0
    error_message = "API location cannot be empty."
  }
}

variable "output_location" {
  description = "Location of the built app content within the repository"
  type        = string
  default     = "src"
  
  validation {
    condition     = length(var.output_location) > 0
    error_message = "Output location cannot be empty."
  }
}

variable "cdn_sku" {
  description = "SKU for the CDN profile"
  type        = string
  default     = "Standard_Microsoft"
  
  validation {
    condition = contains([
      "Standard_Microsoft", "Standard_Akamai", "Standard_Verizon",
      "Premium_Verizon", "Standard_ChinaCdn", "Standard_955BandWidth_ChinaCdn"
    ], var.cdn_sku)
    error_message = "CDN SKU must be a valid Azure CDN SKU."
  }
}

variable "enable_compression" {
  description = "Enable compression for CDN endpoint"
  type        = bool
  default     = true
}

variable "cache_duration_hours" {
  description = "Cache duration in hours for static assets"
  type        = number
  default     = 24
  
  validation {
    condition     = var.cache_duration_hours > 0 && var.cache_duration_hours <= 8760
    error_message = "Cache duration must be between 1 and 8760 hours (1 year)."
  }
}

variable "application_insights_retention_days" {
  description = "Data retention period for Application Insights in days"
  type        = number
  default     = 90
  
  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.application_insights_retention_days)
    error_message = "Application Insights retention must be one of: 30, 60, 90, 120, 180, 270, 365, 550, 730 days."
  }
}

variable "static_web_app_sku" {
  description = "SKU for the Static Web App"
  type        = string
  default     = "Free"
  
  validation {
    condition     = contains(["Free", "Standard"], var.static_web_app_sku)
    error_message = "Static Web App SKU must be either 'Free' or 'Standard'."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = alltrue([for k, v in var.tags : can(regex("^[a-zA-Z0-9_.-]+$", k)) && can(regex("^[a-zA-Z0-9_.-]+$", v))])
    error_message = "Tag keys and values must contain only letters, numbers, underscores, periods, and hyphens."
  }
}

variable "enable_custom_domain" {
  description = "Enable custom domain configuration for Static Web App"
  type        = bool
  default     = false
}

variable "custom_domain_name" {
  description = "Custom domain name for the Static Web App (only used if enable_custom_domain is true)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.custom_domain_name == "" || can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.custom_domain_name))
    error_message = "Custom domain name must be a valid domain name in lowercase."
  }
}

variable "enable_staging_environments" {
  description = "Enable staging environments for the Static Web App (requires Standard SKU)"
  type        = bool
  default     = false
}

variable "allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
  
  validation {
    condition     = alltrue([for origin in var.allowed_origins : can(regex("^(\\*|https?://[a-zA-Z0-9.-]+)$", origin))])
    error_message = "Allowed origins must be '*' or valid HTTP/HTTPS URLs."
  }
}