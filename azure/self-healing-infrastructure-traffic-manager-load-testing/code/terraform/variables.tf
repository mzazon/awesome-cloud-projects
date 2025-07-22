# Variables for Azure Self-Healing Infrastructure
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-selfhealing"
}

variable "location" {
  description = "Primary Azure region for resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Europe", "North Europe", "UK South", "UK West",
      "Southeast Asia", "East Asia", "Japan East", "Japan West",
      "Australia East", "Australia Southeast", "Canada Central",
      "Canada East", "Brazil South", "Central India", "South India",
      "West India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "selfhealing"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "web_app_regions" {
  description = "List of regions for web app deployment"
  type        = list(string)
  default     = ["East US", "West US", "West Europe"]
  
  validation {
    condition     = length(var.web_app_regions) >= 2
    error_message = "At least two regions must be specified for multi-region deployment."
  }
}

variable "app_service_sku" {
  description = "SKU for App Service Plans"
  type        = string
  default     = "B1"
  
  validation {
    condition = contains([
      "B1", "B2", "B3", "S1", "S2", "S3", "P1", "P2", "P3",
      "P1v2", "P2v2", "P3v2", "P1v3", "P2v3", "P3v3"
    ], var.app_service_sku)
    error_message = "App Service SKU must be a valid Azure App Service plan SKU."
  }
}

variable "traffic_manager_ttl" {
  description = "TTL for Traffic Manager DNS responses (in seconds)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.traffic_manager_ttl >= 30 && var.traffic_manager_ttl <= 2147483647
    error_message = "Traffic Manager TTL must be between 30 and 2147483647 seconds."
  }
}

variable "traffic_manager_routing_method" {
  description = "Routing method for Traffic Manager"
  type        = string
  default     = "Performance"
  
  validation {
    condition = contains([
      "Performance", "Weighted", "Priority", "Geographic", "MultiValue", "Subnet"
    ], var.traffic_manager_routing_method)
    error_message = "Traffic Manager routing method must be one of: Performance, Weighted, Priority, Geographic, MultiValue, Subnet."
  }
}

variable "monitor_interval" {
  description = "Monitoring interval for Traffic Manager health checks (in seconds)"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([10, 30], var.monitor_interval)
    error_message = "Monitor interval must be either 10 or 30 seconds."
  }
}

variable "monitor_timeout" {
  description = "Timeout for Traffic Manager health checks (in seconds)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.monitor_timeout >= 5 && var.monitor_timeout <= 10
    error_message = "Monitor timeout must be between 5 and 10 seconds."
  }
}

variable "monitor_failure_threshold" {
  description = "Number of failures before marking endpoint as degraded"
  type        = number
  default     = 3
  
  validation {
    condition     = var.monitor_failure_threshold >= 1 && var.monitor_failure_threshold <= 9
    error_message = "Monitor failure threshold must be between 1 and 9."
  }
}

variable "function_app_runtime" {
  description = "Runtime for Azure Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["python", "dotnet", "node", "java"], var.function_app_runtime)
    error_message = "Function app runtime must be one of: python, dotnet, node, java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Azure Function App"
  type        = string
  default     = "3.9"
}

variable "alert_evaluation_frequency" {
  description = "How often the alert rule is evaluated (in minutes)"
  type        = string
  default     = "PT1M"
  
  validation {
    condition = contains([
      "PT1M", "PT5M", "PT15M", "PT30M", "PT1H"
    ], var.alert_evaluation_frequency)
    error_message = "Alert evaluation frequency must be one of: PT1M, PT5M, PT15M, PT30M, PT1H."
  }
}

variable "alert_window_size" {
  description = "Time window for alert evaluation (in minutes)"
  type        = string
  default     = "PT5M"
  
  validation {
    condition = contains([
      "PT1M", "PT5M", "PT15M", "PT30M", "PT1H", "PT6H", "PT12H", "PT24H"
    ], var.alert_window_size)
    error_message = "Alert window size must be one of: PT1M, PT5M, PT15M, PT30M, PT1H, PT6H, PT12H, PT24H."
  }
}

variable "response_time_threshold" {
  description = "Response time threshold for alerts (in milliseconds)"
  type        = number
  default     = 5000
  
  validation {
    condition     = var.response_time_threshold > 0
    error_message = "Response time threshold must be greater than 0."
  }
}

variable "availability_threshold" {
  description = "Availability threshold for alerts (requests per minute)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.availability_threshold >= 0
    error_message = "Availability threshold must be greater than or equal to 0."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "development"
    Project     = "self-healing-infrastructure"
    Owner       = "platform-team"
    Purpose     = "disaster-recovery"
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "enable_load_testing" {
  description = "Enable Azure Load Testing resource"
  type        = bool
  default     = true
}

variable "enable_auto_scaling" {
  description = "Enable auto-scaling for App Service Plans"
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 7 and 730."
  }
}