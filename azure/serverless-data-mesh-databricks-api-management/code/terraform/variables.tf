# Core configuration variables
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "eastus"
  
  validation {
    condition = can(regex("^[a-z0-9]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = length(var.environment) >= 2 && length(var.environment) <= 10
    error_message = "Environment name must be between 2 and 10 characters."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "datamesh"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters and numbers."
  }
}

# Resource naming variables
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = null
}

variable "databricks_workspace_name" {
  description = "Name of the Databricks workspace"
  type        = string
  default     = null
}

variable "api_management_name" {
  description = "Name of the API Management service"
  type        = string
  default     = null
}

variable "key_vault_name" {
  description = "Name of the Key Vault"
  type        = string
  default     = null
}

variable "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  type        = string
  default     = null
}

# Databricks configuration
variable "databricks_sku" {
  description = "SKU for Databricks workspace"
  type        = string
  default     = "premium"
  
  validation {
    condition     = contains(["standard", "premium"], var.databricks_sku)
    error_message = "Databricks SKU must be either 'standard' or 'premium'."
  }
}

variable "databricks_managed_resource_group_name" {
  description = "Name of the managed resource group for Databricks"
  type        = string
  default     = null
}

variable "databricks_enable_no_public_ip" {
  description = "Enable no public IP for Databricks workspace"
  type        = bool
  default     = true
}

# API Management configuration
variable "apim_sku_name" {
  description = "SKU for API Management service"
  type        = string
  default     = "Consumption"
  
  validation {
    condition = contains([
      "Consumption",
      "Developer",
      "Basic",
      "Standard",
      "Premium"
    ], var.apim_sku_name)
    error_message = "API Management SKU must be one of: Consumption, Developer, Basic, Standard, Premium."
  }
}

variable "apim_publisher_name" {
  description = "Publisher name for API Management service"
  type        = string
  default     = "Data Mesh Team"
}

variable "apim_publisher_email" {
  description = "Publisher email for API Management service"
  type        = string
  default     = "datamesh@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.apim_publisher_email))
    error_message = "Publisher email must be a valid email address."
  }
}

# Key Vault configuration
variable "key_vault_sku" {
  description = "SKU for Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "key_vault_enable_rbac" {
  description = "Enable RBAC authorization for Key Vault"
  type        = bool
  default     = true
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection for Key Vault"
  type        = bool
  default     = false
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault items"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention must be between 7 and 90 days."
  }
}

# Event Grid configuration
variable "event_grid_topic_input_schema" {
  description = "Input schema for Event Grid topic"
  type        = string
  default     = "EventGridSchema"
  
  validation {
    condition = contains([
      "EventGridSchema",
      "CustomInputSchema",
      "CloudEventSchemaV1_0"
    ], var.event_grid_topic_input_schema)
    error_message = "Event Grid input schema must be one of: EventGridSchema, CustomInputSchema, CloudEventSchemaV1_0."
  }
}

# Networking configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for services"
  type        = bool
  default     = false
}

variable "virtual_network_name" {
  description = "Name of the virtual network (required if enable_private_endpoints is true)"
  type        = string
  default     = null
}

variable "subnet_name" {
  description = "Name of the subnet for private endpoints (required if enable_private_endpoints is true)"
  type        = string
  default     = null
}

# Security configuration
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = []
}

variable "enable_system_assigned_identity" {
  description = "Enable system-assigned managed identity for resources"
  type        = bool
  default     = true
}

# Tagging configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    project     = "data-mesh"
    environment = "demo"
    purpose     = "serverless-data-mesh"
  }
}

# Data product configuration
variable "data_product_apis" {
  description = "List of data product APIs to create"
  type = list(object({
    name         = string
    path         = string
    display_name = string
    description  = string
  }))
  default = [
    {
      name         = "customer-analytics-api"
      path         = "customer-analytics"
      display_name = "Customer Analytics Data Product"
      description  = "Domain-owned customer analytics data product API"
    }
  ]
}

# Unity Catalog configuration
variable "unity_catalog_name" {
  description = "Name of the Unity Catalog"
  type        = string
  default     = "data_mesh_catalog"
}

variable "unity_catalog_schema_name" {
  description = "Name of the Unity Catalog schema"
  type        = string
  default     = "customer_analytics"
}

# Monitoring configuration
variable "enable_monitoring" {
  description = "Enable monitoring and logging for resources"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = null
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