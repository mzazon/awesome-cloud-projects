# =============================================================================
# VARIABLES FOR AZURE IMAGE ANALYSIS INFRASTRUCTURE
# =============================================================================

# Project and Environment Configuration
variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "image-analysis"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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
      "Australia Southeast", "Australia Central", "Japan East", "Japan West",
      "Korea Central", "Korea South", "Southeast Asia", "East Asia",
      "Central India", "South India", "West India", "UAE North",
      "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Resource Naming Configuration
variable "resource_group_name" {
  description = "Name of the resource group (will be auto-generated if not provided)"
  type        = string
  default     = ""
}

variable "random_suffix" {
  description = "Random suffix for resource names to ensure uniqueness"
  type        = string
  default     = ""
}

# Computer Vision Configuration
variable "computer_vision_sku" {
  description = "SKU for Computer Vision service (F0 for free tier, S1 for standard)"
  type        = string
  default     = "F0"
  
  validation {
    condition     = contains(["F0", "S1"], var.computer_vision_sku)
    error_message = "Computer Vision SKU must be F0 (free) or S1 (standard)."
  }
}

variable "computer_vision_name" {
  description = "Name of the Computer Vision service (will be auto-generated if not provided)"
  type        = string
  default     = ""
}

# Storage Account Configuration
variable "storage_account_name" {
  description = "Name of the storage account (will be auto-generated if not provided)"
  type        = string
  default     = ""
}

variable "storage_account_tier" {
  description = "Performance tier of the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Type of replication for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Function App Configuration
variable "function_app_name" {
  description = "Name of the Function App (will be auto-generated if not provided)"
  type        = string
  default     = ""
}

variable "function_app_runtime" {
  description = "Runtime for the Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["python", "node", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: python, node, dotnet, java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "3.11"
}

variable "functions_extension_version" {
  description = "Version of the Azure Functions runtime"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~3", "~4"], var.functions_extension_version)
    error_message = "Functions extension version must be ~3 or ~4."
  }
}

# Service Plan Configuration
variable "service_plan_sku_name" {
  description = "SKU for the App Service Plan (Y1 for Consumption plan)"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains([
      "Y1",                    # Consumption plan
      "EP1", "EP2", "EP3",     # Elastic Premium plans
      "P1v2", "P2v2", "P3v2",  # Premium v2 plans
      "P1v3", "P2v3", "P3v3"   # Premium v3 plans
    ], var.service_plan_sku_name)
    error_message = "Service plan SKU must be a valid Azure Functions plan SKU."
  }
}

# Application Insights Configuration
variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be web or other."
  }
}

# Tagging Configuration
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "recipe"
    Environment = "demo"
    CreatedBy   = "terraform"
    Recipe      = "simple-image-analysis-computer-vision-functions"
  }
}

# Security Configuration
variable "enable_https_only" {
  description = "Enable HTTPS only for Function App"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for Function App"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, or 1.2."
  }
}

# Advanced Configuration
variable "enable_cors" {
  description = "Enable CORS for Function App"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "always_on" {
  description = "Keep Function App always on (not applicable for Consumption plan)"
  type        = bool
  default     = false
}