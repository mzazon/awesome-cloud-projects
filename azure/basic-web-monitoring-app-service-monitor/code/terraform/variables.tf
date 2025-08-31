# Input Variables
# This file defines all configurable parameters for the infrastructure deployment

variable "resource_group_name" {
  description = "Name of the resource group to create. If not provided, a unique name will be generated."
  type        = string
  default     = null
  
  validation {
    condition = var.resource_group_name == null || (
      length(var.resource_group_name) >= 1 && 
      length(var.resource_group_name) <= 90 &&
      can(regex("^[a-zA-Z0-9._\\-()]+$", var.resource_group_name))
    )
    error_message = "Resource group name must be between 1-90 characters and can contain alphanumerics, underscores, parentheses, hyphens, and periods."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", "Central US",
      "North Central US", "South Central US", "West Central US", "Canada Central",
      "Canada East", "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West", "Korea Central",
      "South India", "Central India", "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "app_name" {
  description = "Name of the web application. If not provided, a unique name will be generated."
  type        = string
  default     = null
  
  validation {
    condition = var.app_name == null || (
      length(var.app_name) >= 2 && 
      length(var.app_name) <= 60 &&
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9]$", var.app_name))
    )
    error_message = "App name must be between 2-60 characters, start and end with alphanumeric characters, and can contain hyphens."
  }
}

variable "app_service_plan_name" {
  description = "Name of the App Service Plan. If not provided, a unique name will be generated."
  type        = string
  default     = null
  
  validation {
    condition = var.app_service_plan_name == null || (
      length(var.app_service_plan_name) >= 1 && 
      length(var.app_service_plan_name) <= 40 &&
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9]$", var.app_service_plan_name))
    )
    error_message = "App Service Plan name must be between 1-40 characters, start and end with alphanumeric characters, and can contain hyphens."
  }
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace. If not provided, a unique name will be generated."
  type        = string
  default     = null
  
  validation {
    condition = var.log_analytics_workspace_name == null || (
      length(var.log_analytics_workspace_name) >= 4 && 
      length(var.log_analytics_workspace_name) <= 63 &&
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9]$", var.log_analytics_workspace_name))
    )
    error_message = "Log Analytics Workspace name must be between 4-63 characters, start and end with alphanumeric characters, and can contain hyphens."
  }
}

variable "app_service_plan_sku" {
  description = "SKU for the App Service Plan (pricing tier)"
  type        = string
  default     = "F1"
  
  validation {
    condition = contains([
      "F1", "D1", "B1", "B2", "B3", "S1", "S2", "S3", 
      "P1", "P2", "P3", "P1V2", "P2V2", "P3V2", "P1V3", "P2V3", "P3V3"
    ], var.app_service_plan_sku)
    error_message = "App Service Plan SKU must be a valid pricing tier (F1, D1, B1-B3, S1-S3, P1-P3, P1V2-P3V2, P1V3-P3V3)."
  }
}

variable "container_image" {
  description = "Container image to deploy to the web app"
  type        = string
  default     = "mcr.microsoft.com/appsvc/node:18-lts"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$", var.container_image))
    error_message = "Container image must be in the format 'registry/image:tag'."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs in the Log Analytics Workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730 days."
  }
}

variable "alert_email_address" {
  description = "Email address to receive alert notifications"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email_address))
    error_message = "Alert email address must be a valid email address format."
  }
}

variable "response_time_threshold" {
  description = "Response time threshold in seconds for performance alerts"
  type        = number
  default     = 5
  
  validation {
    condition     = var.response_time_threshold > 0 && var.response_time_threshold <= 60
    error_message = "Response time threshold must be between 1 and 60 seconds."
  }
}

variable "http_error_threshold" {
  description = "Number of HTTP 5xx errors within the evaluation window to trigger alerts"
  type        = number
  default     = 10
  
  validation {
    condition     = var.http_error_threshold > 0 && var.http_error_threshold <= 1000
    error_message = "HTTP error threshold must be between 1 and 1000 errors."
  }
}

variable "alert_evaluation_frequency" {
  description = "How often to evaluate alert rules (in minutes)"
  type        = string
  default     = "PT1M"
  
  validation {
    condition = contains([
      "PT1M", "PT5M", "PT15M", "PT30M", "PT1H"
    ], var.alert_evaluation_frequency)
    error_message = "Alert evaluation frequency must be PT1M, PT5M, PT15M, PT30M, or PT1H."
  }
}

variable "alert_window_size" {
  description = "Time window for alert rule evaluation (in minutes)"
  type        = string
  default     = "PT5M"
  
  validation {
    condition = contains([
      "PT1M", "PT5M", "PT15M", "PT30M", "PT1H", "PT6H", "PT12H", "P1D"
    ], var.alert_window_size)
    error_message = "Alert window size must be PT1M, PT5M, PT15M, PT30M, PT1H, PT6H, PT12H, or P1D."
  }
}

variable "environment" {
  description = "Environment name for resource tagging (dev, test, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition = contains([
      "dev", "test", "staging", "prod", "demo"
    ], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    purpose    = "recipe"
    managed_by = "terraform"
  }
  
  validation {
    condition     = alltrue([for k, v in var.tags : can(regex("^[a-zA-Z0-9._-]+$", k)) && length(k) <= 128])
    error_message = "Tag keys must contain only alphanumeric characters, periods, underscores, and hyphens, and be no longer than 128 characters."
  }
  
  validation {
    condition     = alltrue([for k, v in var.tags : length(v) <= 256])
    error_message = "Tag values must be no longer than 256 characters."
  }
}