# Variables for Azure Carbon-Aware Cost Optimization Solution

variable "resource_group_name" {
  description = "Name of the resource group for carbon optimization resources"
  type        = string
  default     = "rg-carbon-optimization"
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", 
      "Central US", "North Central US", "South Central US", 
      "Canada Central", "Canada East", "Brazil South", "North Europe", 
      "West Europe", "UK South", "UK West", "France Central", 
      "Germany West Central", "Switzerland North", "Norway East",
      "Sweden Central", "Australia East", "Australia Southeast", 
      "East Asia", "Southeast Asia", "Japan East", "Japan West", 
      "Korea Central", "India Central", "South Africa North"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "carbon-optimization"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "carbon_threshold_kg" {
  description = "Carbon emissions threshold in kg CO2e per month for triggering optimization"
  type        = number
  default     = 100
  validation {
    condition     = var.carbon_threshold_kg > 0 && var.carbon_threshold_kg <= 10000
    error_message = "Carbon threshold must be between 1 and 10000 kg CO2e per month."
  }
}

variable "cost_threshold_usd" {
  description = "Cost threshold in USD per month for triggering optimization actions"
  type        = number
  default     = 500
  validation {
    condition     = var.cost_threshold_usd > 0 && var.cost_threshold_usd <= 100000
    error_message = "Cost threshold must be between 1 and 100000 USD per month."
  }
}

variable "min_carbon_reduction_percent" {
  description = "Minimum carbon reduction percentage required to trigger optimization actions"
  type        = number
  default     = 10
  validation {
    condition     = var.min_carbon_reduction_percent >= 1 && var.min_carbon_reduction_percent <= 100
    error_message = "Minimum carbon reduction percentage must be between 1 and 100."
  }
}

variable "cpu_utilization_threshold" {
  description = "CPU utilization threshold percentage for resource rightsizing"
  type        = number
  default     = 20
  validation {
    condition     = var.cpu_utilization_threshold >= 1 && var.cpu_utilization_threshold <= 100
    error_message = "CPU utilization threshold must be between 1 and 100 percent."
  }
}

variable "optimization_schedule_time" {
  description = "UTC time for daily carbon optimization schedule (HH:MM format)"
  type        = string
  default     = "02:00"
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.optimization_schedule_time))
    error_message = "Optimization schedule time must be in HH:MM format (24-hour)."
  }
}

variable "peak_optimization_schedule_time" {
  description = "UTC time for peak carbon intensity optimization schedule (HH:MM format)"
  type        = string
  default     = "18:00"
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.peak_optimization_schedule_time))
    error_message = "Peak optimization schedule time must be in HH:MM format (24-hour)."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain log analytics data"
  type        = number
  default     = 30
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be LRS, GRS, RAGRS, or ZRS."
  }
}

variable "key_vault_sku" {
  description = "Key Vault SKU"
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either standard or premium."
  }
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for all resources"
  type        = bool
  default     = true
}

variable "automation_account_sku" {
  description = "Azure Automation account SKU"
  type        = string
  default     = "Basic"
  validation {
    condition     = contains(["Free", "Basic"], var.automation_account_sku)
    error_message = "Automation account SKU must be either Free or Basic."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Sustainability"
    Project     = "Carbon Optimization"
    ManagedBy   = "Terraform"
  }
}