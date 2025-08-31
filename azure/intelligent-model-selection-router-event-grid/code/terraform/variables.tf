# Variable definitions for Azure intelligent model selection architecture
# These variables provide customization for the deployment

# General Configuration Variables
variable "project_name" {
  description = "The name of the project used for resource naming"
  type        = string
  default     = "modelrouter"
  
  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 20
    error_message = "Project name must be between 3 and 20 characters long."
  }
}

variable "environment" {
  description = "The environment for the deployment (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "demo", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, demo, prod."
  }
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US 2"
  
  validation {
    condition = contains([
      "East US 2",
      "Sweden Central"
    ], var.location)
    error_message = "Model Router is currently available only in East US 2 and Sweden Central regions."
  }
}

variable "resource_tags" {
  description = "Common tags to be applied to all resources"
  type        = map(string)
  default = {
    Purpose     = "AI Model Router Recipe"
    Environment = "Demo"
    Project     = "Intelligent Model Selection"
    ManagedBy   = "Terraform"
  }
}

# Storage Configuration Variables
variable "storage_account_tier" {
  description = "The performance tier of the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "The replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS."
  }
}

# Function App Configuration Variables
variable "function_app_runtime" {
  description = "The runtime stack for the Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["python", "node", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: python, node, dotnet, java."
  }
}

variable "function_app_runtime_version" {
  description = "The runtime version for the Function App"
  type        = string
  default     = "3.11"
}

variable "function_app_os_type" {
  description = "The operating system type for the Function App"
  type        = string
  default     = "Linux"
  
  validation {
    condition     = contains(["Linux", "Windows"], var.function_app_os_type)
    error_message = "Function App OS type must be either Linux or Windows."
  }
}

# Azure AI Foundry Configuration Variables
variable "ai_foundry_sku" {
  description = "The SKU for the Azure AI Foundry resource"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0", "S1", "S2", "S3", "S4"], var.ai_foundry_sku)
    error_message = "AI Foundry SKU must be one of: F0, S0, S1, S2, S3, S4."
  }
}

variable "model_deployment_name" {
  description = "The name for the Model Router deployment"
  type        = string
  default     = "model-router-deployment"
  
  validation {
    condition     = length(var.model_deployment_name) >= 3 && length(var.model_deployment_name) <= 64
    error_message = "Model deployment name must be between 3 and 64 characters long."
  }
}

variable "model_name" {
  description = "The model name for the Model Router"
  type        = string
  default     = "model-router"
}

variable "model_version" {
  description = "The model version for the Model Router"
  type        = string
  default     = "2025-05-19"
}

variable "model_sku_capacity" {
  description = "The capacity for the Model Router deployment"
  type        = number
  default     = 50
  
  validation {
    condition     = var.model_sku_capacity >= 1 && var.model_sku_capacity <= 1000
    error_message = "Model SKU capacity must be between 1 and 1000."
  }
}

variable "model_sku_name" {
  description = "The SKU name for the Model Router deployment"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Basic"], var.model_sku_name)
    error_message = "Model SKU name must be either Standard or Basic."
  }
}

# Event Grid Configuration Variables
variable "event_grid_input_schema" {
  description = "The input schema for the Event Grid topic"
  type        = string
  default     = "EventGridSchema"
  
  validation {
    condition = contains([
      "EventGridSchema",
      "CustomEventSchema",
      "CloudEventSchemaV1_0"
    ], var.event_grid_input_schema)
    error_message = "Event Grid input schema must be one of: EventGridSchema, CustomEventSchema, CloudEventSchemaV1_0."
  }
}

variable "event_subscription_included_event_types" {
  description = "The event types to include in the Event Grid subscription"
  type        = list(string)
  default     = ["AIRequest.Submitted"]
}

variable "event_subscription_retry_policy" {
  description = "The retry policy for Event Grid subscription"
  type = object({
    max_delivery_attempts = number
    event_time_to_live    = number
  })
  default = {
    max_delivery_attempts = 30
    event_time_to_live    = 1440
  }
}

# Application Insights Configuration Variables
variable "application_insights_type" {
  description = "The type of Application Insights component"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either web or other."
  }
}

variable "application_insights_retention_days" {
  description = "The retention period in days for Application Insights data"
  type        = number
  default     = 90
  
  validation {
    condition     = var.application_insights_retention_days >= 30 && var.application_insights_retention_days <= 730
    error_message = "Application Insights retention days must be between 30 and 730."
  }
}

# Network Security Configuration Variables
variable "enable_public_network_access" {
  description = "Whether to enable public network access for resources"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = []
}

# Function App Configuration Variables
variable "function_app_settings" {
  description = "Additional application settings for the Function App"
  type        = map(string)
  default = {
    "FUNCTIONS_WORKER_RUNTIME"         = "python"
    "AzureWebJobsFeatureFlags"        = "EnableWorkerIndexing"
    "FUNCTIONS_EXTENSION_VERSION"     = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"        = "1"
  }
}

# Cost Management Variables
variable "enable_daily_quota" {
  description = "Whether to enable daily quota for Application Insights"
  type        = bool
  default     = false
}

variable "daily_quota_gb" {
  description = "Daily quota in GB for Application Insights"
  type        = number
  default     = 1
  
  validation {
    condition     = var.daily_quota_gb >= 0.1 && var.daily_quota_gb <= 1000
    error_message = "Daily quota must be between 0.1 and 1000 GB."
  }
}