# Variables for Azure Health Bot deployment

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase letters and numbers."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "Southeast Asia", "East Asia",
      "Japan East", "Japan West", "Korea Central", "India Central", "India South"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "healthbot"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name)) && length(var.project_name) <= 20
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers and hyphens, end with alphanumeric character, and be 20 characters or less."
  }
}

variable "health_bot_sku" {
  description = "SKU for Azure Health Bot service"
  type        = string
  default     = "F0"
  
  validation {
    condition     = contains(["F0", "S1"], var.health_bot_sku)
    error_message = "Health Bot SKU must be either 'F0' (Free) or 'S1' (Standard)."
  }
}

variable "enable_hipaa_compliance" {
  description = "Enable HIPAA compliance features for the Health Bot"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "healthcare-chatbot"
    compliance  = "hipaa"
    managed_by  = "terraform"
  }
  
  validation {
    condition     = alltrue([for k, v in var.tags : can(regex("^[a-zA-Z0-9-_\\.\\s]*$", k)) && can(regex("^[a-zA-Z0-9-_\\.\\s]*$", v))])
    error_message = "Tags must contain only alphanumeric characters, hyphens, underscores, periods, and spaces."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group (optional, will be generated if not provided)"
  type        = string
  default     = ""
}

variable "health_bot_name" {
  description = "Name of the Health Bot instance (optional, will be generated if not provided)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.health_bot_name == "" || (can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.health_bot_name)) && length(var.health_bot_name) <= 64)
    error_message = "Health Bot name must start with a letter, contain only letters, numbers and hyphens, end with alphanumeric character, and be 64 characters or less."
  }
}