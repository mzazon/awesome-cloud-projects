# Variables for Azure Product Description Generation solution
# This file defines all configurable parameters for the infrastructure deployment

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the Azure Resource Group to create all resources in"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9-_().]{1,90}$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters and can contain alphanumeric, hyphens, underscores, parentheses, and periods."
  }
}

variable "location" {
  description = "Azure region where all resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada East", "Canada Central", "Brazil South",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central",
      "East Asia", "Southeast Asia", "Japan East", "Japan West",
      "Korea Central", "Australia East", "Australia Southeast",
      "Central India", "South India", "West India",
      "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Project Configuration
variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "prod-desc"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters, lowercase alphanumeric and hyphens only."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_access_tier" {
  description = "Access tier for blob storage (Hot for frequent access, Cool for infrequent access)"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be either Hot or Cool."
  }
}

variable "input_container_name" {
  description = "Name of the blob container for input product images"
  type        = string
  default     = "product-images"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.input_container_name))
    error_message = "Container name must be 3-63 characters, lowercase alphanumeric and hyphens only."
  }
}

variable "output_container_name" {
  description = "Name of the blob container for generated descriptions"
  type        = string
  default     = "descriptions"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.output_container_name))
    error_message = "Container name must be 3-63 characters, lowercase alphanumeric and hyphens only."
  }
}

# AI Vision Service Configuration
variable "computer_vision_sku" {
  description = "SKU for the Computer Vision service (S0=Free tier, S1=Standard)"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["F0", "S0", "S1"], var.computer_vision_sku)
    error_message = "Computer Vision SKU must be one of: F0 (Free), S0 (Standard), S1 (Standard)."
  }
}

# OpenAI Service Configuration
variable "openai_sku" {
  description = "SKU for the OpenAI service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0"], var.openai_sku)
    error_message = "OpenAI SKU must be S0 (Standard)."
  }
}

variable "openai_model_name" {
  description = "Name of the OpenAI model to deploy"
  type        = string
  default     = "gpt-4o"
  
  validation {
    condition     = contains(["gpt-4o", "gpt-4", "gpt-4-32k", "gpt-35-turbo", "gpt-35-turbo-16k"], var.openai_model_name)
    error_message = "OpenAI model must be one of the supported models."
  }
}

variable "openai_model_version" {
  description = "Version of the OpenAI model to deploy"
  type        = string
  default     = "2024-11-20"
}

variable "openai_deployment_sku_capacity" {
  description = "Capacity for the OpenAI model deployment (tokens per minute / 1000)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.openai_deployment_sku_capacity >= 1 && var.openai_deployment_sku_capacity <= 1000
    error_message = "OpenAI deployment capacity must be between 1 and 1000."
  }
}

# Function App Configuration
variable "function_app_service_plan_sku" {
  description = "SKU for the Function App service plan (Y1 for Consumption plan)"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_service_plan_sku)
    error_message = "Function App SKU must be Y1 (Consumption) or EP1/EP2/EP3 (Premium)."
  }
}

variable "function_app_runtime" {
  description = "Runtime for the Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["python", "node", "dotnet"], var.function_app_runtime)
    error_message = "Function App runtime must be python, node, or dotnet."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for the Function App"
  type        = string
  default     = "3.11"
}

# Event Grid Configuration
variable "enable_event_grid" {
  description = "Whether to enable Event Grid integration for automatic processing"
  type        = bool
  default     = true
}

variable "event_grid_included_event_types" {
  description = "List of Event Grid event types to include"
  type        = list(string)
  default     = ["Microsoft.Storage.BlobCreated"]
  
  validation {
    condition     = alltrue([for event in var.event_grid_included_event_types : contains(["Microsoft.Storage.BlobCreated", "Microsoft.Storage.BlobDeleted"], event)])
    error_message = "Event types must be valid Azure Storage event types."
  }
}

# Monitoring and Logging Configuration
variable "enable_application_insights" {
  description = "Whether to enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Application Insights"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

# Security Configuration
variable "enable_managed_identity" {
  description = "Whether to enable system-assigned managed identity for the Function App"
  type        = bool
  default     = true
}

variable "allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

# Tagging Configuration
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "recipe"
    category    = "ai-ml"
    environment = "demo"
  }
}

# Advanced Configuration
variable "function_timeout" {
  description = "Timeout for function execution in minutes"
  type        = number
  default     = 5
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 10
    error_message = "Function timeout must be between 1 and 10 minutes."
  }
}

variable "max_function_instances" {
  description = "Maximum number of function instances for scaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_function_instances >= 1 && var.max_function_instances <= 200
    error_message = "Maximum function instances must be between 1 and 200."
  }
}

# Cost Management Configuration
variable "enable_storage_lifecycle_management" {
  description = "Whether to enable storage lifecycle management for cost optimization"
  type        = bool
  default     = true
}

variable "cool_tier_transition_days" {
  description = "Number of days after which blobs transition to cool tier"
  type        = number
  default     = 30
  
  validation {
    condition     = var.cool_tier_transition_days >= 0 && var.cool_tier_transition_days <= 365
    error_message = "Cool tier transition days must be between 0 and 365."
  }
}

variable "delete_after_days" {
  description = "Number of days after which old blobs are deleted (0 to disable)"
  type        = number
  default     = 90
  
  validation {
    condition     = var.delete_after_days >= 0 && var.delete_after_days <= 3650
    error_message = "Delete after days must be between 0 and 3650 (10 years)."
  }
}