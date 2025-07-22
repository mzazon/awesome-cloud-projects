# Variables for Azure Real-Time Collaborative Dashboard Infrastructure

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "collab-dashboard"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for globally unique resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 8
    error_message = "Random suffix length must be between 4 and 8 characters."
  }
}

# Web PubSub Configuration
variable "webpubsub_sku" {
  description = "Azure Web PubSub SKU and capacity"
  type = object({
    name     = string
    capacity = number
  })
  default = {
    name     = "Free_F1"
    capacity = 1
  }
  
  validation {
    condition = contains(["Free_F1", "Standard_S1", "Premium_P1"], var.webpubsub_sku.name)
    error_message = "Web PubSub SKU must be one of: Free_F1, Standard_S1, Premium_P1."
  }
}

variable "webpubsub_hub_name" {
  description = "Name of the Web PubSub hub for dashboard communication"
  type        = string
  default     = "dashboard"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,127}$", var.webpubsub_hub_name))
    error_message = "Hub name must start with a letter and be 1-128 characters of letters and numbers."
  }
}

# Function App Configuration
variable "function_app_sku" {
  description = "Function App service plan SKU"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_sku)
    error_message = "Function App SKU must be one of: Y1 (Consumption), EP1, EP2, EP3 (Premium)."
  }
}

variable "function_app_runtime" {
  description = "Function App runtime configuration"
  type = object({
    name    = string
    version = string
  })
  default = {
    name    = "node"
    version = "18"
  }
  
  validation {
    condition = contains(["node", "dotnet", "python"], var.function_app_runtime.name)
    error_message = "Runtime must be one of: node, dotnet, python."
  }
}

# Static Web App Configuration
variable "static_web_app_sku" {
  description = "Static Web App SKU tier"
  type        = string
  default     = "Free"
  
  validation {
    condition = contains(["Free", "Standard"], var.static_web_app_sku)
    error_message = "Static Web App SKU must be Free or Standard."
  }
}

# Log Analytics Configuration
variable "log_analytics_retention_days" {
  description = "Log Analytics workspace data retention in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "log_analytics_sku" {
  description = "Log Analytics workspace pricing tier"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains(["Free", "PerNode", "PerGB2018", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Premium."
  }
}

# Monitoring Configuration
variable "enable_alerts" {
  description = "Enable Azure Monitor alerts for the dashboard infrastructure"
  type        = bool
  default     = true
}

variable "alert_email_recipients" {
  description = "List of email addresses to receive alert notifications"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.alert_email_recipients : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid email format."
  }
}

# Security Configuration
variable "allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "enable_public_network_access" {
  description = "Enable public network access to services"
  type        = bool
  default     = true
}

# Tagging Configuration
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "collaborative-dashboard"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

variable "additional_tags" {
  description = "Additional tags to merge with common tags"
  type        = map(string)
  default     = {}
}