# Variables for Azure Cost Budget Tracking Infrastructure

variable "resource_group_name" {
  description = "Name of the resource group for cost tracking resources"
  type        = string
  default     = "rg-cost-tracking"
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "Brazil South", "UK South", "UK West", "West Europe",
      "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "UAE North",
      "South Africa North", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West",
      "Korea Central", "India Central", "India South"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "budget_name" {
  description = "Name for the Azure cost budget"
  type        = string
  default     = "monthly-cost-budget"
}

variable "budget_amount" {
  description = "Budget amount in USD for cost tracking"
  type        = number
  default     = 100
  
  validation {
    condition     = var.budget_amount > 0 && var.budget_amount <= 100000
    error_message = "Budget amount must be between 1 and 100,000 USD."
  }
}

variable "budget_time_grain" {
  description = "Time period for budget tracking (Monthly, Quarterly, Annually)"
  type        = string
  default     = "Monthly"
  
  validation {
    condition = contains([
      "Monthly", "Quarterly", "Annually", 
      "BillingMonth", "BillingQuarter", "BillingAnnual"
    ], var.budget_time_grain)
    error_message = "Budget time grain must be one of: Monthly, Quarterly, Annually, BillingMonth, BillingQuarter, BillingAnnual."
  }
}

variable "email_addresses" {
  description = "List of email addresses to receive budget alert notifications"
  type        = list(string)
  default     = ["admin@example.com"]
  
  validation {
    condition = length(var.email_addresses) > 0 && length(var.email_addresses) <= 10
    error_message = "Must provide at least 1 and at most 10 email addresses."
  }
}

variable "action_group_name" {
  description = "Name for the Azure Monitor Action Group"
  type        = string
  default     = "cost-alert-group"
}

variable "action_group_short_name" {
  description = "Short name for the Action Group (used in SMS messages)"
  type        = string
  default     = "CostAlert"
  
  validation {
    condition     = length(var.action_group_short_name) <= 12
    error_message = "Action group short name must be 12 characters or less."
  }
}

variable "alert_thresholds" {
  description = "List of budget alert threshold percentages"
  type = list(object({
    threshold      = number
    threshold_type = string
    operator       = string
  }))
  default = [
    {
      threshold      = 50
      threshold_type = "Actual"
      operator       = "GreaterThan"
    },
    {
      threshold      = 80
      threshold_type = "Actual"
      operator       = "GreaterThan"
    },
    {
      threshold      = 100
      threshold_type = "Forecasted"
      operator       = "GreaterThan"
    }
  ]
  
  validation {
    condition = alltrue([
      for alert in var.alert_thresholds : 
      alert.threshold >= 1 && alert.threshold <= 1000
    ])
    error_message = "All threshold values must be between 1 and 1000 percent."
  }
  
  validation {
    condition = alltrue([
      for alert in var.alert_thresholds : 
      contains(["Actual", "Forecasted"], alert.threshold_type)
    ])
    error_message = "Threshold type must be either 'Actual' or 'Forecasted'."
  }
  
  validation {
    condition = alltrue([
      for alert in var.alert_thresholds : 
      contains(["EqualTo", "GreaterThan", "GreaterThanOrEqualTo"], alert.operator)
    ])
    error_message = "Operator must be one of: EqualTo, GreaterThan, GreaterThanOrEqualTo."
  }
}

variable "budget_start_date" {
  description = "Start date for the budget in YYYY-MM-DD format (defaults to first day of current month)"
  type        = string
  default     = null
  
  validation {
    condition = var.budget_start_date == null || can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.budget_start_date))
    error_message = "Budget start date must be in YYYY-MM-DD format or null for automatic calculation."
  }
}

variable "budget_end_date" {
  description = "End date for the budget in YYYY-MM-DD format (defaults to 10 years from start date)"
  type        = string
  default     = null
  
  validation {
    condition = var.budget_end_date == null || can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.budget_end_date))
    error_message = "Budget end date must be in YYYY-MM-DD format or null for automatic calculation."
  }
}

variable "enable_resource_group_filter" {
  description = "Enable filtering budget to specific resource group only"
  type        = bool
  default     = false
}

variable "filter_resource_groups" {
  description = "List of resource group names to filter budget costs (only used if enable_resource_group_filter is true)"
  type        = list(string)
  default     = []
}

variable "contact_roles" {
  description = "List of Azure RBAC roles to notify (e.g., Owner, Contributor)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for role in var.contact_roles : 
      contains(["Owner", "Contributor", "Reader"], role)
    ])
    error_message = "Contact roles must be valid Azure RBAC roles: Owner, Contributor, or Reader."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "cost-monitoring"
    environment = "demo"
    managed-by  = "terraform"
  }
}