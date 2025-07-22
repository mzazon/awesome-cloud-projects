# Input Variables for Azure Cost Anomaly Detection Infrastructure
# This file defines all configurable parameters for the cost anomaly detection solution

# Environment and Resource Configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition     = can(regex("^[A-Za-z0-9\\s]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "naming_suffix" {
  description = "Suffix to append to resource names (leave empty for auto-generated)"
  type        = string
  default     = ""
}

# Cost Management Configuration
variable "anomaly_threshold" {
  description = "Percentage threshold for cost anomaly detection (e.g., 20 for 20%)"
  type        = number
  default     = 20
  
  validation {
    condition     = var.anomaly_threshold >= 5 && var.anomaly_threshold <= 100
    error_message = "Anomaly threshold must be between 5 and 100."
  }
}

variable "lookback_days" {
  description = "Number of days to look back for baseline cost calculation"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lookback_days >= 7 && var.lookback_days <= 90
    error_message = "Lookback days must be between 7 and 90."
  }
}

variable "monitored_subscription_ids" {
  description = "List of Azure subscription IDs to monitor for cost anomalies"
  type        = list(string)
  default     = []
}

# Function App Configuration
variable "function_app_service_plan_sku" {
  description = "SKU for the Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = can(regex("^(Y1|EP1|EP2|EP3)$", var.function_app_service_plan_sku))
    error_message = "Function App service plan SKU must be one of: Y1, EP1, EP2, EP3."
  }
}

variable "function_app_runtime_version" {
  description = "Python runtime version for Azure Functions"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = can(regex("^(3.9|3.10|3.11)$", var.function_app_runtime_version))
    error_message = "Function App runtime version must be one of: 3.9, 3.10, 3.11."
  }
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Storage account tier (Standard or Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = can(regex("^(Standard|Premium)$", var.storage_account_tier))
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = can(regex("^(LRS|GRS|RAGRS|ZRS|GZRS|RAGZRS)$", var.storage_account_replication_type))
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Cosmos DB Configuration
variable "cosmosdb_consistency_level" {
  description = "Cosmos DB consistency level"
  type        = string
  default     = "Session"
  
  validation {
    condition     = can(regex("^(Eventual|ConsistentPrefix|Session|BoundedStaleness|Strong)$", var.cosmosdb_consistency_level))
    error_message = "Cosmos DB consistency level must be one of: Eventual, ConsistentPrefix, Session, BoundedStaleness, Strong."
  }
}

variable "cosmosdb_throughput" {
  description = "Cosmos DB throughput (RU/s) for containers"
  type        = number
  default     = 400
  
  validation {
    condition     = var.cosmosdb_throughput >= 400 && var.cosmosdb_throughput <= 4000
    error_message = "Cosmos DB throughput must be between 400 and 4000 RU/s."
  }
}

variable "cosmosdb_enable_automatic_failover" {
  description = "Enable automatic failover for Cosmos DB"
  type        = bool
  default     = false
}

variable "cosmosdb_backup_type" {
  description = "Cosmos DB backup type (Periodic or Continuous)"
  type        = string
  default     = "Periodic"
  
  validation {
    condition     = can(regex("^(Periodic|Continuous)$", var.cosmosdb_backup_type))
    error_message = "Cosmos DB backup type must be either Periodic or Continuous."
  }
}

# Logic App Configuration
variable "logic_app_enabled" {
  description = "Enable Logic App for advanced workflow automation"
  type        = bool
  default     = true
}

variable "logic_app_frequency" {
  description = "Logic App trigger frequency (Hour, Day, Week, Month)"
  type        = string
  default     = "Hour"
  
  validation {
    condition     = can(regex("^(Hour|Day|Week|Month)$", var.logic_app_frequency))
    error_message = "Logic App frequency must be one of: Hour, Day, Week, Month."
  }
}

variable "logic_app_interval" {
  description = "Logic App trigger interval (numeric value)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.logic_app_interval >= 1 && var.logic_app_interval <= 24
    error_message = "Logic App interval must be between 1 and 24."
  }
}

# Notification Configuration
variable "notification_email" {
  description = "Email address for cost anomaly notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "teams_webhook_url" {
  description = "Microsoft Teams webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

# Application Insights Configuration
variable "application_insights_retention_days" {
  description = "Application Insights data retention in days"
  type        = number
  default     = 90
  
  validation {
    condition     = var.application_insights_retention_days >= 30 && var.application_insights_retention_days <= 730
    error_message = "Application Insights retention must be between 30 and 730 days."
  }
}

variable "application_insights_sampling_percentage" {
  description = "Application Insights sampling percentage"
  type        = number
  default     = 100
  
  validation {
    condition     = var.application_insights_sampling_percentage >= 0.1 && var.application_insights_sampling_percentage <= 100
    error_message = "Application Insights sampling percentage must be between 0.1 and 100."
  }
}

# Security Configuration
variable "enable_managed_identity" {
  description = "Enable managed identity for Function App"
  type        = bool
  default     = true
}

variable "enable_https_only" {
  description = "Enable HTTPS only for Function App"
  type        = bool
  default     = true
}

variable "allowed_cors_origins" {
  description = "List of allowed CORS origins for Function App"
  type        = list(string)
  default     = []
}

# Resource Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "cost-anomaly-detection"
    Environment = "production"
    Solution    = "azure-cost-management"
    ManagedBy   = "terraform"
  }
}

# Advanced Configuration
variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for resources"
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Log Analytics workspace retention in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "function_timeout_minutes" {
  description = "Function execution timeout in minutes"
  type        = number
  default     = 5
  
  validation {
    condition     = var.function_timeout_minutes >= 1 && var.function_timeout_minutes <= 10
    error_message = "Function timeout must be between 1 and 10 minutes."
  }
}