# Input variables for the automated video analysis infrastructure
# These variables allow customization of the deployment for different environments

# Resource naming and location variables
variable "location" {
  description = "The Azure region where all resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", "Central US",
      "North Central US", "South Central US", "West Central US", "Canada Central",
      "Canada East", "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West", "Korea Central",
      "South India", "Central India", "West India", "UAE North", "South Africa North"
    ], var.location)
    error_message = "The location must be a valid Azure region that supports Video Indexer and Azure Functions."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = length(var.environment) <= 10 && can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must be lowercase alphanumeric and no more than 10 characters."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "video-analysis"
  
  validation {
    condition     = length(var.project_name) <= 20 && can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be lowercase alphanumeric with hyphens and no more than 20 characters."
  }
}

# Resource-specific configuration variables
variable "storage_account_tier" {
  description = "Storage account performance tier (Standard or Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "function_app_plan_sku" {
  description = "App Service Plan SKU for the Function App (Y1 for Consumption plan)"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains([
      "Y1",           # Consumption plan
      "EP1", "EP2", "EP3",  # Elastic Premium plans
      "P1v2", "P2v2", "P3v2"  # Premium plans
    ], var.function_app_plan_sku)
    error_message = "Function App plan SKU must be a valid Azure Functions hosting plan SKU."
  }
}

variable "video_indexer_sku" {
  description = "Video Indexer account pricing tier (S0 for standard)"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.video_indexer_sku)
    error_message = "Video Indexer SKU must be S0 (currently the only available option)."
  }
}

# Function App configuration variables
variable "function_timeout_minutes" {
  description = "Function timeout in minutes (max 10 for consumption plan)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_timeout_minutes >= 1 && var.function_timeout_minutes <= 60
    error_message = "Function timeout must be between 1 and 60 minutes."
  }
}

variable "python_version" {
  description = "Python runtime version for Azure Functions"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = contains(["3.8", "3.9", "3.10", "3.11"], var.python_version)
    error_message = "Python version must be one of: 3.8, 3.9, 3.10, 3.11."
  }
}

# Security and access control variables
variable "enable_public_access" {
  description = "Whether to allow public access to storage account (false for enhanced security)"
  type        = bool
  default     = false
}

variable "allowed_ip_addresses" {
  description = "List of IP addresses or CIDR blocks allowed to access storage account"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_addresses : can(cidrhost(ip, 0)) || can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip))
    ])
    error_message = "All IP addresses must be valid IPv4 addresses or CIDR blocks."
  }
}

# Application Insights and monitoring configuration
variable "enable_application_insights" {
  description = "Whether to create Application Insights for function monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain Application Insights logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

# Cost management and optimization variables
variable "storage_lifecycle_enabled" {
  description = "Whether to enable storage lifecycle management for cost optimization"
  type        = bool
  default     = true
}

variable "video_archive_days" {
  description = "Number of days after which to move videos to cool storage tier"
  type        = number
  default     = 30
  
  validation {
    condition     = var.video_archive_days >= 1
    error_message = "Video archive days must be at least 1."
  }
}

variable "insights_delete_days" {
  description = "Number of days after which to delete insights files"
  type        = number
  default     = 365
  
  validation {
    condition     = var.insights_delete_days >= 30
    error_message = "Insights delete days must be at least 30."
  }
}

# Resource tagging variables
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.tags) <= 15
    error_message = "No more than 15 additional tags are allowed."
  }
}

# Development and testing variables
variable "create_sample_video" {
  description = "Whether to create a sample video file for testing (development only)"
  type        = bool
  default     = false
}

variable "enable_debug_logging" {
  description = "Whether to enable debug logging in the Function App"
  type        = bool
  default     = false
}