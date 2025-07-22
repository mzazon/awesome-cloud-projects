# variables.tf
# Input variables for Azure Static Web Apps with Front Door WAF deployment

variable "resource_group_name" {
  description = "Name of the resource group for all resources"
  type        = string
  default     = null
  
  validation {
    condition = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "North Europe", "West Europe", "UK South", "UK West",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast",
      "Japan East", "Japan West", "Korea Central", "Korea South"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "secure-webapp"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Static Web App Configuration
variable "static_web_app_sku_tier" {
  description = "SKU tier for Static Web App (Free or Standard)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Free", "Standard"], var.static_web_app_sku_tier)
    error_message = "SKU tier must be either 'Free' or 'Standard'."
  }
}

variable "static_web_app_source_repo" {
  description = "GitHub repository URL for Static Web App source code"
  type        = string
  default     = "https://github.com/staticwebdev/vanilla-basic"
  
  validation {
    condition     = can(regex("^https://github\\.com/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$", var.static_web_app_source_repo))
    error_message = "Source repository must be a valid GitHub repository URL."
  }
}

variable "static_web_app_branch" {
  description = "GitHub branch for Static Web App deployment"
  type        = string
  default     = "main"
}

variable "static_web_app_app_location" {
  description = "Location of application code in repository"
  type        = string
  default     = "/"
}

variable "static_web_app_output_location" {
  description = "Location of build output in repository"
  type        = string
  default     = "public"
}

# Front Door Configuration
variable "front_door_sku_name" {
  description = "SKU name for Front Door (Standard_AzureFrontDoor or Premium_AzureFrontDoor)"
  type        = string
  default     = "Standard_AzureFrontDoor"
  
  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.front_door_sku_name)
    error_message = "Front Door SKU must be either 'Standard_AzureFrontDoor' or 'Premium_AzureFrontDoor'."
  }
}

variable "enable_https_redirect" {
  description = "Enable automatic HTTPS redirect"
  type        = bool
  default     = true
}

variable "forwarding_protocol" {
  description = "Protocol to use when forwarding to origin (HttpOnly, HttpsOnly, MatchRequest)"
  type        = string
  default     = "HttpsOnly"
  
  validation {
    condition     = contains(["HttpOnly", "HttpsOnly", "MatchRequest"], var.forwarding_protocol)
    error_message = "Forwarding protocol must be one of: HttpOnly, HttpsOnly, MatchRequest."
  }
}

# WAF Configuration
variable "waf_mode" {
  description = "WAF policy mode (Detection or Prevention)"
  type        = string
  default     = "Prevention"
  
  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "WAF mode must be either 'Detection' or 'Prevention'."
  }
}

variable "enable_bot_protection" {
  description = "Enable Bot Manager Rule Set for bot protection"
  type        = bool
  default     = true
}

variable "enable_owasp_protection" {
  description = "Enable Microsoft Default Rule Set (OWASP) for security protection"
  type        = bool
  default     = true
}

variable "rate_limit_threshold" {
  description = "Rate limit threshold (requests per minute per IP)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.rate_limit_threshold >= 10 && var.rate_limit_threshold <= 2000
    error_message = "Rate limit threshold must be between 10 and 2000 requests per minute."
  }
}

variable "allowed_countries" {
  description = "List of country codes allowed to access the application (ISO 3166-1 alpha-2)"
  type        = list(string)
  default     = ["US", "CA", "GB", "DE", "FR", "AU", "JP"]
  
  validation {
    condition = alltrue([
      for country in var.allowed_countries : can(regex("^[A-Z]{2}$", country))
    ])
    error_message = "All country codes must be valid ISO 3166-1 alpha-2 format (e.g., US, GB, DE)."
  }
}

# Cache Configuration
variable "static_cache_duration" {
  description = "Cache duration for static assets (in format: days.hours:minutes:seconds)"
  type        = string
  default     = "7.00:00:00"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]{2}:[0-9]{2}:[0-9]{2}$", var.static_cache_duration))
    error_message = "Cache duration must be in format: days.hours:minutes:seconds (e.g., 7.00:00:00)."
  }
}

variable "enable_compression" {
  description = "Enable compression for text-based content"
  type        = bool
  default     = true
}

# Health Probe Configuration
variable "health_probe_interval" {
  description = "Health probe interval in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.health_probe_interval >= 5 && var.health_probe_interval <= 255
    error_message = "Health probe interval must be between 5 and 255 seconds."
  }
}

variable "health_probe_path" {
  description = "Path for health probe requests"
  type        = string
  default     = "/"
}

variable "successful_samples_required" {
  description = "Number of successful samples required for healthy status"
  type        = number
  default     = 3
  
  validation {
    condition     = var.successful_samples_required >= 2 && var.successful_samples_required <= 10
    error_message = "Successful samples required must be between 2 and 10."
  }
}

# Tagging
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for Front Door and WAF"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_name" {
  description = "Name of existing Log Analytics workspace for diagnostic logs (optional)"
  type        = string
  default     = null
}