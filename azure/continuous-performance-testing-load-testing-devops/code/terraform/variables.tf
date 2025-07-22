# Variables for Azure Load Testing and Azure DevOps Performance Testing Infrastructure
# This file defines all configurable parameters for the Terraform deployment

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the Azure Resource Group to create for load testing resources"
  type        = string
  default     = "rg-loadtest-devops"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-._]*[a-zA-Z0-9])?$", var.resource_group_name))
    error_message = "Resource group name must be valid Azure resource name."
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
      "West Europe", "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "UK South", "UK West", "Southeast Asia", 
      "East Asia", "Australia East", "Australia Southeast", "Australia Central",
      "Japan East", "Japan West", "Korea Central", "India Central",
      "South Africa North", "UAE North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Load Testing Configuration
variable "load_test_name" {
  description = "Name of the Azure Load Testing resource"
  type        = string
  default     = "alt-perftest-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z]([a-zA-Z0-9-]*[a-zA-Z0-9])?$", var.load_test_name))
    error_message = "Load test name must start with a letter and contain only letters, numbers, and hyphens."
  }
}

variable "load_test_description" {
  description = "Description for the Azure Load Testing resource"
  type        = string
  default     = "Load testing resource for automated performance validation in CI/CD pipelines"
}

# Application Insights Configuration
variable "app_insights_name" {
  description = "Name of the Application Insights resource"
  type        = string
  default     = "ai-perftest-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z]([a-zA-Z0-9-._]*[a-zA-Z0-9])?$", var.app_insights_name))
    error_message = "Application Insights name must be valid Azure resource name."
  }
}

variable "app_insights_application_type" {
  description = "Type of application being monitored by Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition = contains([
      "web", "ios", "other", "store", "java", "phone"
    ], var.app_insights_application_type)
    error_message = "Application type must be one of: web, ios, other, store, java, phone."
  }
}

variable "app_insights_retention_in_days" {
  description = "Data retention period in days for Application Insights"
  type        = number
  default     = 90
  
  validation {
    condition = contains([
      30, 60, 90, 120, 180, 270, 365, 550, 730
    ], var.app_insights_retention_in_days)
    error_message = "Retention period must be one of: 30, 60, 90, 120, 180, 270, 365, 550, 730 days."
  }
}

# Log Analytics Workspace Configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace for centralized logging"
  type        = string
  default     = "law-perftest-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$", var.log_analytics_workspace_name))
    error_message = "Log Analytics Workspace name must be valid Azure resource name."
  }
}

variable "log_analytics_sku" {
  description = "SKU for the Log Analytics Workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains([
      "Free", "PerNode", "Premium", "Standard", "Standalone", "PerGB2018", "CapacityReservation"
    ], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be valid option."
  }
}

variable "log_analytics_retention_in_days" {
  description = "Data retention period in days for Log Analytics Workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_in_days >= 30 && var.log_analytics_retention_in_days <= 730
    error_message = "Retention period must be between 30 and 730 days."
  }
}

# Service Principal Configuration for Azure DevOps
variable "service_principal_name" {
  description = "Name for the Azure AD Service Principal used by Azure DevOps"
  type        = string
  default     = "sp-loadtest-devops"
  
  validation {
    condition     = can(regex("^[a-zA-Z]([a-zA-Z0-9-._]*[a-zA-Z0-9])?$", var.service_principal_name))
    error_message = "Service principal name must be valid Azure AD application name."
  }
}

# Monitoring and Alerting Configuration
variable "action_group_name" {
  description = "Name of the Azure Monitor Action Group for performance alerts"
  type        = string
  default     = "ag-perftest-alerts"
  
  validation {
    condition     = can(regex("^[a-zA-Z]([a-zA-Z0-9-._]*[a-zA-Z0-9])?$", var.action_group_name))
    error_message = "Action group name must be valid Azure resource name."
  }
}

variable "action_group_short_name" {
  description = "Short name for the Azure Monitor Action Group (max 12 characters)"
  type        = string
  default     = "PerfAlerts"
  
  validation {
    condition     = length(var.action_group_short_name) <= 12 && can(regex("^[a-zA-Z0-9]+$", var.action_group_short_name))
    error_message = "Action group short name must be alphanumeric and max 12 characters."
  }
}

variable "alert_email_receiver" {
  description = "Email address for receiving performance alerts"
  type        = string
  default     = "devops@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email_receiver))
    error_message = "Must be a valid email address."
  }
}

# Performance Thresholds for Alerts
variable "response_time_threshold_ms" {
  description = "Response time threshold in milliseconds for performance alerts"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.response_time_threshold_ms > 0 && var.response_time_threshold_ms <= 30000
    error_message = "Response time threshold must be between 1 and 30000 milliseconds."
  }
}

variable "error_rate_threshold_percent" {
  description = "Error rate threshold percentage for performance alerts"
  type        = number
  default     = 5
  
  validation {
    condition     = var.error_rate_threshold_percent >= 0 && var.error_rate_threshold_percent <= 100
    error_message = "Error rate threshold must be between 0 and 100 percent."
  }
}

variable "alert_window_size" {
  description = "Time window for alert evaluation (ISO 8601 duration format)"
  type        = string
  default     = "PT5M"
  
  validation {
    condition = contains([
      "PT1M", "PT5M", "PT15M", "PT30M", "PT1H", "PT6H", "PT12H", "PT24H"
    ], var.alert_window_size)
    error_message = "Window size must be valid ISO 8601 duration: PT1M, PT5M, PT15M, PT30M, PT1H, PT6H, PT12H, or PT24H."
  }
}

variable "alert_evaluation_frequency" {
  description = "Frequency of alert rule evaluation (ISO 8601 duration format)"
  type        = string
  default     = "PT1M"
  
  validation {
    condition = contains([
      "PT1M", "PT5M", "PT15M", "PT30M", "PT1H"
    ], var.alert_evaluation_frequency)
    error_message = "Evaluation frequency must be valid ISO 8601 duration: PT1M, PT5M, PT15M, PT30M, or PT1H."
  }
}

# Tagging Configuration
variable "environment" {
  description = "Environment tag for resources (e.g., dev, test, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition = contains([
      "dev", "test", "staging", "prod", "demo"
    ], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "project" {
  description = "Project name tag for resources"
  type        = string
  default     = "performance-testing"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.project))
    error_message = "Project name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "cost_center" {
  description = "Cost center tag for resource billing allocation"
  type        = string
  default     = "engineering"
}

variable "owner" {
  description = "Owner tag for resource management and accountability"
  type        = string
  default     = "devops-team"
}

# Additional Configuration
variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for resources to send logs to Log Analytics"
  type        = bool
  default     = true
}

variable "enable_managed_identity" {
  description = "Enable system-assigned managed identity for Load Testing resource"
  type        = bool
  default     = true
}

variable "generate_random_suffix" {
  description = "Generate a random suffix for globally unique resource names"
  type        = bool
  default     = true
}