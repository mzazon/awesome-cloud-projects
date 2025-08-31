# Variables for Azure Smart Writing Feedback System
# This file defines all configurable parameters for the infrastructure deployment

variable "resource_group_name" {
  description = "Name of the Azure Resource Group to create or use"
  type        = string
  default     = ""
  
  validation {
    condition     = var.resource_group_name == "" || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition     = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "staging", "demo", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, demo, prod."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "writing-feedback"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "openai_sku_name" {
  description = "SKU name for Azure OpenAI Service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.openai_sku_name)
    error_message = "OpenAI SKU must be either F0 (free tier) or S0 (standard)."
  }
}

variable "gpt_model_name" {
  description = "GPT model name to deploy for text analysis"
  type        = string
  default     = "gpt-4o"
  
  validation {
    condition     = contains(["gpt-4o", "gpt-4", "gpt-35-turbo"], var.gpt_model_name)
    error_message = "GPT model must be one of: gpt-4o, gpt-4, gpt-35-turbo."
  }
}

variable "gpt_model_version" {
  description = "Version of the GPT model to deploy"
  type        = string
  default     = "2024-11-20"
}

variable "gpt_deployment_capacity" {
  description = "Capacity units for GPT model deployment (Tokens Per Minute in thousands)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.gpt_deployment_capacity >= 1 && var.gpt_deployment_capacity <= 1000
    error_message = "GPT deployment capacity must be between 1 and 1000."
  }
}

variable "cosmos_consistency_level" {
  description = "Consistency level for Cosmos DB account"
  type        = string
  default     = "Session"
  
  validation {
    condition     = contains(["Eventual", "ConsistentPrefix", "Session", "BoundedStaleness", "Strong"], var.cosmos_consistency_level)
    error_message = "Cosmos DB consistency level must be one of: Eventual, ConsistentPrefix, Session, BoundedStaleness, Strong."
  }
}

variable "cosmos_database_throughput" {
  description = "Throughput (RU/s) for Cosmos DB database"
  type        = number
  default     = 400
  
  validation {
    condition     = var.cosmos_database_throughput >= 400 && var.cosmos_database_throughput <= 4000
    error_message = "Cosmos DB database throughput must be between 400 and 4000 RU/s."
  }
}

variable "cosmos_container_throughput" {
  description = "Throughput (RU/s) for Cosmos DB container"
  type        = number
  default     = 400
  
  validation {
    condition     = var.cosmos_container_throughput >= 400 && var.cosmos_container_throughput <= 4000
    error_message = "Cosmos DB container throughput must be between 400 and 4000 RU/s."
  }
}

variable "function_app_runtime" {
  description = "Runtime for Azure Functions"
  type        = string
  default     = "node"
  
  validation {
    condition     = contains(["node", "dotnet", "python"], var.function_app_runtime)
    error_message = "Function app runtime must be one of: node, dotnet, python."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Azure Functions"
  type        = string
  default     = "20"
}

variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "enable_automatic_failover" {
  description = "Enable automatic failover for Cosmos DB"
  type        = bool
  default     = false
}

variable "enable_application_insights" {
  description = "Enable Application Insights for monitoring"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}