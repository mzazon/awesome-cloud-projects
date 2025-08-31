# Input variables for Azure AI Cost Monitoring with Foundry and Application Insights
# These variables allow customization of the deployment while maintaining best practices

# ==============================================================================
# CORE CONFIGURATION VARIABLES
# ==============================================================================

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "Asia Pacific", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod) for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.environment))
    error_message = "Environment must be 2-10 characters, lowercase letters and numbers only."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "ai-monitoring"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

# ==============================================================================
# RESOURCE GROUP CONFIGURATION
# ==============================================================================

variable "resource_group_name" {
  description = "Name of the Azure Resource Group (will be generated if not provided)"
  type        = string
  default     = null
}

# ==============================================================================
# AI FOUNDRY CONFIGURATION
# ==============================================================================

variable "ai_hub_name" {
  description = "Name of the Azure AI Foundry Hub (will be generated if not provided)"
  type        = string
  default     = null
}

variable "ai_project_name" {
  description = "Name of the Azure AI Foundry Project (will be generated if not provided)"
  type        = string
  default     = null
}

variable "ai_hub_description" {
  description = "Description for the Azure AI Foundry Hub"
  type        = string
  default     = "AI Foundry Hub for cost monitoring and analytics"
}

variable "ai_project_description" {
  description = "Description for the Azure AI Foundry Project"
  type        = string
  default     = "AI Project for implementing cost-aware AI applications"
}

# ==============================================================================
# MONITORING AND ANALYTICS CONFIGURATION
# ==============================================================================

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace (will be generated if not provided)"
  type        = string
  default     = null
}

variable "application_insights_name" {
  description = "Name of the Application Insights instance (will be generated if not provided)"
  type        = string
  default     = null
}

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
  description = "Pricing tier for Log Analytics Workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Premium", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Premium, Standalone."
  }
}

# ==============================================================================
# STORAGE CONFIGURATION
# ==============================================================================

variable "storage_account_name" {
  description = "Name of the Storage Account (will be generated if not provided)"
  type        = string
  default     = null
}

variable "storage_account_tier" {
  description = "Performance tier of the Storage Account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Replication type for the Storage Account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# ==============================================================================
# COST MANAGEMENT CONFIGURATION
# ==============================================================================

variable "budget_amount" {
  description = "Monthly budget amount in USD for AI resources"
  type        = number
  default     = 100
  
  validation {
    condition     = var.budget_amount > 0 && var.budget_amount <= 10000
    error_message = "Budget amount must be between 1 and 10000 USD."
  }
}

variable "budget_alert_thresholds" {
  description = "List of percentage thresholds for budget alerts"
  type        = list(number)
  default     = [80, 100, 120]
  
  validation {
    condition     = alltrue([for threshold in var.budget_alert_thresholds : threshold > 0 && threshold <= 1000])
    error_message = "Budget alert thresholds must be between 1 and 1000 percent."
  }
}

variable "budget_notification_emails" {
  description = "List of email addresses to receive budget alerts"
  type        = list(string)
  default     = ["admin@company.com"]
  
  validation {
    condition     = alltrue([for email in var.budget_notification_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All notification emails must be valid email addresses."
  }
}

# ==============================================================================
# ACTION GROUP CONFIGURATION
# ==============================================================================

variable "action_group_name" {
  description = "Name of the Action Group for alerts (will be generated if not provided)"
  type        = string
  default     = null
}

variable "action_group_short_name" {
  description = "Short name for the Action Group (max 12 characters)"
  type        = string
  default     = "AIAlerts"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9]{1,12}$", var.action_group_short_name))
    error_message = "Action group short name must be 1-12 characters, letters and numbers only."
  }
}

variable "webhook_url" {
  description = "Optional webhook URL for cost alerts"
  type        = string
  default     = null
  
  validation {
    condition     = var.webhook_url == null || can(regex("^https?://", var.webhook_url))
    error_message = "Webhook URL must be a valid HTTP or HTTPS URL."
  }
}

# ==============================================================================
# WORKBOOK CONFIGURATION
# ==============================================================================

variable "workbook_display_name" {
  description = "Display name for the Azure Monitor Workbook"
  type        = string
  default     = "AI Cost Monitoring Dashboard"
}

variable "workbook_description" {
  description = "Description for the Azure Monitor Workbook"
  type        = string
  default     = "Comprehensive dashboard for monitoring AI token usage, costs, and performance metrics"
}

# ==============================================================================
# TAGGING CONFIGURATION
# ==============================================================================

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_default_tags" {
  description = "Whether to apply default tags to all resources"
  type        = bool
  default     = true
}