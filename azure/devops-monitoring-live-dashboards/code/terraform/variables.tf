# Variables for Azure DevOps Real-Time Monitoring Dashboard solution
# This file defines all configurable parameters for the infrastructure

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-monitoring-dashboard"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][-a-zA-Z0-9_]{0,88}[a-zA-Z0-9]$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters long and can contain letters, numbers, hyphens, and underscores."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US", "West Central US",
      "North Europe", "West Europe", "UK South", "UK West",
      "Southeast Asia", "East Asia", "Japan East", "Japan West",
      "Australia East", "Australia Southeast", "Brazil South", "Canada Central"
    ], var.location)
    error_message = "Location must be a valid Azure region."
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

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "monitoring"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters long and contain only letters and numbers."
  }
}

variable "random_suffix" {
  description = "Random suffix for unique resource names (leave empty to auto-generate)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.random_suffix == "" || can(regex("^[a-z0-9]{3,6}$", var.random_suffix))
    error_message = "Random suffix must be 3-6 characters long and contain only lowercase letters and numbers."
  }
}

# SignalR Service Configuration
variable "signalr_sku" {
  description = "SKU for Azure SignalR Service"
  type        = string
  default     = "Standard_S1"
  
  validation {
    condition     = contains(["Free_F1", "Standard_S1", "Premium_P1", "Premium_P2"], var.signalr_sku)
    error_message = "SignalR SKU must be one of: Free_F1, Standard_S1, Premium_P1, Premium_P2."
  }
}

variable "signalr_capacity" {
  description = "Capacity units for Azure SignalR Service"
  type        = number
  default     = 1
  
  validation {
    condition     = var.signalr_capacity >= 1 && var.signalr_capacity <= 100
    error_message = "SignalR capacity must be between 1 and 100."
  }
}

variable "signalr_service_mode" {
  description = "Service mode for Azure SignalR Service"
  type        = string
  default     = "Default"
  
  validation {
    condition     = contains(["Default", "Serverless", "Classic"], var.signalr_service_mode)
    error_message = "SignalR service mode must be one of: Default, Serverless, Classic."
  }
}

# Azure Functions Configuration
variable "functions_runtime_version" {
  description = "Runtime version for Azure Functions"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~4", "~3"], var.functions_runtime_version)
    error_message = "Functions runtime version must be ~4 or ~3."
  }
}

variable "functions_node_version" {
  description = "Node.js version for Azure Functions"
  type        = string
  default     = "18"
  
  validation {
    condition     = contains(["16", "18", "20"], var.functions_node_version)
    error_message = "Node.js version must be 16, 18, or 20."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS."
  }
}

# App Service Plan Configuration
variable "app_service_plan_sku" {
  description = "SKU for the App Service Plan"
  type        = string
  default     = "B1"
  
  validation {
    condition     = contains(["F1", "D1", "B1", "B2", "B3", "S1", "S2", "S3", "P1v2", "P2v2", "P3v2", "P1v3", "P2v3", "P3v3"], var.app_service_plan_sku)
    error_message = "App Service Plan SKU must be a valid Azure App Service Plan SKU."
  }
}

variable "app_service_plan_os_type" {
  description = "OS type for the App Service Plan"
  type        = string
  default     = "Linux"
  
  validation {
    condition     = contains(["Linux", "Windows"], var.app_service_plan_os_type)
    error_message = "OS type must be Linux or Windows."
  }
}

# Web App Configuration
variable "web_app_runtime_stack" {
  description = "Runtime stack for the web app"
  type        = string
  default     = "NODE|18-lts"
  
  validation {
    condition     = can(regex("^(NODE|PYTHON|DOTNETCORE|JAVA|PHP)\\|.*", var.web_app_runtime_stack))
    error_message = "Runtime stack must be in format 'RUNTIME|VERSION', e.g., 'NODE|18-lts'."
  }
}

variable "web_app_always_on" {
  description = "Keep the web app always on"
  type        = bool
  default     = true
}

variable "web_app_https_only" {
  description = "Force HTTPS for the web app"
  type        = bool
  default     = true
}

# Log Analytics Configuration
variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

# Application Insights Configuration
variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be 'web' or 'other'."
  }
}

# Monitoring Configuration
variable "enable_monitoring_alerts" {
  description = "Enable Azure Monitor alerts"
  type        = bool
  default     = true
}

variable "alert_notification_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = ""
  
  validation {
    condition     = var.alert_notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

# Tagging Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "monitoring-dashboard"
    Purpose     = "devops-monitoring"
    ManagedBy   = "terraform"
  }
}

# Security Configuration
variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for all resources"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for web services"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, or 1.2."
  }
}

variable "enable_https_redirect" {
  description = "Enable automatic HTTPS redirect"
  type        = bool
  default     = true
}

# DevOps Integration
variable "devops_organization_url" {
  description = "Azure DevOps organization URL (for webhook configuration)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.devops_organization_url == "" || can(regex("^https://dev\\.azure\\.com/.*", var.devops_organization_url))
    error_message = "DevOps organization URL must be a valid Azure DevOps URL or empty string."
  }
}

variable "devops_project_names" {
  description = "List of Azure DevOps project names to monitor"
  type        = list(string)
  default     = []
  
  validation {
    condition     = length(var.devops_project_names) <= 10
    error_message = "Maximum of 10 DevOps projects can be monitored."
  }
}