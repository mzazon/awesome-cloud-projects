# Core Infrastructure Variables
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-video-conferencing-app"
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9\\s]+$", var.location))
    error_message = "Location must be a valid Azure region name."
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

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "video-conferencing"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Container Registry Variables
variable "container_registry_sku" {
  description = "SKU for the Azure Container Registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container registry SKU must be Basic, Standard, or Premium."
  }
}

variable "container_registry_admin_enabled" {
  description = "Enable admin user for the container registry"
  type        = bool
  default     = true
}

# Communication Services Variables
variable "communication_services_data_location" {
  description = "Data location for Azure Communication Services"
  type        = string
  default     = "UnitedStates"
  
  validation {
    condition = contains([
      "UnitedStates", "Europe", "Australia", "UnitedKingdom", 
      "France", "Germany", "Switzerland", "Norway", "UAE"
    ], var.communication_services_data_location)
    error_message = "Data location must be a valid Azure Communication Services region."
  }
}

# Storage Account Variables
variable "storage_account_tier" {
  description = "Performance tier for the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

variable "storage_account_access_tier" {
  description = "Access tier for the storage account"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_account_access_tier)
    error_message = "Storage access tier must be Hot or Cool."
  }
}

# App Service Plan Variables
variable "app_service_plan_sku" {
  description = "SKU for the App Service Plan"
  type        = string
  default     = "P1v2"
  
  validation {
    condition = can(regex("^[BSPM][0-9][v2-3]?$", var.app_service_plan_sku))
    error_message = "App Service Plan SKU must be valid (e.g., B1, S1, P1v2, P2v3)."
  }
}

variable "app_service_plan_worker_count" {
  description = "Number of worker instances for the App Service Plan"
  type        = number
  default     = 1
  
  validation {
    condition     = var.app_service_plan_worker_count >= 1 && var.app_service_plan_worker_count <= 30
    error_message = "Worker count must be between 1 and 30."
  }
}

# Web App Variables
variable "web_app_always_on" {
  description = "Keep the web app always on"
  type        = bool
  default     = true
}

variable "web_app_ftps_state" {
  description = "FTPS state for the web app"
  type        = string
  default     = "Disabled"
  
  validation {
    condition     = contains(["AllAllowed", "FtpsOnly", "Disabled"], var.web_app_ftps_state)
    error_message = "FTPS state must be AllAllowed, FtpsOnly, or Disabled."
  }
}

variable "web_app_https_only" {
  description = "Enforce HTTPS only for the web app"
  type        = bool
  default     = true
}

# Auto-scaling Variables
variable "autoscale_enabled" {
  description = "Enable auto-scaling for the App Service Plan"
  type        = bool
  default     = true
}

variable "autoscale_min_instances" {
  description = "Minimum number of instances for auto-scaling"
  type        = number
  default     = 1
  
  validation {
    condition     = var.autoscale_min_instances >= 1 && var.autoscale_min_instances <= 10
    error_message = "Minimum instances must be between 1 and 10."
  }
}

variable "autoscale_max_instances" {
  description = "Maximum number of instances for auto-scaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.autoscale_max_instances >= 1 && var.autoscale_max_instances <= 30
    error_message = "Maximum instances must be between 1 and 30."
  }
}

variable "autoscale_default_instances" {
  description = "Default number of instances for auto-scaling"
  type        = number
  default     = 2
  
  validation {
    condition     = var.autoscale_default_instances >= 1 && var.autoscale_default_instances <= 10
    error_message = "Default instances must be between 1 and 10."
  }
}

variable "autoscale_cpu_threshold_out" {
  description = "CPU threshold for scaling out (percentage)"
  type        = number
  default     = 70
  
  validation {
    condition     = var.autoscale_cpu_threshold_out >= 10 && var.autoscale_cpu_threshold_out <= 90
    error_message = "CPU threshold for scaling out must be between 10 and 90."
  }
}

variable "autoscale_cpu_threshold_in" {
  description = "CPU threshold for scaling in (percentage)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.autoscale_cpu_threshold_in >= 10 && var.autoscale_cpu_threshold_in <= 80
    error_message = "CPU threshold for scaling in must be between 10 and 80."
  }
}

# Application Insights Variables
variable "application_insights_type" {
  description = "Type of Application Insights instance"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "ios", "java", "other"], var.application_insights_type)
    error_message = "Application Insights type must be web, ios, java, or other."
  }
}

variable "application_insights_sampling_percentage" {
  description = "Sampling percentage for Application Insights"
  type        = number
  default     = 100
  
  validation {
    condition     = var.application_insights_sampling_percentage >= 0 && var.application_insights_sampling_percentage <= 100
    error_message = "Sampling percentage must be between 0 and 100."
  }
}

# Container Application Variables
variable "container_image_name" {
  description = "Name of the container image"
  type        = string
  default     = "video-conferencing-app"
}

variable "container_image_tag" {
  description = "Tag of the container image"
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 3000
  
  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "Container port must be between 1 and 65535."
  }
}

# Node.js Application Variables
variable "node_env" {
  description = "Node.js environment"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.node_env)
    error_message = "Node environment must be development, staging, or production."
  }
}

# Logging Variables
variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
  }
}

# Tagging Variables
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "video-conferencing"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Security Variables
variable "enable_private_endpoint" {
  description = "Enable private endpoints for supported services"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access the web app"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Backup Variables
variable "enable_backup" {
  description = "Enable backup for the web app"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 30
    error_message = "Backup retention days must be between 1 and 30."
  }
}