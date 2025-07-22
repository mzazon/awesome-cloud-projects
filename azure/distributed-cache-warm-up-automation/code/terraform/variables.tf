# Variables for Azure distributed cache warm-up workflow infrastructure

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "cache-warmup"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "cache-warmup"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Container Apps Configuration
variable "container_apps_cpu" {
  description = "CPU allocation for container apps (in cores)"
  type        = number
  default     = 0.5
  
  validation {
    condition     = var.container_apps_cpu >= 0.25 && var.container_apps_cpu <= 4
    error_message = "Container Apps CPU must be between 0.25 and 4 cores."
  }
}

variable "container_apps_memory" {
  description = "Memory allocation for container apps (in GB)"
  type        = string
  default     = "1.0Gi"
  
  validation {
    condition     = can(regex("^[0-9]+\\.?[0-9]*Gi$", var.container_apps_memory))
    error_message = "Memory must be specified in Gi format (e.g., 1.0Gi, 2.5Gi)."
  }
}

variable "worker_parallelism" {
  description = "Number of parallel worker instances"
  type        = number
  default     = 4
  
  validation {
    condition     = var.worker_parallelism >= 1 && var.worker_parallelism <= 10
    error_message = "Worker parallelism must be between 1 and 10."
  }
}

variable "coordinator_schedule" {
  description = "Cron expression for coordinator job scheduling"
  type        = string
  default     = "0 */6 * * *"  # Every 6 hours
  
  validation {
    condition     = can(regex("^[0-9\\*\\-\\,\\/\\s]+$", var.coordinator_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

# Redis Configuration
variable "redis_sku_name" {
  description = "Redis Enterprise SKU name"
  type        = string
  default     = "Enterprise_E10"
  
  validation {
    condition     = contains(["Enterprise_E10", "Enterprise_E20", "Enterprise_E50", "Enterprise_E100"], var.redis_sku_name)
    error_message = "Redis SKU must be one of: Enterprise_E10, Enterprise_E20, Enterprise_E50, Enterprise_E100."
  }
}

variable "redis_capacity" {
  description = "Redis cache capacity"
  type        = number
  default     = 2
  
  validation {
    condition     = var.redis_capacity >= 2 && var.redis_capacity <= 120
    error_message = "Redis capacity must be between 2 and 120."
  }
}

variable "redis_family" {
  description = "Redis cache family"
  type        = string
  default     = "E"
  
  validation {
    condition     = contains(["E"], var.redis_family)
    error_message = "Redis family must be 'E' for Enterprise tier."
  }
}

variable "enable_non_ssl_port" {
  description = "Enable non-SSL port for Redis"
  type        = bool
  default     = false
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

variable "storage_access_tier" {
  description = "Storage account access tier"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be Hot or Cool."
  }
}

# Key Vault Configuration
variable "key_vault_sku_name" {
  description = "Key Vault SKU name"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku_name)
    error_message = "Key Vault SKU must be standard or premium."
  }
}

variable "key_vault_enabled_for_deployment" {
  description = "Enable Key Vault for Azure Virtual Machines deployment"
  type        = bool
  default     = false
}

variable "key_vault_enabled_for_disk_encryption" {
  description = "Enable Key Vault for Azure Disk Encryption"
  type        = bool
  default     = false
}

variable "key_vault_enabled_for_template_deployment" {
  description = "Enable Key Vault for Azure Resource Manager template deployment"
  type        = bool
  default     = false
}

# Log Analytics Configuration
variable "log_analytics_sku" {
  description = "Log Analytics workspace SKU"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["PerGB2018", "Free", "Standalone", "PerNode", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: PerGB2018, Free, Standalone, PerNode, Premium."
  }
}

variable "log_analytics_retention_in_days" {
  description = "Log Analytics workspace retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_in_days >= 30 && var.log_analytics_retention_in_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

# Container Registry Configuration
variable "container_registry_sku" {
  description = "Container Registry SKU"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container Registry SKU must be Basic, Standard, or Premium."
  }
}

variable "container_registry_admin_enabled" {
  description = "Enable admin user for Container Registry"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_monitoring_alerts" {
  description = "Enable Azure Monitor alerts"
  type        = bool
  default     = true
}

variable "alert_email_address" {
  description = "Email address for alert notifications"
  type        = string
  default     = "admin@company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email_address))
    error_message = "Alert email address must be a valid email format."
  }
}

# Container Images Configuration
variable "coordinator_image" {
  description = "Coordinator container image"
  type        = string
  default     = "mcr.microsoft.com/dotnet/samples:aspnetapp"
}

variable "worker_image" {
  description = "Worker container image"
  type        = string
  default     = "mcr.microsoft.com/dotnet/samples:aspnetapp"
}

# Network Configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for Azure services"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of allowed IP ranges for firewall rules"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Resource Naming Configuration
variable "resource_name_suffix" {
  description = "Optional suffix for resource names"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.resource_name_suffix))
    error_message = "Resource name suffix must contain only lowercase letters, numbers, and hyphens."
  }
}