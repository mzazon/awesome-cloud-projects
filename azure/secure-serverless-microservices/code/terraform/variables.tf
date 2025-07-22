# ========================================
# Core Configuration Variables
# ========================================

variable "resource_group_name" {
  description = "Name of the resource group to create all resources in"
  type        = string
  default     = "rg-secure-containers"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.\\(\\)]+$", var.resource_group_name))
    error_message = "Resource group name must contain only letters, numbers, hyphens, periods, underscores, and parentheses."
  }
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Japan East",
      "Japan West", "Australia East", "Australia Southeast", "Southeast Asia",
      "East Asia", "South India", "Central India", "Korea Central", "Korea South"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "secure-containers"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# ========================================
# Container Registry Variables
# ========================================

variable "container_registry_sku" {
  description = "SKU for Azure Container Registry (Basic, Standard, Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container registry SKU must be Basic, Standard, or Premium."
  }
}

variable "container_registry_admin_enabled" {
  description = "Enable admin user for Container Registry"
  type        = bool
  default     = false
}

variable "container_registry_public_network_access" {
  description = "Enable public network access for Container Registry"
  type        = bool
  default     = true
}

# ========================================
# Key Vault Variables
# ========================================

variable "key_vault_sku" {
  description = "SKU for Azure Key Vault (standard, premium)"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be standard or premium."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted keys, secrets, and certificates"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection for Key Vault"
  type        = bool
  default     = false
}

variable "key_vault_public_network_access" {
  description = "Enable public network access for Key Vault"
  type        = string
  default     = "Enabled"
  
  validation {
    condition     = contains(["Enabled", "Disabled"], var.key_vault_public_network_access)
    error_message = "Key Vault public network access must be Enabled or Disabled."
  }
}

# ========================================
# Container Apps Variables
# ========================================

variable "container_apps_environment_internal_load_balancer" {
  description = "Use internal load balancer for Container Apps Environment"
  type        = bool
  default     = false
}

variable "container_apps_environment_zone_redundant" {
  description = "Enable zone redundancy for Container Apps Environment"
  type        = bool
  default     = false
}

# API Service Configuration
variable "api_service_name" {
  description = "Name of the API service container app"
  type        = string
  default     = "api-service"
}

variable "api_service_image" {
  description = "Container image for the API service"
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "api_service_cpu" {
  description = "CPU allocation for API service (in cores)"
  type        = number
  default     = 0.5
  
  validation {
    condition     = var.api_service_cpu >= 0.25 && var.api_service_cpu <= 4
    error_message = "API service CPU must be between 0.25 and 4 cores."
  }
}

variable "api_service_memory" {
  description = "Memory allocation for API service (in Gi)"
  type        = string
  default     = "1.0Gi"
  
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?Gi$", var.api_service_memory))
    error_message = "API service memory must be in format like '1.0Gi' or '2Gi'."
  }
}

variable "api_service_min_replicas" {
  description = "Minimum number of replicas for API service"
  type        = number
  default     = 1
  
  validation {
    condition     = var.api_service_min_replicas >= 0 && var.api_service_min_replicas <= 25
    error_message = "API service min replicas must be between 0 and 25."
  }
}

variable "api_service_max_replicas" {
  description = "Maximum number of replicas for API service"
  type        = number
  default     = 5
  
  validation {
    condition     = var.api_service_max_replicas >= 1 && var.api_service_max_replicas <= 25
    error_message = "API service max replicas must be between 1 and 25."
  }
}

variable "api_service_target_port" {
  description = "Target port for API service"
  type        = number
  default     = 80
  
  validation {
    condition     = var.api_service_target_port >= 1 && var.api_service_target_port <= 65535
    error_message = "API service target port must be between 1 and 65535."
  }
}

# Worker Service Configuration
variable "worker_service_name" {
  description = "Name of the worker service container app"
  type        = string
  default     = "worker-service"
}

variable "worker_service_image" {
  description = "Container image for the worker service"
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "worker_service_cpu" {
  description = "CPU allocation for worker service (in cores)"
  type        = number
  default     = 0.25
  
  validation {
    condition     = var.worker_service_cpu >= 0.25 && var.worker_service_cpu <= 4
    error_message = "Worker service CPU must be between 0.25 and 4 cores."
  }
}

variable "worker_service_memory" {
  description = "Memory allocation for worker service (in Gi)"
  type        = string
  default     = "0.5Gi"
  
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?Gi$", var.worker_service_memory))
    error_message = "Worker service memory must be in format like '0.5Gi' or '1Gi'."
  }
}

variable "worker_service_min_replicas" {
  description = "Minimum number of replicas for worker service"
  type        = number
  default     = 0
  
  validation {
    condition     = var.worker_service_min_replicas >= 0 && var.worker_service_min_replicas <= 25
    error_message = "Worker service min replicas must be between 0 and 25."
  }
}

variable "worker_service_max_replicas" {
  description = "Maximum number of replicas for worker service"
  type        = number
  default     = 3
  
  validation {
    condition     = var.worker_service_max_replicas >= 1 && var.worker_service_max_replicas <= 25
    error_message = "Worker service max replicas must be between 1 and 25."
  }
}

variable "worker_service_target_port" {
  description = "Target port for worker service"
  type        = number
  default     = 80
  
  validation {
    condition     = var.worker_service_target_port >= 1 && var.worker_service_target_port <= 65535
    error_message = "Worker service target port must be between 1 and 65535."
  }
}

# ========================================
# Monitoring Variables
# ========================================

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}

variable "application_insights_retention_days" {
  description = "Number of days to retain data in Application Insights"
  type        = number
  default     = 90
  
  validation {
    condition     = var.application_insights_retention_days >= 30 && var.application_insights_retention_days <= 730
    error_message = "Application Insights retention days must be between 30 and 730."
  }
}

variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts for Container Apps"
  type        = bool
  default     = true
}

variable "cpu_alert_threshold" {
  description = "CPU usage threshold for alerts (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cpu_alert_threshold >= 1 && var.cpu_alert_threshold <= 100
    error_message = "CPU alert threshold must be between 1 and 100."
  }
}

variable "memory_alert_threshold" {
  description = "Memory usage threshold for alerts (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.memory_alert_threshold >= 1 && var.memory_alert_threshold <= 100
    error_message = "Memory alert threshold must be between 1 and 100."
  }
}

# ========================================
# Security Variables
# ========================================

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources (CIDR notation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR notation."
  }
}

variable "enable_rbac" {
  description = "Enable Role-Based Access Control (RBAC)"
  type        = bool
  default     = true
}

# ========================================
# Sample Secret Variables
# ========================================

variable "database_connection_string" {
  description = "Sample database connection string for Key Vault"
  type        = string
  default     = "Server=tcp:myserver.database.windows.net;Database=mydb;Authentication=Active Directory Managed Identity;"
  sensitive   = true
}

variable "api_key" {
  description = "Sample API key for Key Vault"
  type        = string
  default     = "sample-api-key"
  sensitive   = true
}

variable "service_bus_connection" {
  description = "Sample Service Bus connection string for Key Vault"
  type        = string
  default     = "Endpoint=sb://namespace.servicebus.windows.net/;Authentication=Managed Identity"
  sensitive   = true
}

# ========================================
# Resource Tags
# ========================================

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "recipe"
    Environment = "demo"
    Owner       = "container-apps-recipe"
    Recipe      = "secure-container-orchestration"
    IaC         = "terraform"
  }
}