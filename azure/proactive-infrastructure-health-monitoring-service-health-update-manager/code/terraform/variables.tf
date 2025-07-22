# Core Infrastructure Variables
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US",
      "UK South", "UK West", "North Europe", "West Europe",
      "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East", "Australia Southeast",
      "Japan East", "Japan West", "Korea Central", "Southeast Asia",
      "East Asia", "India Central", "Brazil South", "Canada Central",
      "Canada East", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name)) || var.resource_group_name == ""
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "health-monitoring"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# Log Analytics Workspace Variables
variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid pricing tier."
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

# Alert Configuration Variables
variable "alert_email_address" {
  description = "Email address for alert notifications"
  type        = string
  default     = "admin@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email_address))
    error_message = "Alert email address must be a valid email format."
  }
}

variable "webhook_url" {
  description = "Webhook URL for Logic App trigger (optional)"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^https://.*", var.webhook_url)) || var.webhook_url == ""
    error_message = "Webhook URL must be a valid HTTPS URL or empty."
  }
}

variable "enable_service_health_alerts" {
  description = "Enable Azure Service Health alerts"
  type        = bool
  default     = true
}

variable "enable_update_manager_alerts" {
  description = "Enable Azure Update Manager alerts"
  type        = bool
  default     = true
}

# Update Manager Configuration Variables
variable "assessment_mode" {
  description = "Assessment mode for Update Manager"
  type        = string
  default     = "AutomaticByPlatform"
  
  validation {
    condition     = contains(["AutomaticByPlatform", "ImageDefault"], var.assessment_mode)
    error_message = "Assessment mode must be either 'AutomaticByPlatform' or 'ImageDefault'."
  }
}

variable "patch_schedule_day" {
  description = "Day of the week for patch schedule (0=Sunday, 1=Monday, etc.)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.patch_schedule_day >= 0 && var.patch_schedule_day <= 6
    error_message = "Patch schedule day must be between 0 (Sunday) and 6 (Saturday)."
  }
}

variable "patch_schedule_hour" {
  description = "Hour of the day for patch schedule (0-23)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.patch_schedule_hour >= 0 && var.patch_schedule_hour <= 23
    error_message = "Patch schedule hour must be between 0 and 23."
  }
}

variable "patch_schedule_duration" {
  description = "Duration of patch window in hours"
  type        = number
  default     = 4
  
  validation {
    condition     = var.patch_schedule_duration >= 1 && var.patch_schedule_duration <= 8
    error_message = "Patch schedule duration must be between 1 and 8 hours."
  }
}

# Logic App Configuration Variables
variable "logic_app_name" {
  description = "Name for the Logic App workflow"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.logic_app_name)) || var.logic_app_name == ""
    error_message = "Logic App name must contain only alphanumeric characters and hyphens."
  }
}

# Automation Account Variables
variable "automation_account_sku" {
  description = "SKU for the Automation Account"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Free", "Basic"], var.automation_account_sku)
    error_message = "Automation Account SKU must be either 'Free' or 'Basic'."
  }
}

# Monitoring and Alerting Variables
variable "critical_alert_threshold" {
  description = "Threshold for critical patch compliance alerts"
  type        = number
  default     = 0
  
  validation {
    condition     = var.critical_alert_threshold >= 0
    error_message = "Critical alert threshold must be a non-negative number."
  }
}

variable "alert_evaluation_frequency" {
  description = "Frequency for alert evaluation in minutes"
  type        = number
  default     = 15
  
  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.alert_evaluation_frequency)
    error_message = "Alert evaluation frequency must be one of: 1, 5, 10, 15, 30, 60 minutes."
  }
}

variable "alert_window_size" {
  description = "Time window for alert evaluation in minutes"
  type        = number
  default     = 15
  
  validation {
    condition     = contains([1, 5, 10, 15, 30, 60, 120, 180, 240, 300, 360], var.alert_window_size)
    error_message = "Alert window size must be a valid time window in minutes."
  }
}

# Tagging Variables
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "health-monitoring"
    Environment = "production"
    Managed-By  = "terraform"
  }
}

# Service Health Alert Configuration
variable "service_health_alert_scopes" {
  description = "Scopes for Service Health alerts (subscription IDs)"
  type        = list(string)
  default     = []
}

variable "service_health_alert_regions" {
  description = "Azure regions to monitor for Service Health alerts"
  type        = list(string)
  default     = ["eastus", "westus2", "northeurope"]
}

variable "service_health_alert_services" {
  description = "Azure services to monitor for Service Health alerts"
  type        = list(string)
  default     = ["Virtual Machines", "Azure Monitor", "Log Analytics", "Logic Apps"]
}

# Advanced Configuration Variables
variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for resources"
  type        = bool
  default     = true
}

variable "enable_workbook_dashboard" {
  description = "Enable Azure Workbook dashboard creation"
  type        = bool
  default     = true
}

variable "enable_automation_runbooks" {
  description = "Enable creation of automation runbooks"
  type        = bool
  default     = true
}

variable "automation_success_rate_threshold" {
  description = "Threshold for automation success rate monitoring (percentage)"
  type        = number
  default     = 90
  
  validation {
    condition     = var.automation_success_rate_threshold >= 0 && var.automation_success_rate_threshold <= 100
    error_message = "Automation success rate threshold must be between 0 and 100."
  }
}