# Variables for Azure distributed session management infrastructure
variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "session-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters long and contain only lowercase letters, numbers, and hyphens."
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
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia",
      "Central India", "South India", "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "redis_sku" {
  description = "Azure Redis Cache SKU configuration"
  type = object({
    family   = string
    capacity = number
    name     = string
  })
  default = {
    family   = "M"      # Memory Optimized
    capacity = 10       # M10 - 10GB Memory Optimized
    name     = "M10"
  }
  
  validation {
    condition     = contains(["M", "P", "C"], var.redis_sku.family)
    error_message = "Redis SKU family must be M (Memory Optimized), P (Premium), or C (Standard)."
  }
  
  validation {
    condition     = var.redis_sku.capacity >= 1 && var.redis_sku.capacity <= 120
    error_message = "Redis SKU capacity must be between 1 and 120."
  }
}

variable "app_service_plan_sku" {
  description = "App Service Plan SKU configuration"
  type = object({
    tier = string
    size = string
  })
  default = {
    tier = "Standard"
    size = "S1"
  }
  
  validation {
    condition = contains([
      "Free", "Shared", "Basic", "Standard", "Premium", "PremiumV2", "PremiumV3"
    ], var.app_service_plan_sku.tier)
    error_message = "App Service Plan tier must be a valid Azure App Service Plan tier."
  }
}

variable "app_service_instances" {
  description = "Number of App Service instances for load balancing"
  type        = number
  default     = 2
  
  validation {
    condition     = var.app_service_instances >= 1 && var.app_service_instances <= 30
    error_message = "App Service instances must be between 1 and 30."
  }
}

variable "dotnet_version" {
  description = ".NET runtime version for the web application"
  type        = string
  default     = "v8.0"
  
  validation {
    condition = contains([
      "v6.0", "v7.0", "v8.0"
    ], var.dotnet_version)
    error_message = "DOTNET version must be a supported .NET Core version."
  }
}

variable "session_timeout_minutes" {
  description = "Session timeout in minutes"
  type        = number
  default     = 20
  
  validation {
    condition     = var.session_timeout_minutes >= 1 && var.session_timeout_minutes <= 1440
    error_message = "Session timeout must be between 1 and 1440 minutes (24 hours)."
  }
}

variable "enable_redis_non_ssl_port" {
  description = "Enable non-SSL port for Redis (not recommended for production)"
  type        = bool
  default     = false
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for Redis"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, or 1.2."
  }
}

variable "virtual_network_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = length(var.virtual_network_address_space) > 0
    error_message = "Virtual network address space must contain at least one CIDR block."
  }
}

variable "redis_subnet_address_prefix" {
  description = "Address prefix for the Redis subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.redis_subnet_address_prefix, 0))
    error_message = "Redis subnet address prefix must be a valid CIDR block."
  }
}

variable "enable_monitoring" {
  description = "Enable Azure Monitor and Application Insights"
  type        = bool
  default     = true
}

variable "enable_diagnostic_logging" {
  description = "Enable diagnostic logging for Redis and App Service"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain diagnostic logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "DistributedSessionManagement"
    Environment = "Demo"
    Architecture = "WebApp-Redis"
  }
}