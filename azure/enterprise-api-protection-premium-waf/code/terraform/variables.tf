# Variables for Enterprise API Security and Performance Infrastructure
# This file defines all configurable parameters for the deployment

# Basic Configuration Variables
variable "resource_group_name" {
  description = "Name of the Azure Resource Group for all resources"
  type        = string
  default     = "rg-enterprise-api-security"
  
  validation {
    condition     = length(var.resource_group_name) > 3 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 4 and 90 characters."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", "Central US",
      "North Central US", "South Central US", "West Central US", "Canada Central",
      "Canada East", "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "East Asia", "Southeast Asia",
      "Japan East", "Japan West", "Korea Central", "Central India", "South India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
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

# API Management Configuration
variable "apim_name_prefix" {
  description = "Prefix for API Management service name (will be suffixed with random string)"
  type        = string
  default     = "apim-enterprise"
  
  validation {
    condition     = length(var.apim_name_prefix) >= 1 && length(var.apim_name_prefix) <= 40
    error_message = "API Management prefix must be between 1 and 40 characters."
  }
}

variable "apim_publisher_name" {
  description = "Publisher name for API Management service"
  type        = string
  default     = "Enterprise APIs"
  
  validation {
    condition     = length(var.apim_publisher_name) > 0
    error_message = "Publisher name cannot be empty."
  }
}

variable "apim_publisher_email" {
  description = "Publisher email for API Management service"
  type        = string
  default     = "api-admin@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.apim_publisher_email))
    error_message = "Publisher email must be a valid email address."
  }
}

variable "apim_sku_name" {
  description = "SKU for API Management service"
  type        = string
  default     = "Premium"
  
  validation {
    condition     = contains(["Premium"], var.apim_sku_name)
    error_message = "API Management SKU must be Premium for enterprise features."
  }
}

variable "apim_sku_capacity" {
  description = "Capacity units for API Management Premium SKU"
  type        = number
  default     = 1
  
  validation {
    condition     = var.apim_sku_capacity >= 1 && var.apim_sku_capacity <= 10
    error_message = "API Management capacity must be between 1 and 10 units."
  }
}

# Redis Cache Configuration
variable "redis_name_prefix" {
  description = "Prefix for Redis Cache name (will be suffixed with random string)"
  type        = string
  default     = "redis-enterprise"
  
  validation {
    condition     = length(var.redis_name_prefix) >= 1 && length(var.redis_name_prefix) <= 40
    error_message = "Redis prefix must be between 1 and 40 characters."
  }
}

variable "redis_sku" {
  description = "SKU for Azure Cache for Redis"
  type        = string
  default     = "Premium"
  
  validation {
    condition     = contains(["Premium"], var.redis_sku)
    error_message = "Redis SKU must be Premium for enterprise features."
  }
}

variable "redis_capacity" {
  description = "Capacity for Redis Premium SKU (1-6 for Premium)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.redis_capacity >= 1 && var.redis_capacity <= 6
    error_message = "Redis capacity must be between 1 and 6 for Premium SKU."
  }
}

variable "redis_maxmemory_policy" {
  description = "Memory management policy for Redis"
  type        = string
  default     = "allkeys-lru"
  
  validation {
    condition = contains([
      "allkeys-lru", "allkeys-lfu", "allkeys-random", "volatile-lru",
      "volatile-lfu", "volatile-random", "volatile-ttl", "noeviction"
    ], var.redis_maxmemory_policy)
    error_message = "Invalid Redis maxmemory policy."
  }
}

# Front Door and WAF Configuration
variable "front_door_name_prefix" {
  description = "Prefix for Azure Front Door name (will be suffixed with random string)"
  type        = string
  default     = "fd-enterprise"
  
  validation {
    condition     = length(var.front_door_name_prefix) >= 1 && length(var.front_door_name_prefix) <= 40
    error_message = "Front Door prefix must be between 1 and 40 characters."
  }
}

variable "front_door_sku" {
  description = "SKU for Azure Front Door"
  type        = string
  default     = "Premium_AzureFrontDoor"
  
  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.front_door_sku)
    error_message = "Front Door SKU must be Standard_AzureFrontDoor or Premium_AzureFrontDoor."
  }
}

variable "waf_policy_name_prefix" {
  description = "Prefix for WAF Policy name (will be suffixed with random string)"
  type        = string
  default     = "waf-enterprise-policy"
  
  validation {
    condition     = length(var.waf_policy_name_prefix) >= 1 && length(var.waf_policy_name_prefix) <= 40
    error_message = "WAF policy prefix must be between 1 and 40 characters."
  }
}

variable "waf_mode" {
  description = "Mode for Web Application Firewall (Detection or Prevention)"
  type        = string
  default     = "Prevention"
  
  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "WAF mode must be either Detection or Prevention."
  }
}

# Monitoring Configuration
variable "log_analytics_name_prefix" {
  description = "Prefix for Log Analytics Workspace name (will be suffixed with random string)"
  type        = string
  default     = "law-enterprise"
  
  validation {
    condition     = length(var.log_analytics_name_prefix) >= 1 && length(var.log_analytics_name_prefix) <= 40
    error_message = "Log Analytics prefix must be between 1 and 40 characters."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics Workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["PerGB2018", "CapacityReservation"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be PerGB2018 or CapacityReservation."
  }
}

variable "app_insights_name_prefix" {
  description = "Prefix for Application Insights name (will be suffixed with random string)"
  type        = string
  default     = "ai-enterprise"
  
  validation {
    condition     = length(var.app_insights_name_prefix) >= 1 && length(var.app_insights_name_prefix) <= 40
    error_message = "Application Insights prefix must be between 1 and 40 characters."
  }
}

variable "app_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.app_insights_type)
    error_message = "Application Insights type must be web or other."
  }
}

# API Configuration
variable "sample_api_name" {
  description = "Name for the sample API"
  type        = string
  default     = "sample-enterprise-api"
  
  validation {
    condition     = length(var.sample_api_name) > 0
    error_message = "Sample API name cannot be empty."
  }
}

variable "sample_api_path" {
  description = "Path for the sample API"
  type        = string
  default     = "/api/v1"
  
  validation {
    condition     = can(regex("^/", var.sample_api_path))
    error_message = "API path must start with '/'."
  }
}

variable "sample_api_service_url" {
  description = "Backend service URL for the sample API"
  type        = string
  default     = "https://httpbin.org"
  
  validation {
    condition     = can(regex("^https?://", var.sample_api_service_url))
    error_message = "Service URL must be a valid HTTP or HTTPS URL."
  }
}

# Security Configuration
variable "enable_managed_identity" {
  description = "Enable managed identity for API Management"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for Redis and other services"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "TLS version must be 1.0, 1.1, or 1.2."
  }
}

# Rate Limiting Configuration
variable "rate_limit_calls" {
  description = "Number of calls allowed per renewal period for rate limiting"
  type        = number
  default     = 100
  
  validation {
    condition     = var.rate_limit_calls > 0
    error_message = "Rate limit calls must be greater than 0."
  }
}

variable "rate_limit_renewal_period" {
  description = "Renewal period in seconds for rate limiting"
  type        = number
  default     = 60
  
  validation {
    condition     = var.rate_limit_renewal_period > 0
    error_message = "Rate limit renewal period must be greater than 0."
  }
}

variable "quota_calls" {
  description = "Number of calls allowed per quota renewal period"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.quota_calls > 0
    error_message = "Quota calls must be greater than 0."
  }
}

variable "quota_renewal_period" {
  description = "Renewal period in seconds for quota"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.quota_renewal_period > 0
    error_message = "Quota renewal period must be greater than 0."
  }
}

# Cache Configuration
variable "cache_duration" {
  description = "Cache duration in seconds for API responses"
  type        = number
  default     = 300
  
  validation {
    condition     = var.cache_duration >= 0
    error_message = "Cache duration must be 0 or greater."
  }
}

# Tagging
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "enterprise-api-security"
    environment = "demo"
    project     = "api-management"
    owner       = "platform-team"
  }
}

# Health Probe Configuration
variable "health_probe_interval" {
  description = "Health probe interval in seconds"
  type        = number
  default     = 120
  
  validation {
    condition     = var.health_probe_interval >= 30 && var.health_probe_interval <= 255
    error_message = "Health probe interval must be between 30 and 255 seconds."
  }
}

variable "health_probe_path" {
  description = "Health probe path for API Management"
  type        = string
  default     = "/status-0123456789abcdef"
  
  validation {
    condition     = can(regex("^/", var.health_probe_path))
    error_message = "Health probe path must start with '/'."
  }
}