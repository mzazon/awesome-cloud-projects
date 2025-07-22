# Variables for the stateful container workloads deployment

variable "resource_group_name" {
  description = "Name of the resource group to create"
  type        = string
  default     = "rg-stateful-containers"
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "Central US", "North Central US", "South Central US", 
      "West Central US", "West US", "West US 2", "West US 3", "Canada Central",
      "Canada East", "Brazil South", "North Europe", "West Europe", "UK South",
      "UK West", "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "Sweden Central", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "Central India", "South India",
      "West India", "Japan East", "Japan West", "Korea Central", "Korea South",
      "Southeast Asia", "East Asia", "China East 2", "China North 2"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "stateful-containers"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "file_share_quota" {
  description = "Maximum size of the file share in GB"
  type        = number
  default     = 100
  
  validation {
    condition     = var.file_share_quota >= 1 && var.file_share_quota <= 102400
    error_message = "File share quota must be between 1 and 102400 GB."
  }
}

variable "file_share_name" {
  description = "Name of the Azure Files share"
  type        = string
  default     = "containerdata"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.file_share_name))
    error_message = "File share name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "container_registry_sku" {
  description = "SKU for the Azure Container Registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container registry SKU must be one of: Basic, Standard, Premium."
  }
}

variable "postgres_password" {
  description = "Password for the PostgreSQL database"
  type        = string
  default     = "SecurePassword123!"
  sensitive   = true
  
  validation {
    condition     = length(var.postgres_password) >= 8
    error_message = "PostgreSQL password must be at least 8 characters long."
  }
}

variable "postgres_database" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "appdb"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.postgres_database))
    error_message = "Database name must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "postgres_cpu_cores" {
  description = "Number of CPU cores for the PostgreSQL container"
  type        = number
  default     = 1
  
  validation {
    condition     = var.postgres_cpu_cores >= 0.1 && var.postgres_cpu_cores <= 4
    error_message = "CPU cores must be between 0.1 and 4."
  }
}

variable "postgres_memory_gb" {
  description = "Amount of memory in GB for the PostgreSQL container"
  type        = number
  default     = 2
  
  validation {
    condition     = var.postgres_memory_gb >= 0.5 && var.postgres_memory_gb <= 14
    error_message = "Memory must be between 0.5 and 14 GB."
  }
}

variable "app_cpu_cores" {
  description = "Number of CPU cores for the application container"
  type        = number
  default     = 0.5
  
  validation {
    condition     = var.app_cpu_cores >= 0.1 && var.app_cpu_cores <= 4
    error_message = "CPU cores must be between 0.1 and 4."
  }
}

variable "app_memory_gb" {
  description = "Amount of memory in GB for the application container"
  type        = number
  default     = 1
  
  validation {
    condition     = var.app_memory_gb >= 0.5 && var.app_memory_gb <= 14
    error_message = "Memory must be between 0.5 and 14 GB."
  }
}

variable "worker_cpu_cores" {
  description = "Number of CPU cores for the worker container"
  type        = number
  default     = 0.5
  
  validation {
    condition     = var.worker_cpu_cores >= 0.1 && var.worker_cpu_cores <= 4
    error_message = "CPU cores must be between 0.1 and 4."
  }
}

variable "worker_memory_gb" {
  description = "Amount of memory in GB for the worker container"
  type        = number
  default     = 0.5
  
  validation {
    condition     = var.worker_memory_gb >= 0.5 && var.worker_memory_gb <= 14
    error_message = "Memory must be between 0.5 and 14 GB."
  }
}

variable "container_restart_policy" {
  description = "Restart policy for container instances"
  type        = string
  default     = "Always"
  
  validation {
    condition     = contains(["Always", "Never", "OnFailure"], var.container_restart_policy)
    error_message = "Container restart policy must be one of: Always, Never, OnFailure."
  }
}

variable "enable_log_analytics" {
  description = "Enable Log Analytics workspace for container monitoring"
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in Log Analytics"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "recipe"
    environment = "demo"
    project     = "stateful-containers"
  }
}