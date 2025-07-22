# Variables for the Azure Playwright Testing infrastructure

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-playwright-testing"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "West US 3", "East Asia", "West Europe"
    ], var.location)
    error_message = "Location must be one of the supported regions for Azure Playwright Testing: East US, West US 3, East Asia, or West Europe."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "testing"
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "playwright"
}

variable "application_insights_name" {
  description = "Name of the Application Insights instance"
  type        = string
  default     = ""
}

variable "key_vault_name" {
  description = "Name of the Key Vault (must be globally unique)"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "testing"
    Purpose     = "e2e-testing"
    Project     = "playwright"
    ManagedBy   = "terraform"
  }
}

# Test application configuration variables
variable "test_app_url" {
  description = "URL of the test application"
  type        = string
  default     = "https://your-test-app.azurewebsites.net"
}

variable "test_username" {
  description = "Test user username"
  type        = string
  default     = "testuser@example.com"
  sensitive   = true
}

variable "test_password" {
  description = "Test user password (if not provided, will be auto-generated)"
  type        = string
  default     = ""
  sensitive   = true
}

# Key Vault configuration
variable "key_vault_sku" {
  description = "SKU for Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "enable_rbac_authorization" {
  description = "Enable RBAC authorization for Key Vault"
  type        = bool
  default     = true
}

# Application Insights configuration
variable "application_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition = contains([
      "web", "ios", "other", "store", "java", "phone"
    ], var.application_type)
    error_message = "Application type must be one of: web, ios, other, store, java, phone."
  }
}

variable "retention_in_days" {
  description = "Data retention period for Application Insights in days"
  type        = number
  default     = 90
  
  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.retention_in_days)
    error_message = "Retention period must be one of: 30, 60, 90, 120, 180, 270, 365, 550, or 730 days."
  }
}

# Log Analytics workspace configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains([
      "Free", "Standalone", "PerNode", "PerGB2018"
    ], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

variable "log_analytics_retention_days" {
  description = "Data retention period for Log Analytics workspace in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}