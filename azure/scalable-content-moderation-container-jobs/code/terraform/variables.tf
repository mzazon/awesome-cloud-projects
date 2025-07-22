# General Configuration
variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US",
      "UK South", "UK West", "West Europe", "North Europe",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports AI Content Safety."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "content-moderation"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Content Moderation"
    Environment = "Demo"
    CreatedBy   = "Terraform"
  }
}

# Content Safety Configuration
variable "content_safety_sku" {
  description = "SKU for Azure AI Content Safety service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.content_safety_sku)
    error_message = "Content Safety SKU must be either F0 (free) or S0 (standard)."
  }
}

# Service Bus Configuration
variable "service_bus_sku" {
  description = "SKU for Azure Service Bus namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "Service Bus SKU must be Basic, Standard, or Premium."
  }
}

variable "content_queue_max_size" {
  description = "Maximum size of the content queue in MB"
  type        = number
  default     = 5120
  
  validation {
    condition     = var.content_queue_max_size >= 1024 && var.content_queue_max_size <= 81920
    error_message = "Queue max size must be between 1024 MB and 81920 MB."
  }
}

variable "message_ttl_hours" {
  description = "Time to live for messages in hours"
  type        = number
  default     = 24
  
  validation {
    condition     = var.message_ttl_hours >= 1 && var.message_ttl_hours <= 8760
    error_message = "Message TTL must be between 1 hour and 8760 hours (1 year)."
  }
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

variable "storage_access_tier" {
  description = "Access tier for storage account"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be Hot or Cool."
  }
}

# Container Apps Configuration
variable "container_apps_workload_profiles" {
  description = "Enable workload profiles for Container Apps Environment"
  type        = bool
  default     = true
}

variable "container_job_cpu" {
  description = "CPU allocation for container job"
  type        = number
  default     = 0.5
  
  validation {
    condition     = var.container_job_cpu >= 0.25 && var.container_job_cpu <= 4.0
    error_message = "Container job CPU must be between 0.25 and 4.0."
  }
}

variable "container_job_memory" {
  description = "Memory allocation for container job in Gi"
  type        = string
  default     = "1.0Gi"
  
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?Gi$", var.container_job_memory))
    error_message = "Container job memory must be in format like '1.0Gi' or '2Gi'."
  }
}

variable "container_job_timeout" {
  description = "Timeout for container job execution in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.container_job_timeout >= 60 && var.container_job_timeout <= 1800
    error_message = "Container job timeout must be between 60 and 1800 seconds."
  }
}

variable "container_job_retry_limit" {
  description = "Retry limit for container job execution"
  type        = number
  default     = 3
  
  validation {
    condition     = var.container_job_retry_limit >= 0 && var.container_job_retry_limit <= 10
    error_message = "Container job retry limit must be between 0 and 10."
  }
}

variable "container_job_parallelism" {
  description = "Number of parallel executions for container job"
  type        = number
  default     = 3
  
  validation {
    condition     = var.container_job_parallelism >= 1 && var.container_job_parallelism <= 10
    error_message = "Container job parallelism must be between 1 and 10."
  }
}

variable "scale_rule_message_count" {
  description = "Number of messages to trigger scaling"
  type        = number
  default     = 5
  
  validation {
    condition     = var.scale_rule_message_count >= 1 && var.scale_rule_message_count <= 100
    error_message = "Scale rule message count must be between 1 and 100."
  }
}

# Monitoring Configuration
variable "enable_log_analytics" {
  description = "Enable Log Analytics workspace for monitoring"
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Retention period for Log Analytics workspace in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "enable_alerts" {
  description = "Enable monitoring alerts"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address or empty string."
  }
}

variable "high_queue_depth_threshold" {
  description = "Threshold for high queue depth alert"
  type        = number
  default     = 50
  
  validation {
    condition     = var.high_queue_depth_threshold >= 10 && var.high_queue_depth_threshold <= 1000
    error_message = "High queue depth threshold must be between 10 and 1000."
  }
}

# Security Configuration
variable "enable_managed_identity" {
  description = "Enable managed identity for Container Apps"
  type        = bool
  default     = true
}

variable "enable_https_only" {
  description = "Enable HTTPS only for storage account"
  type        = bool
  default     = true
}

variable "enable_storage_firewall" {
  description = "Enable storage account firewall (restrict to Azure services)"
  type        = bool
  default     = true
}