# Core Configuration Variables
variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central",
      "Australia East", "Australia Southeast", "Southeast Asia",
      "East Asia", "Japan East", "Japan West", "Korea Central",
      "Korea South", "India Central", "India South", "India West",
      "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "mlflow-lifecycle"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase alphanumeric and hyphens only."
  }
}

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the Azure Resource Group (leave empty for auto-generation)"
  type        = string
  default     = ""
}

# Machine Learning Workspace Configuration
variable "ml_workspace_name" {
  description = "Name of the Azure Machine Learning workspace (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "ml_compute_instance_size" {
  description = "Size of the ML compute instance"
  type        = string
  default     = "Standard_DS3_v2"
  
  validation {
    condition = contains([
      "Standard_DS2_v2", "Standard_DS3_v2", "Standard_DS4_v2",
      "Standard_DS11_v2", "Standard_DS12_v2", "Standard_DS13_v2",
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3"
    ], var.ml_compute_instance_size)
    error_message = "ML compute instance size must be a valid Azure VM size."
  }
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Storage account tier"
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
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Container Apps Configuration
variable "container_app_min_replicas" {
  description = "Minimum number of container app replicas"
  type        = number
  default     = 1
  
  validation {
    condition     = var.container_app_min_replicas >= 0 && var.container_app_min_replicas <= 25
    error_message = "Container app min replicas must be between 0 and 25."
  }
}

variable "container_app_max_replicas" {
  description = "Maximum number of container app replicas"
  type        = number
  default     = 10
  
  validation {
    condition     = var.container_app_max_replicas >= 1 && var.container_app_max_replicas <= 300
    error_message = "Container app max replicas must be between 1 and 300."
  }
}

variable "container_app_cpu" {
  description = "CPU allocation for container app"
  type        = number
  default     = 1.0
  
  validation {
    condition     = var.container_app_cpu >= 0.25 && var.container_app_cpu <= 4.0
    error_message = "Container app CPU must be between 0.25 and 4.0."
  }
}

variable "container_app_memory" {
  description = "Memory allocation for container app (in Gi)"
  type        = string
  default     = "2.0Gi"
  
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?Gi$", var.container_app_memory))
    error_message = "Container app memory must be in format like '2.0Gi'."
  }
}

# Container Registry Configuration
variable "container_registry_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container registry SKU must be Basic, Standard, or Premium."
  }
}

variable "container_registry_admin_enabled" {
  description = "Enable admin user for container registry"
  type        = bool
  default     = true
}

# Key Vault Configuration
variable "key_vault_sku" {
  description = "SKU for Azure Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be standard or premium."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention days must be between 7 and 90."
  }
}

# Log Analytics Configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standalone, Standard, Premium."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}

# Application Insights Configuration
variable "application_insights_type" {
  description = "Type of Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be web or other."
  }
}

# Model Configuration
variable "model_name" {
  description = "Default model name for MLflow registry"
  type        = string
  default     = "demo-regression-model"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{3,50}$", var.model_name))
    error_message = "Model name must be 3-50 characters, alphanumeric, hyphens, and underscores only."
  }
}

variable "model_version" {
  description = "Model version to deploy"
  type        = string
  default     = "latest"
}

# Monitoring and Alerting Configuration
variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts for the solution"
  type        = bool
  default     = true
}

variable "alert_email_recipients" {
  description = "List of email addresses to receive alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.alert_email_recipients : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid."
  }
}

# Security Configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Default allows all - should be restricted in production
}

# Tags Configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}