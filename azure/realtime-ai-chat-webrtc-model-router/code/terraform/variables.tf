# Variables for Real-time AI Chat with WebRTC and Model Router
variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, hyphens."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US 2"
  
  validation {
    condition = contains([
      "East US 2", "Sweden Central", "eastus2", "swedencentral"
    ], var.location)
    error_message = "Location must be East US 2 or Sweden Central for Azure OpenAI Realtime API support."
  }
}

variable "environment" {
  description = "Environment tag for resources (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "realtime-chat"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "openai_sku_name" {
  description = "SKU for Azure OpenAI service"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["S0", "S1", "F0"], var.openai_sku_name)
    error_message = "OpenAI SKU must be one of: F0, S0, S1."
  }
}

variable "signalr_sku" {
  description = "SKU configuration for SignalR Service"
  type = object({
    name     = string
    capacity = number
  })
  default = {
    name     = "Standard_S1"
    capacity = 1
  }
  
  validation {
    condition = contains([
      "Free_F1", "Standard_S1", "Premium_P1"
    ], var.signalr_sku.name)
    error_message = "SignalR SKU name must be one of: Free_F1, Standard_S1, Premium_P1."
  }
  
  validation {
    condition     = var.signalr_sku.capacity >= 1 && var.signalr_sku.capacity <= 100
    error_message = "SignalR capacity must be between 1 and 100."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS."
  }
}

variable "function_app_plan_sku" {
  description = "Function App service plan SKU (Y1 for Consumption, EP1-EP3 for Premium)"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains([
      "Y1", "EP1", "EP2", "EP3"
    ], var.function_app_plan_sku)
    error_message = "Function App SKU must be Y1 (Consumption) or EP1-EP3 (Premium)."
  }
}

variable "gpt_4o_mini_capacity" {
  description = "Token capacity for GPT-4o-mini-realtime deployment (TPM in thousands)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.gpt_4o_mini_capacity >= 1 && var.gpt_4o_mini_capacity <= 100
    error_message = "GPT-4o-mini capacity must be between 1 and 100 (thousands of tokens per minute)."
  }
}

variable "gpt_4o_capacity" {
  description = "Token capacity for GPT-4o-realtime deployment (TPM in thousands)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.gpt_4o_capacity >= 1 && var.gpt_4o_capacity <= 100
    error_message = "GPT-4o capacity must be between 1 and 100 (thousands of tokens per minute)."
  }
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for services"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain diagnostic logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 1 and 730."
  }
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.tags) <= 15
    error_message = "Maximum of 15 additional tags allowed."
  }
}

# Local values for computed configurations
locals {
  # Generate random suffix for unique resource names
  random_suffix = random_id.suffix.hex
  
  # Resource naming with consistent pattern
  resource_prefix = "${var.project_name}-${var.environment}"
  
  # Standardized location mapping
  location_short = lower(replace(var.location, " ", ""))
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "realtime-ai-chat"
    CreatedBy   = "terraform"
    Location    = var.location
  }, var.tags)
}