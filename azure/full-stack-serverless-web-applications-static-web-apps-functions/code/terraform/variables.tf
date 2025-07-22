# Variables for Azure Static Web Apps and Azure Functions Infrastructure
# This file defines all configurable variables for the Terraform deployment

# Project Configuration
variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "fullstack-serverless"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Location Configuration
variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Australia Central", "Southeast Asia", "East Asia",
      "Japan East", "Japan West", "Korea Central", "South India", "Central India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the resource group (if not provided, will be generated)"
  type        = string
  default     = ""
}

# GitHub Repository Configuration
variable "github_repository_url" {
  description = "GitHub repository URL for the application source code"
  type        = string
  default     = ""
  
  validation {
    condition = var.github_repository_url == "" || can(regex("^https://github.com/[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$", var.github_repository_url))
    error_message = "GitHub repository URL must be a valid GitHub repository URL or empty string."
  }
}

variable "github_branch" {
  description = "GitHub branch to deploy from"
  type        = string
  default     = "main"
  
  validation {
    condition     = var.github_branch != ""
    error_message = "GitHub branch cannot be empty."
  }
}

# Static Web App Configuration
variable "static_web_app_name" {
  description = "Name of the Azure Static Web App (if not provided, will be generated)"
  type        = string
  default     = ""
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

variable "app_location" {
  description = "Location of the application source code in the repository"
  type        = string
  default     = "/"
  
  validation {
    condition     = can(regex("^/", var.app_location))
    error_message = "App location must start with '/'."
  }
}

variable "api_location" {
  description = "Location of the API source code in the repository"
  type        = string
  default     = "api"
}

variable "output_location" {
  description = "Location of the built application output"
  type        = string
  default     = "build"
}

# Storage Account Configuration
variable "storage_account_name" {
  description = "Name of the storage account (if not provided, will be generated)"
  type        = string
  default     = ""
}

variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_account_kind" {
  description = "Storage account kind"
  type        = string
  default     = "StorageV2"
  
  validation {
    condition     = contains(["Storage", "StorageV2", "BlobStorage", "FileStorage", "BlockBlobStorage"], var.storage_account_kind)
    error_message = "Storage account kind must be one of: Storage, StorageV2, BlobStorage, FileStorage, BlockBlobStorage."
  }
}

variable "storage_account_access_tier" {
  description = "Storage account access tier"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_account_access_tier)
    error_message = "Storage account access tier must be either 'Hot' or 'Cool'."
  }
}

# Azure Functions Configuration
variable "functions_version" {
  description = "Azure Functions runtime version"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~3", "~4"], var.functions_version)
    error_message = "Functions version must be either '~3' or '~4'."
  }
}

variable "node_version" {
  description = "Node.js version for Azure Functions"
  type        = string
  default     = "18"
  
  validation {
    condition     = contains(["16", "18", "20"], var.node_version)
    error_message = "Node.js version must be one of: 16, 18, 20."
  }
}

# Security Configuration
variable "enable_https_only" {
  description = "Enable HTTPS only for all resources"
  type        = bool
  default     = true
}

variable "enable_public_access" {
  description = "Enable public access to storage account"
  type        = bool
  default     = false
}

variable "allowed_origins" {
  description = "List of allowed origins for CORS (empty list allows all)"
  type        = list(string)
  default     = []
}

# Monitoring Configuration
variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "application_insights_type" {
  description = "Application Insights application type"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either 'web' or 'other'."
  }
}

variable "log_analytics_workspace_retention_days" {
  description = "Log Analytics workspace retention in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_workspace_retention_days >= 30 && var.log_analytics_workspace_retention_days <= 730
    error_message = "Log Analytics workspace retention must be between 30 and 730 days."
  }
}

# Tags Configuration
variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default = {
    Project     = "fullstack-serverless"
    Environment = "dev"
    ManagedBy   = "terraform"
    Purpose     = "recipe"
  }
}

# Advanced Configuration
variable "enable_custom_domain" {
  description = "Enable custom domain configuration"
  type        = bool
  default     = false
}

variable "custom_domain_name" {
  description = "Custom domain name for the static web app"
  type        = string
  default     = ""
}

variable "enable_staging_environment" {
  description = "Enable staging environment for the static web app"
  type        = bool
  default     = false
}

variable "enable_backup" {
  description = "Enable backup for storage account"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 9999
    error_message = "Backup retention must be between 1 and 9999 days."
  }
}

# Cost Optimization Configuration
variable "enable_cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

variable "storage_lifecycle_policy" {
  description = "Enable storage lifecycle policy for cost optimization"
  type        = bool
  default     = true
}