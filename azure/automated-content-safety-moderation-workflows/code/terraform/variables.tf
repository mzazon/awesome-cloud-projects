# Variables for the Content Moderation Infrastructure

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "content-moderation"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group (will be created if not exists)"
  type        = string
  default     = ""
}

variable "ai_content_safety_sku" {
  description = "SKU for Azure AI Content Safety service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.ai_content_safety_sku)
    error_message = "AI Content Safety SKU must be either F0 (Free) or S0 (Standard)."
  }
}

variable "storage_account_tier" {
  description = "Storage account tier for content storage"
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
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS."
  }
}

variable "function_app_plan_sku" {
  description = "SKU for the Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_plan_sku)
    error_message = "Function App plan SKU must be one of: Y1 (Consumption), EP1, EP2, EP3 (Premium)."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerGB2018", "PerNode", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerGB2018, PerNode, Premium."
  }
}

variable "log_analytics_retention_in_days" {
  description = "Data retention period for Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_in_days >= 30 && var.log_analytics_retention_in_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "event_grid_topic_input_schema" {
  description = "Input schema for Event Grid topic"
  type        = string
  default     = "EventGridSchema"
  
  validation {
    condition     = contains(["EventGridSchema", "CloudEventSchemaV1_0", "CustomEventSchema"], var.event_grid_topic_input_schema)
    error_message = "Event Grid topic input schema must be one of: EventGridSchema, CloudEventSchemaV1_0, CustomEventSchema."
  }
}

variable "content_safety_categories" {
  description = "List of content safety categories to analyze"
  type        = list(string)
  default     = ["Hate", "Violence", "Sexual", "SelfHarm"]
  
  validation {
    condition = alltrue([
      for category in var.content_safety_categories :
      contains(["Hate", "Violence", "Sexual", "SelfHarm"], category)
    ])
    error_message = "Content safety categories must be from: Hate, Violence, Sexual, SelfHarm."
  }
}

variable "content_safety_severity_threshold" {
  description = "Severity threshold for content quarantine (0-6)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.content_safety_severity_threshold >= 0 && var.content_safety_severity_threshold <= 6
    error_message = "Content safety severity threshold must be between 0 and 6."
  }
}

variable "notification_email" {
  description = "Email address for moderation notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for resources"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable monitoring and alerting"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}