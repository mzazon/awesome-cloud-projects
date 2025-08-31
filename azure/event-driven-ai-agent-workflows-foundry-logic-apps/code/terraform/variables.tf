# Variables for Event-Driven AI Agent Workflows with AI Foundry and Logic Apps
# This file defines all configurable parameters for the infrastructure

variable "resource_group_name" {
  description = "Name of the Azure resource group to create"
  type        = string
  default     = "rg-ai-workflows"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters and can contain alphanumeric, underscore, parentheses, hyphen, and period characters."
  }
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "Canada Central", "Canada East",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North",
      "Australia East", "Australia Southeast",
      "Southeast Asia", "East Asia", "Japan East", "Japan West",
      "Korea Central", "India Central"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports AI services."
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
  description = "Project name used for resource naming"
  type        = string
  default     = "ai-workflows"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters and contain only alphanumeric characters and hyphens."
  }
}

variable "service_bus_sku" {
  description = "SKU for the Service Bus namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "Service Bus SKU must be Basic, Standard, or Premium."
  }
}

variable "service_bus_queue_max_size" {
  description = "Maximum size of the Service Bus queue in MB"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.service_bus_queue_max_size >= 1 && var.service_bus_queue_max_size <= 80 * 1024
    error_message = "Queue max size must be between 1 MB and 80 GB (81920 MB)."
  }
}

variable "service_bus_message_ttl" {
  description = "Time to live for messages in Service Bus (ISO 8601 duration format)"
  type        = string
  default     = "P14D"  # 14 days
  
  validation {
    condition     = can(regex("^P\\d+D$", var.service_bus_message_ttl))
    error_message = "Message TTL must be in ISO 8601 duration format (e.g., P14D for 14 days)."
  }
}

variable "ai_foundry_hub_name" {
  description = "Name for the AI Foundry hub workspace"
  type        = string
  default     = ""  # Will be generated if empty
  
  validation {
    condition     = var.ai_foundry_hub_name == "" || can(regex("^[a-zA-Z][a-zA-Z0-9-]{2,32}$", var.ai_foundry_hub_name))
    error_message = "AI Foundry hub name must start with a letter, be 3-33 characters long, and contain only alphanumeric characters and hyphens."
  }
}

variable "ai_foundry_project_name" {
  description = "Name for the AI Foundry project workspace"
  type        = string
  default     = ""  # Will be generated if empty
  
  validation {
    condition     = var.ai_foundry_project_name == "" || can(regex("^[a-zA-Z][a-zA-Z0-9-]{2,32}$", var.ai_foundry_project_name))
    error_message = "AI Foundry project name must start with a letter, be 3-33 characters long, and contain only alphanumeric characters and hyphens."
  }
}

variable "logic_app_name" {
  description = "Name for the Logic App workflow"
  type        = string
  default     = ""  # Will be generated if empty
  
  validation {
    condition     = var.logic_app_name == "" || can(regex("^[a-zA-Z][a-zA-Z0-9-]{2,79}$", var.logic_app_name))
    error_message = "Logic App name must start with a letter, be 3-80 characters long, and contain only alphanumeric characters and hyphens."
  }
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain diagnostic logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 730
    error_message = "Log retention must be between 1 and 730 days."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "create_resource_group" {
  description = "Whether to create a new resource group or use an existing one"
  type        = bool
  default     = true
}

variable "ai_model_deployment_name" {
  description = "Name for the AI model deployment (for future use)"
  type        = string
  default     = "gpt-4o"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,64}$", var.ai_model_deployment_name))
    error_message = "AI model deployment name must be 1-64 characters and contain only alphanumeric characters and hyphens."
  }
}

variable "service_bus_topic_enable_partitioning" {
  description = "Enable partitioning for Service Bus topic"
  type        = bool
  default     = false
}

variable "logic_app_trigger_frequency" {
  description = "Frequency for Logic App trigger polling (Minute, Hour, Day)"
  type        = string
  default     = "Minute"
  
  validation {
    condition     = contains(["Minute", "Hour", "Day"], var.logic_app_trigger_frequency)
    error_message = "Logic App trigger frequency must be Minute, Hour, or Day."
  }
}

variable "logic_app_trigger_interval" {
  description = "Interval for Logic App trigger polling"
  type        = number
  default     = 1
  
  validation {
    condition     = var.logic_app_trigger_interval >= 1 && var.logic_app_trigger_interval <= 1000
    error_message = "Logic App trigger interval must be between 1 and 1000."
  }
}