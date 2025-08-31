# Variables for Azure Simple Image Resizing Infrastructure
# This file defines all configurable parameters for the infrastructure deployment

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "imageresizer"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters and numbers."
  }
}

variable "resource_tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "recipe"
    Environment = "demo"
    Solution    = "image-resizing"
  }
}

# Storage Configuration Variables
variable "storage_account_tier" {
  description = "Storage account performance tier"
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
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "blob_access_tier" {
  description = "Default access tier for blob storage"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.blob_access_tier)
    error_message = "Blob access tier must be either Hot or Cool."
  }
}

variable "blob_public_access_enabled" {
  description = "Enable public access to blob containers"
  type        = bool
  default     = true
}

# Function App Configuration Variables
variable "function_app_runtime" {
  description = "Runtime for the Function App"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "dotnet", "java", "python"], var.function_app_runtime)
    error_message = "Function app runtime must be one of: node, dotnet, java, python."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "20"
}

variable "function_app_os_type" {
  description = "Operating system type for Function App"
  type        = string
  default     = "Linux"
  
  validation {
    condition     = contains(["Linux", "Windows"], var.function_app_os_type)
    error_message = "Function app OS type must be either Linux or Windows."
  }
}

# Image Processing Configuration Variables
variable "thumbnail_width" {
  description = "Width for thumbnail images"
  type        = number
  default     = 150
  
  validation {
    condition     = var.thumbnail_width > 0 && var.thumbnail_width <= 2000
    error_message = "Thumbnail width must be between 1 and 2000 pixels."
  }
}

variable "thumbnail_height" {
  description = "Height for thumbnail images"
  type        = number
  default     = 150
  
  validation {
    condition     = var.thumbnail_height > 0 && var.thumbnail_height <= 2000
    error_message = "Thumbnail height must be between 1 and 2000 pixels."
  }
}

variable "medium_width" {
  description = "Width for medium-sized images"
  type        = number
  default     = 800
  
  validation {
    condition     = var.medium_width > 0 && var.medium_width <= 4000
    error_message = "Medium width must be between 1 and 4000 pixels."
  }
}

variable "medium_height" {
  description = "Height for medium-sized images"
  type        = number
  default     = 600
  
  validation {
    condition     = var.medium_height > 0 && var.medium_height <= 4000
    error_message = "Medium height must be between 1 and 4000 pixels."
  }
}

# Application Insights Configuration
variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either web or other."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}