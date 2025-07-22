# Variable definitions for Azure multi-tenant SaaS performance and cost analytics solution
# These variables allow customization of the deployment

variable "resource_group_name" {
  description = "Name of the Azure resource group to create"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, hyphens, and underscores."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", "West Europe",
      "UK South", "UK West", "France Central", "Germany West Central",
      "Norway East", "Switzerland North", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India", "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production", "testing"], var.environment)
    error_message = "Environment must be one of: development, staging, production, testing."
  }
}

variable "solution_name" {
  description = "Solution name for resource naming and tagging"
  type        = string
  default     = "saas-analytics"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.solution_name))
    error_message = "Solution name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "multi-tenant-monitoring"
}

variable "cost_center" {
  description = "Cost center for resource tagging and cost attribution"
  type        = string
  default     = "engineering"
}

variable "owner" {
  description = "Owner of the resources for tagging and contact purposes"
  type        = string
  default     = "platform-team"
}

# Log Analytics Workspace Configuration
variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standard", "Premium", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standard, Premium, PerNode, PerGB2018, Standalone."
  }
}

variable "log_analytics_retention_days" {
  description = "Data retention period in days for Log Analytics workspace"
  type        = number
  default     = 90
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "log_analytics_daily_quota_gb" {
  description = "Daily data ingestion quota in GB for Log Analytics workspace"
  type        = number
  default     = 10
  
  validation {
    condition     = var.log_analytics_daily_quota_gb >= 1
    error_message = "Daily quota must be at least 1 GB."
  }
}

# Application Insights Configuration
variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either 'web' or 'other'."
  }
}

variable "application_insights_sampling_percentage" {
  description = "Sampling percentage for Application Insights telemetry"
  type        = number
  default     = 100
  
  validation {
    condition     = var.application_insights_sampling_percentage >= 0 && var.application_insights_sampling_percentage <= 100
    error_message = "Sampling percentage must be between 0 and 100."
  }
}

# Azure Data Explorer Configuration
variable "data_explorer_sku_name" {
  description = "SKU name for Azure Data Explorer cluster"
  type        = string
  default     = "Standard_D11_v2"
  
  validation {
    condition = contains([
      "Standard_D11_v2", "Standard_D12_v2", "Standard_D13_v2", "Standard_D14_v2",
      "Standard_DS13_v2+1TB_PS", "Standard_DS13_v2+2TB_PS", "Standard_DS14_v2+3TB_PS",
      "Standard_L4s", "Standard_L8s", "Standard_L16s"
    ], var.data_explorer_sku_name)
    error_message = "Invalid Data Explorer SKU name."
  }
}

variable "data_explorer_sku_tier" {
  description = "SKU tier for Azure Data Explorer cluster"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard"], var.data_explorer_sku_tier)
    error_message = "Data Explorer SKU tier must be either 'Basic' or 'Standard'."
  }
}

variable "data_explorer_capacity" {
  description = "Number of instances for Azure Data Explorer cluster"
  type        = number
  default     = 2
  
  validation {
    condition     = var.data_explorer_capacity >= 2 && var.data_explorer_capacity <= 1000
    error_message = "Data Explorer capacity must be between 2 and 1000 instances."
  }
}

variable "data_explorer_hot_cache_period" {
  description = "Hot cache period for Data Explorer database (ISO 8601 duration)"
  type        = string
  default     = "P30D"
  
  validation {
    condition     = can(regex("^P([0-9]+D|[0-9]+M|[0-9]+Y)$", var.data_explorer_hot_cache_period))
    error_message = "Hot cache period must be in ISO 8601 duration format (e.g., P30D, P1M, P1Y)."
  }
}

variable "data_explorer_soft_delete_period" {
  description = "Soft delete period for Data Explorer database (ISO 8601 duration)"
  type        = string
  default     = "P365D"
  
  validation {
    condition     = can(regex("^P([0-9]+D|[0-9]+M|[0-9]+Y)$", var.data_explorer_soft_delete_period))
    error_message = "Soft delete period must be in ISO 8601 duration format (e.g., P365D, P1Y)."
  }
}

# Cost Management Configuration
variable "budget_amount" {
  description = "Monthly budget amount for cost management"
  type        = number
  default     = 200
  
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "budget_alert_email" {
  description = "Email address for budget alert notifications"
  type        = string
  default     = "admin@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.budget_alert_email))
    error_message = "Budget alert email must be a valid email address."
  }
}

variable "budget_alert_thresholds" {
  description = "List of threshold percentages for budget alerts"
  type        = list(number)
  default     = [80, 100]
  
  validation {
    condition     = length(var.budget_alert_thresholds) > 0 && alltrue([for t in var.budget_alert_thresholds : t > 0 && t <= 100])
    error_message = "Budget alert thresholds must be between 1 and 100."
  }
}

# Network and Security Configuration
variable "enable_public_network_access" {
  description = "Enable public network access for Data Explorer cluster"
  type        = bool
  default     = true
}

variable "trusted_external_tenants" {
  description = "List of external tenant IDs trusted for Data Explorer access"
  type        = list(string)
  default     = []
}

variable "disk_encryption_enabled" {
  description = "Enable disk encryption for Data Explorer cluster"
  type        = bool
  default     = true
}

# Advanced Configuration
variable "enable_streaming_ingest" {
  description = "Enable streaming ingest for Data Explorer cluster"
  type        = bool
  default     = true
}

variable "enable_purge" {
  description = "Enable data purge capability for Data Explorer cluster"
  type        = bool
  default     = false
}

variable "enable_double_encryption" {
  description = "Enable double encryption for Data Explorer cluster"
  type        = bool
  default     = false
}

variable "optimized_auto_scale" {
  description = "Enable optimized auto scale for Data Explorer cluster"
  type        = bool
  default     = false
}

variable "auto_scale_minimum" {
  description = "Minimum capacity for auto scale (when enabled)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.auto_scale_minimum >= 2
    error_message = "Auto scale minimum must be at least 2."
  }
}

variable "auto_scale_maximum" {
  description = "Maximum capacity for auto scale (when enabled)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.auto_scale_maximum >= 2
    error_message = "Auto scale maximum must be at least 2."
  }
}

# Resource tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}