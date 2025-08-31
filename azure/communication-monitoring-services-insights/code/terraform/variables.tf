# Azure Communication Services Monitoring Infrastructure Variables
# Configuration parameters for customizing the deployment

# Resource naming and location configuration
variable "resource_group_name" {
  description = "Name of the Azure resource group to create"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters and can contain alphanumeric, underscore, parentheses, hyphen, and period characters."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", "Central US", "North Central US", "South Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Japan East", "Japan West", "Korea Central", "Korea South",
      "Southeast Asia", "East Asia", "India Central", "India South", "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.environment))
    error_message = "Environment must be 2-20 characters, lowercase alphanumeric and hyphens only."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "comm-monitor"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters, lowercase alphanumeric and hyphens only."
  }
}

# Communication Services configuration
variable "communication_service_data_location" {
  description = "Data residency location for Azure Communication Services"
  type        = string
  default     = "United States"
  
  validation {
    condition = contains([
      "Africa", "Asia Pacific", "Australia", "Brazil", "Canada", "Europe", "France", "Germany", 
      "India", "Japan", "Korea", "Norway", "Switzerland", "UAE", "UK", "United States"
    ], var.communication_service_data_location)
    error_message = "Data location must be a valid Azure Communication Services data location."
  }
}

# Log Analytics workspace configuration
variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation", "PerGB2018"], var.log_analytics_sku)
    error_message = "SKU must be a valid Log Analytics workspace SKU."
  }
}

variable "log_analytics_retention_days" {
  description = "Data retention period in days for Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.log_analytics_retention_days)
    error_message = "Retention days must be one of: 30, 60, 90, 120, 180, 270, 365, 550, 730."
  }
}

variable "log_analytics_daily_quota_gb" {
  description = "Daily ingestion quota in GB for Log Analytics workspace (-1 for unlimited)"
  type        = number
  default     = -1
  
  validation {
    condition     = var.log_analytics_daily_quota_gb == -1 || (var.log_analytics_daily_quota_gb >= 1 && var.log_analytics_daily_quota_gb <= 4000)
    error_message = "Daily quota must be -1 (unlimited) or between 1 and 4000 GB."
  }
}

# Application Insights configuration
variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["ios", "java", "MobileCenter", "Node.JS", "other", "phone", "store", "web"], var.application_insights_type)
    error_message = "Application type must be a valid Application Insights application type."
  }
}

variable "application_insights_retention_days" {
  description = "Data retention period in days for Application Insights"
  type        = number
  default     = 90
  
  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.application_insights_retention_days)
    error_message = "Retention days must be one of: 30, 60, 90, 120, 180, 270, 365, 550, 730."
  }
}

variable "application_insights_daily_cap_gb" {
  description = "Daily data cap in GB for Application Insights"
  type        = number
  default     = 100
  
  validation {
    condition     = var.application_insights_daily_cap_gb >= 1 && var.application_insights_daily_cap_gb <= 1000
    error_message = "Daily data cap must be between 1 and 1000 GB."
  }
}

variable "application_insights_sampling_percentage" {
  description = "Sampling percentage for Application Insights telemetry"
  type        = number
  default     = 100
  
  validation {
    condition     = var.application_insights_sampling_percentage >= 1 && var.application_insights_sampling_percentage <= 100
    error_message = "Sampling percentage must be between 1 and 100."
  }
}

# Monitoring and alerting configuration
variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for Communication Services and Application Insights"
  type        = bool
  default     = true
}

variable "enable_metric_alerts" {
  description = "Enable metric alerts for proactive monitoring"
  type        = bool
  default     = true
}

variable "alert_email_addresses" {
  description = "List of email addresses to receive monitoring alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition = length(var.alert_email_addresses) == 0 || alltrue([
      for email in var.alert_email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid email format."
  }
}

variable "communication_service_error_threshold" {
  description = "Threshold for Communication Services error alerts (requests per evaluation period)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.communication_service_error_threshold >= 1 && var.communication_service_error_threshold <= 10000
    error_message = "Error threshold must be between 1 and 10000."
  }
}

variable "alert_evaluation_frequency" {
  description = "How often metric alerts are evaluated (ISO 8601 duration)"
  type        = string
  default     = "PT5M"
  
  validation {
    condition     = contains(["PT1M", "PT5M", "PT15M", "PT30M", "PT1H"], var.alert_evaluation_frequency)
    error_message = "Evaluation frequency must be one of: PT1M, PT5M, PT15M, PT30M, PT1H."
  }
}

variable "alert_window_size" {
  description = "Time window for metric alert evaluation (ISO 8601 duration)"
  type        = string
  default     = "PT15M"
  
  validation {
    condition     = contains(["PT1M", "PT5M", "PT15M", "PT30M", "PT1H", "PT6H", "PT12H", "P1D"], var.alert_window_size)
    error_message = "Window size must be one of: PT1M, PT5M, PT15M, PT30M, PT1H, PT6H, PT12H, P1D."
  }
}

# Resource tagging configuration
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.tags : can(regex("^[a-zA-Z0-9_.:-]{1,128}$", k)) && can(regex("^[a-zA-Z0-9_.:-]{0,256}$", v))
    ])
    error_message = "Tag keys must be 1-128 characters and values must be 0-256 characters. Only alphanumeric, underscore, period, colon, and hyphen characters are allowed."
  }
}