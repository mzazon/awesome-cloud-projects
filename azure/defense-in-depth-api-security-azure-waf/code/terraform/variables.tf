# Core configuration variables
variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Poland Central",
      "Italy North", "Spain Central", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West",
      "Korea Central", "India Central", "UAE North", "South Africa North"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "zero-trust-api"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Network configuration variables
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "agw_subnet_prefix" {
  description = "Address prefix for Application Gateway subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "apim_subnet_prefix" {
  description = "Address prefix for API Management subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "pe_subnet_prefix" {
  description = "Address prefix for Private Endpoint subnet"
  type        = string
  default     = "10.0.3.0/24"
}

# API Management configuration variables
variable "apim_sku_name" {
  description = "API Management SKU name"
  type        = string
  default     = "Standard_1"
  
  validation {
    condition = contains([
      "Developer_1", "Basic_1", "Basic_2", 
      "Standard_1", "Standard_2", 
      "Premium_1", "Premium_2", "Premium_4", "Premium_8"
    ], var.apim_sku_name)
    error_message = "API Management SKU must be a valid tier and capacity."
  }
}

variable "apim_publisher_name" {
  description = "API Management publisher name"
  type        = string
  default     = "Contoso API Security"
  
  validation {
    condition     = length(var.apim_publisher_name) > 0 && length(var.apim_publisher_name) <= 100
    error_message = "Publisher name must be between 1 and 100 characters."
  }
}

variable "apim_publisher_email" {
  description = "API Management publisher email"
  type        = string
  default     = "admin@contoso.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.apim_publisher_email))
    error_message = "Publisher email must be a valid email address."
  }
}

# Application Gateway configuration variables
variable "agw_sku" {
  description = "Application Gateway SKU configuration"
  type = object({
    name     = string
    tier     = string
    capacity = number
  })
  default = {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }
  
  validation {
    condition = contains(["WAF_v2"], var.agw_sku.tier)
    error_message = "Application Gateway tier must be WAF_v2 for zero-trust security."
  }
}

# WAF configuration variables
variable "waf_mode" {
  description = "WAF mode (Detection or Prevention)"
  type        = string
  default     = "Prevention"
  
  validation {
    condition = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "WAF mode must be either Detection or Prevention."
  }
}

variable "waf_rule_set_version" {
  description = "OWASP rule set version for WAF"
  type        = string
  default     = "3.2"
  
  validation {
    condition = contains(["3.0", "3.1", "3.2"], var.waf_rule_set_version)
    error_message = "WAF rule set version must be 3.0, 3.1, or 3.2."
  }
}

variable "rate_limit_threshold" {
  description = "Rate limit threshold for WAF custom rule (requests per minute)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.rate_limit_threshold > 0 && var.rate_limit_threshold <= 1000
    error_message = "Rate limit threshold must be between 1 and 1000."
  }
}

# Monitoring configuration variables
variable "log_retention_days" {
  description = "Log Analytics workspace retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

# Security configuration variables
variable "allowed_ip_ranges" {
  description = "List of allowed IP ranges for API access (CIDR notation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([
      for ip_range in var.allowed_ip_ranges : can(cidrhost(ip_range, 0))
    ])
    error_message = "All IP ranges must be in valid CIDR notation."
  }
}

variable "api_rate_limit_calls" {
  description = "API rate limit calls per minute"
  type        = number
  default     = 100
  
  validation {
    condition     = var.api_rate_limit_calls > 0 && var.api_rate_limit_calls <= 10000
    error_message = "API rate limit must be between 1 and 10000 calls per minute."
  }
}

variable "api_rate_limit_per_ip" {
  description = "API rate limit calls per IP per minute"
  type        = number
  default     = 10
  
  validation {
    condition     = var.api_rate_limit_per_ip > 0 && var.api_rate_limit_per_ip <= 1000
    error_message = "API rate limit per IP must be between 1 and 1000 calls per minute."
  }
}

# Sample API configuration variables
variable "enable_sample_api" {
  description = "Whether to create a sample secure API for testing"
  type        = bool
  default     = true
}

variable "sample_api_backend_url" {
  description = "Backend URL for the sample API"
  type        = string
  default     = "https://httpbin.org"
  
  validation {
    condition     = can(regex("^https?://", var.sample_api_backend_url))
    error_message = "Sample API backend URL must be a valid HTTP or HTTPS URL."
  }
}

# Resource tagging variables
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "zero-trust-api-security"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}