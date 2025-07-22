# variables.tf - Input variables for the cost optimization infrastructure
# This file defines all configurable parameters for the deployment

variable "resource_group_name" {
  description = "Name of the Azure Resource Group where all resources will be created"
  type        = string
  default     = "rg-cost-optimization"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
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
      "Canada Central", "Canada East", "Brazil South", "North Europe",
      "West Europe", "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India", "UAE North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "cost-optimization"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "budget_amount" {
  description = "Monthly budget amount in USD for cost monitoring"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.budget_amount > 0 && var.budget_amount <= 100000
    error_message = "Budget amount must be between 1 and 100000."
  }
}

variable "budget_alert_thresholds" {
  description = "List of budget alert thresholds as percentages (e.g., [50, 80, 100])"
  type        = list(number)
  default     = [50, 80, 100]
  
  validation {
    condition     = alltrue([for threshold in var.budget_alert_thresholds : threshold > 0 && threshold <= 100])
    error_message = "Budget alert thresholds must be between 1 and 100."
  }
}

variable "cost_data_retention_days" {
  description = "Number of days to retain cost data exports in storage"
  type        = number
  default     = 90
  
  validation {
    condition     = var.cost_data_retention_days >= 30 && var.cost_data_retention_days <= 365
    error_message = "Cost data retention must be between 30 and 365 days."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 7 and 730 days."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "Premium", "Standard", "Standalone", "PerGB2018", "CapacityReservation"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, Premium, Standard, Standalone, PerGB2018, CapacityReservation."
  }
}

variable "storage_account_tier" {
  description = "Storage account tier for cost data exports"
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

variable "logic_app_plan_sku" {
  description = "SKU for Logic App Service Plan"
  type        = string
  default     = "WS1"
  
  validation {
    condition     = contains(["WS1", "WS2", "WS3"], var.logic_app_plan_sku)
    error_message = "Logic App plan SKU must be one of: WS1, WS2, WS3."
  }
}

variable "teams_webhook_url" {
  description = "Microsoft Teams webhook URL for cost alerts (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "email_notification_addresses" {
  description = "List of email addresses for cost optimization notifications"
  type        = list(string)
  default     = []
  
  validation {
    condition     = alltrue([for email in var.email_notification_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All email addresses must be valid."
  }
}

variable "enable_anomaly_detection" {
  description = "Enable cost anomaly detection with Azure Monitor"
  type        = bool
  default     = true
}

variable "anomaly_detection_threshold" {
  description = "Percentage threshold for cost anomaly detection"
  type        = number
  default     = 80
  
  validation {
    condition     = var.anomaly_detection_threshold >= 50 && var.anomaly_detection_threshold <= 100
    error_message = "Anomaly detection threshold must be between 50 and 100."
  }
}

variable "export_schedule_frequency" {
  description = "Frequency for cost data exports (Daily, Weekly, Monthly)"
  type        = string
  default     = "Daily"
  
  validation {
    condition     = contains(["Daily", "Weekly", "Monthly"], var.export_schedule_frequency)
    error_message = "Export schedule frequency must be one of: Daily, Weekly, Monthly."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    "Purpose"     = "Cost Optimization"
    "ManagedBy"   = "Terraform"
    "Environment" = "Production"
  }
}

variable "enable_rbac" {
  description = "Enable Role-Based Access Control for cost management"
  type        = bool
  default     = true
}

variable "cost_management_scope" {
  description = "Scope for cost management operations (subscription, resource-group, management-group)"
  type        = string
  default     = "subscription"
  
  validation {
    condition     = contains(["subscription", "resource-group", "management-group"], var.cost_management_scope)
    error_message = "Cost management scope must be one of: subscription, resource-group, management-group."
  }
}