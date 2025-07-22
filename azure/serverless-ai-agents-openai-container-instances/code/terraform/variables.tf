# Variables for the Serverless AI Agents infrastructure

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "eastus"
  
  validation {
    condition = can(regex("^[a-z0-9]+$", var.location))
    error_message = "Location must be a valid Azure region name in lowercase."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create"
  type        = string
  default     = ""
  
  validation {
    condition = var.resource_group_name == "" || can(regex("^[a-zA-Z0-9-_]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "ai-agents"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "openai_sku" {
  description = "SKU for Azure OpenAI Service"
  type        = string
  default     = "S0"
  
  validation {
    condition = contains(["F0", "S0"], var.openai_sku)
    error_message = "OpenAI SKU must be either F0 (Free) or S0 (Standard)."
  }
}

variable "openai_model_name" {
  description = "Name of the OpenAI model to deploy"
  type        = string
  default     = "gpt-4"
  
  validation {
    condition = contains(["gpt-4", "gpt-35-turbo", "gpt-4-turbo"], var.openai_model_name)
    error_message = "Model name must be a supported OpenAI model."
  }
}

variable "openai_model_version" {
  description = "Version of the OpenAI model to deploy"
  type        = string
  default     = "0613"
  
  validation {
    condition = can(regex("^[0-9]{4}$", var.openai_model_version))
    error_message = "Model version must be a 4-digit version number."
  }
}

variable "container_registry_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container Registry SKU must be Basic, Standard, or Premium."
  }
}

variable "storage_account_tier" {
  description = "Performance tier for Azure Storage Account"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for Azure Storage Account"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be LRS, GRS, RAGRS, or ZRS."
  }
}

variable "function_app_service_plan_sku" {
  description = "SKU for Function App Service Plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_service_plan_sku)
    error_message = "Function App Service Plan SKU must be Y1 (Consumption), EP1, EP2, or EP3 (Elastic Premium)."
  }
}

variable "container_cpu" {
  description = "CPU cores for container instances"
  type        = number
  default     = 1
  
  validation {
    condition = var.container_cpu >= 0.5 && var.container_cpu <= 4
    error_message = "Container CPU must be between 0.5 and 4 cores."
  }
}

variable "container_memory" {
  description = "Memory in GB for container instances"
  type        = number
  default     = 1.5
  
  validation {
    condition = var.container_memory >= 1 && var.container_memory <= 8
    error_message = "Container memory must be between 1 and 8 GB."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "recipe"
    Environment = "demo"
    Project     = "ai-agents"
  }
}

variable "enable_monitoring" {
  description = "Enable Application Insights monitoring"
  type        = bool
  default     = true
}

variable "enable_container_registry_admin" {
  description = "Enable admin user for Container Registry"
  type        = bool
  default     = true
}

variable "event_grid_topic_input_schema" {
  description = "Input schema for Event Grid topic"
  type        = string
  default     = "EventGridSchema"
  
  validation {
    condition = contains(["EventGridSchema", "CustomEventSchema", "CloudEventSchemaV1_0"], var.event_grid_topic_input_schema)
    error_message = "Event Grid input schema must be EventGridSchema, CustomEventSchema, or CloudEventSchemaV1_0."
  }
}

variable "function_app_runtime" {
  description = "Runtime for Function App"
  type        = string
  default     = "python"
  
  validation {
    condition = contains(["python", "node", "dotnet"], var.function_app_runtime)
    error_message = "Function App runtime must be python, node, or dotnet."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Function App"
  type        = string
  default     = "3.11"
  
  validation {
    condition = can(regex("^[0-9.]+$", var.function_app_runtime_version))
    error_message = "Function App runtime version must be a valid version number."
  }
}