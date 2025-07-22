# Core configuration variables
variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Norway East", "Switzerland North", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "Central India", "South India",
      "Japan East", "Japan West", "Korea Central", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "The location must be a valid Azure region that supports Azure OpenAI Service."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "intelligent-automation"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Resource naming and tagging
variable "resource_group_name" {
  description = "Name of the resource group. If not provided, will be generated from project_name and environment"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Intelligent Business Process Automation"
    Environment = "Demo"
    ManagedBy   = "Terraform"
  }
}

# Azure OpenAI Service configuration
variable "openai_sku" {
  description = "SKU for Azure OpenAI Service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.openai_sku)
    error_message = "OpenAI SKU must be either F0 (free) or S0 (standard)."
  }
}

variable "gpt4_deployment_name" {
  description = "Name for the GPT-4 model deployment"
  type        = string
  default     = "gpt-4"
}

variable "gpt4_model_version" {
  description = "Version of GPT-4 model to deploy"
  type        = string
  default     = "0613"
  
  validation {
    condition     = contains(["0613", "1106-Preview"], var.gpt4_model_version)
    error_message = "GPT-4 model version must be either 0613 or 1106-Preview."
  }
}

variable "gpt4_scale_type" {
  description = "Scale type for GPT-4 deployment"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Manual"], var.gpt4_scale_type)
    error_message = "Scale type must be either Standard or Manual."
  }
}

# Service Bus configuration
variable "servicebus_sku" {
  description = "SKU for Service Bus namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.servicebus_sku)
    error_message = "Service Bus SKU must be Basic, Standard, or Premium."
  }
}

variable "processing_queue_max_size" {
  description = "Maximum size of the processing queue in MB"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.processing_queue_max_size >= 1 && var.processing_queue_max_size <= 5120
    error_message = "Processing queue max size must be between 1 and 5120 MB."
  }
}

variable "message_ttl_minutes" {
  description = "Time to live for messages in minutes"
  type        = number
  default     = 10
  
  validation {
    condition     = var.message_ttl_minutes >= 1 && var.message_ttl_minutes <= 1440
    error_message = "Message TTL must be between 1 and 1440 minutes (24 hours)."
  }
}

# Container Apps configuration
variable "container_apps_sku" {
  description = "SKU for Container Apps Environment"
  type        = string
  default     = "Consumption"
  
  validation {
    condition     = contains(["Consumption", "Dedicated"], var.container_apps_sku)
    error_message = "Container Apps SKU must be either Consumption or Dedicated."
  }
}

variable "container_registry_sku" {
  description = "SKU for Container Registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container Registry SKU must be Basic, Standard, or Premium."
  }
}

variable "job_replica_timeout" {
  description = "Timeout for job replicas in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.job_replica_timeout >= 60 && var.job_replica_timeout <= 1800
    error_message = "Job replica timeout must be between 60 and 1800 seconds."
  }
}

variable "job_parallelism" {
  description = "Number of parallel job executions"
  type        = number
  default     = 3
  
  validation {
    condition     = var.job_parallelism >= 1 && var.job_parallelism <= 10
    error_message = "Job parallelism must be between 1 and 10."
  }
}

variable "job_retry_limit" {
  description = "Maximum number of job retry attempts"
  type        = number
  default     = 2
  
  validation {
    condition     = var.job_retry_limit >= 0 && var.job_retry_limit <= 5
    error_message = "Job retry limit must be between 0 and 5."
  }
}

# Monitoring configuration
variable "log_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "enable_dashboard" {
  description = "Create monitoring dashboard"
  type        = bool
  default     = true
}

# Security and access configuration
variable "enable_system_assigned_identity" {
  description = "Enable system-assigned managed identity for Container Apps"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources (CIDR notation)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_ip_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "All IP ranges must be in valid CIDR notation (e.g., 10.0.0.0/8)."
  }
}

# Cost optimization
variable "enable_auto_shutdown" {
  description = "Enable automatic shutdown for development environments"
  type        = bool
  default     = false
}

variable "auto_shutdown_time" {
  description = "Time to automatically shutdown resources (HH:MM format, 24-hour)"
  type        = string
  default     = "18:00"
  
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.auto_shutdown_time))
    error_message = "Auto shutdown time must be in HH:MM format (24-hour)."
  }
}

# Feature flags
variable "enable_advanced_monitoring" {
  description = "Enable advanced monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Enable backup for stateful resources"
  type        = bool
  default     = false
}

variable "create_sample_data" {
  description = "Create sample data for testing"
  type        = bool
  default     = false
}