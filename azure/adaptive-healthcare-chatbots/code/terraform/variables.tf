# Variables for Azure Healthcare Chatbot Infrastructure

# General Configuration
variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Healthcare Bot and SQL Managed Instance."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "healthcare-chatbot"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "organization_name" {
  description = "Healthcare organization name for compliance tagging"
  type        = string
  default     = "Healthcare Organization"
}

# Network Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefix" {
  description = "Address prefix for the SQL Managed Instance subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# SQL Managed Instance Configuration
variable "sql_admin_username" {
  description = "Administrator username for SQL Managed Instance"
  type        = string
  default     = "sqladmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{2,15}$", var.sql_admin_username))
    error_message = "SQL admin username must be 3-16 characters, start with a letter, and contain only letters and numbers."
  }
}

variable "sql_admin_password" {
  description = "Administrator password for SQL Managed Instance"
  type        = string
  sensitive   = true
  default     = null
  
  validation {
    condition = var.sql_admin_password == null || can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[@$!%*?&])[A-Za-z\\d@$!%*?&]{12,128}$", var.sql_admin_password))
    error_message = "SQL admin password must be 12-128 characters with at least one lowercase letter, one uppercase letter, one number, and one special character."
  }
}

variable "sql_sku_name" {
  description = "SKU name for SQL Managed Instance"
  type        = string
  default     = "GP_Gen5"
  
  validation {
    condition     = contains(["GP_Gen5", "BC_Gen5"], var.sql_sku_name)
    error_message = "SQL SKU must be either GP_Gen5 (General Purpose) or BC_Gen5 (Business Critical)."
  }
}

variable "sql_vcores" {
  description = "Number of vCores for SQL Managed Instance"
  type        = number
  default     = 4
  
  validation {
    condition     = contains([4, 8, 16, 24, 32, 40, 64, 80], var.sql_vcores)
    error_message = "SQL vCores must be one of: 4, 8, 16, 24, 32, 40, 64, 80."
  }
}

variable "sql_storage_size_gb" {
  description = "Storage size in GB for SQL Managed Instance"
  type        = number
  default     = 32
  
  validation {
    condition     = var.sql_storage_size_gb >= 32 && var.sql_storage_size_gb <= 16384
    error_message = "SQL storage size must be between 32 GB and 16,384 GB (16 TB)."
  }
}

# Health Bot Configuration
variable "health_bot_sku" {
  description = "SKU for Azure Health Bot"
  type        = string
  default     = "F0"
  
  validation {
    condition     = contains(["F0", "S1"], var.health_bot_sku)
    error_message = "Health Bot SKU must be either F0 (Free) or S1 (Standard)."
  }
}

# Personalizer Configuration
variable "personalizer_sku" {
  description = "SKU for Azure Personalizer"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0"], var.personalizer_sku)
    error_message = "Personalizer SKU must be either F0 (Free) or S0 (Standard)."
  }
}

# Function App Configuration
variable "function_app_service_plan_sku" {
  description = "SKU for the Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3"], var.function_app_service_plan_sku)
    error_message = "Function App SKU must be one of: Y1 (Consumption), EP1, EP2, EP3 (Premium)."
  }
}

# API Management Configuration
variable "apim_sku_name" {
  description = "SKU for API Management"
  type        = string
  default     = "Developer_1"
  
  validation {
    condition = contains([
      "Developer_1", "Standard_1", "Standard_2", 
      "Premium_1", "Premium_2", "Premium_4", "Premium_6"
    ], var.apim_sku_name)
    error_message = "API Management SKU must be a valid tier and capacity combination."
  }
}

variable "apim_publisher_name" {
  description = "Publisher name for API Management"
  type        = string
  default     = "Healthcare Organization"
}

variable "apim_publisher_email" {
  description = "Publisher email for API Management"
  type        = string
  default     = "admin@healthcare.org"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.apim_publisher_email))
    error_message = "Publisher email must be a valid email address."
  }
}

# Security Configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security (recommended for production)"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([
      for ip_range in var.allowed_ip_ranges : can(cidrhost(ip_range, 0))
    ])
    error_message = "All IP ranges must be valid CIDR notation."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Application Insights and monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention must be between 7 and 730 days."
  }
}

# Compliance Configuration
variable "enable_hipaa_compliance" {
  description = "Enable HIPAA compliance features (recommended for healthcare)"
  type        = bool
  default     = true
}

variable "data_classification" {
  description = "Data classification level for compliance"
  type        = string
  default     = "sensitive"
  
  validation {
    condition     = contains(["public", "internal", "confidential", "sensitive"], var.data_classification)
    error_message = "Data classification must be one of: public, internal, confidential, sensitive."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}