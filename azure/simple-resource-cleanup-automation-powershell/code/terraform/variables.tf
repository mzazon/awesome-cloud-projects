# Variables for Azure resource cleanup automation infrastructure
# These variables allow customization of the deployment for different environments

variable "resource_group_name" {
  description = "The name of the resource group for automation resources"
  type        = string
  default     = "rg-cleanup-automation"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

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
      "Korea Central", "Southeast Asia", "East Asia", "Central India",
      "South India", "West India", "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "automation_account_name" {
  description = "The name of the Azure Automation account"
  type        = string
  default     = null
  
  validation {
    condition     = var.automation_account_name == null || can(regex("^[a-zA-Z][a-zA-Z0-9-]{4,49}$", var.automation_account_name))
    error_message = "Automation account name must be 6-50 characters, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "automation_account_sku" {
  description = "The SKU of the Azure Automation account"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Free"], var.automation_account_sku)
    error_message = "Automation account SKU must be either 'Basic' or 'Free'."
  }
}

variable "runbook_name" {
  description = "The name of the PowerShell runbook for resource cleanup"
  type        = string
  default     = "ResourceCleanupRunbook"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]{0,63}$", var.runbook_name))
    error_message = "Runbook name must be 1-64 characters, start with a letter, and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "schedule_name" {
  description = "The name of the automation schedule"
  type        = string
  default     = "WeeklyCleanupSchedule"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]{0,127}$", var.schedule_name))
    error_message = "Schedule name must be 1-128 characters, start with a letter, and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "schedule_frequency" {
  description = "The frequency of the cleanup schedule"
  type        = string
  default     = "Week"
  
  validation {
    condition     = contains(["OneTime", "Day", "Hour", "Week", "Month"], var.schedule_frequency)
    error_message = "Schedule frequency must be one of: OneTime, Day, Hour, Week, Month."
  }
}

variable "schedule_interval" {
  description = "The interval between schedule runs (only valid for Day, Hour, Week, or Month frequencies)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.schedule_interval >= 1 && var.schedule_interval <= 100
    error_message = "Schedule interval must be between 1 and 100."
  }
}

variable "schedule_week_days" {
  description = "List of days of the week when the cleanup should run (only valid for Week frequency)"
  type        = list(string)
  default     = ["Sunday"]
  
  validation {
    condition = alltrue([
      for day in var.schedule_week_days : contains([
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
      ], day)
    ])
    error_message = "Week days must be valid day names (Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday)."
  }
}

variable "schedule_start_hour" {
  description = "The hour (0-23) when the cleanup schedule should start"
  type        = number
  default     = 2
  
  validation {
    condition     = var.schedule_start_hour >= 0 && var.schedule_start_hour <= 23
    error_message = "Schedule start hour must be between 0 and 23."
  }
}

variable "schedule_timezone" {
  description = "The timezone for the schedule"
  type        = string
  default     = "UTC"
  
  validation {
    condition     = can(regex("^[A-Za-z/_]+$", var.schedule_timezone))
    error_message = "Timezone must be a valid timezone identifier (e.g., UTC, US/Eastern, Europe/London)."
  }
}

variable "default_cleanup_days_old" {
  description = "Default number of days old a resource must be to be considered for cleanup"
  type        = number
  default     = 7
  
  validation {
    condition     = var.default_cleanup_days_old >= 1 && var.default_cleanup_days_old <= 365
    error_message = "Default cleanup days old must be between 1 and 365."
  }
}

variable "default_environment_filter" {
  description = "Default environment tag value to filter resources for cleanup"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.default_environment_filter))
    error_message = "Environment filter must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "enable_dry_run_by_default" {
  description = "Whether to enable dry run mode by default for safety"
  type        = bool
  default     = true
}

variable "create_test_resources" {
  description = "Whether to create test resources for demonstrating the cleanup functionality"
  type        = bool
  default     = false
}

variable "test_resource_group_name" {
  description = "The name of the test resource group (only used if create_test_resources is true)"
  type        = string
  default     = null
  
  validation {
    condition     = var.test_resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.test_resource_group_name))
    error_message = "Test resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    Project     = "ResourceCleanupAutomation"
    Environment = "Demo"
    ManagedBy   = "Terraform"
  }
  
  validation {
    condition = alltrue([
      for key, value in var.tags : can(regex("^[a-zA-Z0-9._-]+$", key)) && can(regex("^[a-zA-Z0-9 ._-]+$", value))
    ])
    error_message = "Tag keys and values must contain only alphanumeric characters, spaces, periods, underscores, and hyphens."
  }
}

variable "enable_public_network_access" {
  description = "Whether to enable public network access for the automation account"
  type        = bool
  default     = true
}

variable "enable_local_authentication" {
  description = "Whether to enable local authentication for the automation account"
  type        = bool
  default     = true
}