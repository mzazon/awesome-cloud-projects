# Input variables for Azure Meeting Intelligence Infrastructure

# Resource naming and location configuration
variable "resource_group_name" {
  description = "Name of the resource group for all meeting intelligence resources"
  type        = string
  default     = "rg-meeting-intelligence"
  
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters long."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", 
      "West Europe", "UK South", "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "UAE North",
      "South Africa North", "Australia East", "Australia Southeast",
      "Central India", "South India", "West India", "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Cognitive Services."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo, test."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "meeting-intelligence"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Storage configuration
variable "storage_account_replication_type" {
  description = "Storage account replication type for meeting recordings"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_tier" {
  description = "Storage tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_tier)
    error_message = "Storage tier must be either Standard or Premium."
  }
}

variable "blob_container_name" {
  description = "Name of the blob container for meeting recordings"
  type        = string
  default     = "meeting-recordings"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.blob_container_name)) && length(var.blob_container_name) >= 3 && length(var.blob_container_name) <= 63
    error_message = "Container name must be between 3-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Cognitive Services configuration
variable "speech_service_sku" {
  description = "SKU for Azure Speech Services (S0 required for batch transcription)"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.speech_service_sku)
    error_message = "Speech Service SKU must be F0 (free) or S0 (standard). S0 required for production workloads."
  }
}

variable "openai_service_sku" {
  description = "SKU for Azure OpenAI Service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_service_sku)
    error_message = "OpenAI Service SKU must be S0 (standard)."
  }
}

variable "openai_model_name" {
  description = "OpenAI model to deploy for meeting analysis"
  type        = string
  default     = "gpt-4o"
  
  validation {
    condition     = contains(["gpt-4", "gpt-4o", "gpt-4-turbo", "gpt-35-turbo"], var.openai_model_name)
    error_message = "OpenAI model must be one of: gpt-4, gpt-4o, gpt-4-turbo, gpt-35-turbo."
  }
}

variable "openai_model_version" {
  description = "Version of the OpenAI model to deploy"
  type        = string
  default     = "2024-11-20"
  
  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.openai_model_version))
    error_message = "Model version must be in YYYY-MM-DD format."
  }
}

variable "openai_deployment_capacity" {
  description = "Capacity for OpenAI model deployment (TPM in thousands)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.openai_deployment_capacity >= 1 && var.openai_deployment_capacity <= 120
    error_message = "OpenAI deployment capacity must be between 1 and 120."
  }
}

# Service Bus configuration
variable "service_bus_sku" {
  description = "SKU for Azure Service Bus namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "Service Bus SKU must be Basic, Standard, or Premium."
  }
}

variable "transcript_queue_name" {
  description = "Name of the Service Bus queue for transcript processing"
  type        = string
  default     = "transcript-processing"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.transcript_queue_name)) && length(var.transcript_queue_name) <= 260
    error_message = "Queue name must contain only letters, numbers, periods, hyphens, and underscores, max 260 characters."
  }
}

variable "results_topic_name" {
  description = "Name of the Service Bus topic for meeting insights"
  type        = string
  default     = "meeting-insights"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.results_topic_name)) && length(var.results_topic_name) <= 260
    error_message = "Topic name must contain only letters, numbers, periods, hyphens, and underscores, max 260 characters."
  }
}

variable "notification_subscription_name" {
  description = "Name of the Service Bus subscription for notifications"
  type        = string
  default     = "notification-subscription"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.notification_subscription_name)) && length(var.notification_subscription_name) <= 50
    error_message = "Subscription name must contain only letters, numbers, periods, hyphens, and underscores, max 50 characters."
  }
}

# Function App configuration
variable "function_app_plan_sku" {
  description = "SKU for the Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2"], var.function_app_plan_sku)
    error_message = "Function App plan SKU must be Y1 (Consumption), EP1-EP3 (Elastic Premium), or P1v2-P3v2 (Premium)."
  }
}

variable "function_app_runtime_version" {
  description = "Python runtime version for Function App"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = contains(["3.9", "3.10", "3.11"], var.function_app_runtime_version)
    error_message = "Function App runtime version must be 3.9, 3.10, or 3.11."
  }
}

variable "functions_extension_version" {
  description = "Azure Functions runtime version"
  type        = string
  default     = "~4"
  
  validation {
    condition     = contains(["~3", "~4"], var.functions_extension_version)
    error_message = "Functions extension version must be ~3 or ~4."
  }
}

# Application Insights configuration
variable "application_insights_retention_days" {
  description = "Number of days to retain Application Insights data"
  type        = number
  default     = 30
  
  validation {
    condition     = var.application_insights_retention_days >= 30 && var.application_insights_retention_days <= 730
    error_message = "Application Insights retention must be between 30 and 730 days."
  }
}

# Security and access configuration
variable "enable_public_access" {
  description = "Enable public access to storage account (disable for production)"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP address ranges allowed to access storage account"
  type        = list(string)
  default     = []
  
  validation {
    condition     = alltrue([for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))])
    error_message = "All IP ranges must be valid CIDR blocks."
  }
}

# Monitoring and alerting configuration
variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for all resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain diagnostic logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
  }
}

# Cost optimization configuration
variable "enable_autoscale" {
  description = "Enable autoscaling for Function App (Premium plans only)"
  type        = bool
  default     = false
}

variable "max_instances" {
  description = "Maximum number of instances for Function App autoscaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 100
    error_message = "Maximum instances must be between 1 and 100."
  }
}

# Resource tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.additional_tags) <= 15
    error_message = "Maximum of 15 additional tags allowed per resource."
  }
}