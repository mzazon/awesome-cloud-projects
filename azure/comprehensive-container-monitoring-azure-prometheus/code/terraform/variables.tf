# Variables for Azure Stateful Workload Monitoring Infrastructure
# This file defines all configurable variables for the monitoring solution

# Basic Configuration Variables
variable "location" {
  description = "The Azure region where all resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "The location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]{1,10}$", var.environment))
    error_message = "Environment must be alphanumeric with hyphens, max 10 characters."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "stateful-monitoring"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]{1,20}$", var.project_name))
    error_message = "Project name must be alphanumeric with hyphens, max 20 characters."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group (optional, will be generated if not provided)"
  type        = string
  default     = ""
}

# Container Apps Configuration
variable "container_app_environment_name" {
  description = "Name of the Container Apps environment"
  type        = string
  default     = ""
}

variable "container_app_name" {
  description = "Name of the main container application"
  type        = string
  default     = ""
}

variable "container_app_image" {
  description = "Container image for the stateful application"
  type        = string
  default     = "postgres:14"
}

variable "container_app_cpu" {
  description = "CPU allocation for the container app"
  type        = number
  default     = 1.0
  
  validation {
    condition = var.container_app_cpu >= 0.25 && var.container_app_cpu <= 4.0
    error_message = "CPU allocation must be between 0.25 and 4.0 cores."
  }
}

variable "container_app_memory" {
  description = "Memory allocation for the container app in Gi"
  type        = string
  default     = "2.0Gi"
  
  validation {
    condition = can(regex("^[0-9]+(\\.[0-9]+)?Gi$", var.container_app_memory))
    error_message = "Memory must be specified in Gi format (e.g., 2.0Gi)."
  }
}

variable "container_app_min_replicas" {
  description = "Minimum number of container replicas"
  type        = number
  default     = 1
  
  validation {
    condition = var.container_app_min_replicas >= 0 && var.container_app_min_replicas <= 10
    error_message = "Minimum replicas must be between 0 and 10."
  }
}

variable "container_app_max_replicas" {
  description = "Maximum number of container replicas"
  type        = number
  default     = 3
  
  validation {
    condition = var.container_app_max_replicas >= 1 && var.container_app_max_replicas <= 25
    error_message = "Maximum replicas must be between 1 and 25."
  }
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Premium"
  
  validation {
    condition = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Invalid storage replication type."
  }
}

variable "storage_share_quota" {
  description = "Storage share quota in GB"
  type        = number
  default     = 100
  
  validation {
    condition = var.storage_share_quota >= 1 && var.storage_share_quota <= 102400
    error_message = "Storage share quota must be between 1 and 102400 GB."
  }
}

# Monitoring Configuration
variable "monitor_workspace_name" {
  description = "Name of the Azure Monitor workspace"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = ""
}

variable "log_analytics_retention_days" {
  description = "Log Analytics workspace retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 7 and 730 days."
  }
}

variable "grafana_instance_name" {
  description = "Name of the Azure Managed Grafana instance"
  type        = string
  default     = ""
}

variable "grafana_sku" {
  description = "SKU for Azure Managed Grafana"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Essential", "Standard"], var.grafana_sku)
    error_message = "Grafana SKU must be either Essential or Standard."
  }
}

# Database Configuration
variable "postgres_database_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "sampledb"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.postgres_database_name))
    error_message = "Database name must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "postgres_username" {
  description = "PostgreSQL username"
  type        = string
  default     = "sampleuser"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.postgres_username))
    error_message = "Username must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  default     = "samplepass123"
  sensitive   = true
  
  validation {
    condition = length(var.postgres_password) >= 8
    error_message = "Password must be at least 8 characters long."
  }
}

# Monitoring Sidecar Configuration
variable "enable_monitoring_sidecar" {
  description = "Enable monitoring sidecar container"
  type        = bool
  default     = true
}

variable "monitoring_sidecar_image" {
  description = "Monitoring sidecar container image"
  type        = string
  default     = "prom/node-exporter:latest"
}

variable "monitoring_sidecar_cpu" {
  description = "CPU allocation for monitoring sidecar"
  type        = number
  default     = 0.25
  
  validation {
    condition = var.monitoring_sidecar_cpu >= 0.25 && var.monitoring_sidecar_cpu <= 2.0
    error_message = "Monitoring sidecar CPU must be between 0.25 and 2.0 cores."
  }
}

variable "monitoring_sidecar_memory" {
  description = "Memory allocation for monitoring sidecar"
  type        = string
  default     = "0.5Gi"
  
  validation {
    condition = can(regex("^[0-9]+(\\.[0-9]+)?Gi$", var.monitoring_sidecar_memory))
    error_message = "Memory must be specified in Gi format (e.g., 0.5Gi)."
  }
}

# Alerting Configuration
variable "enable_alerts" {
  description = "Enable monitoring alerts"
  type        = bool
  default     = true
}

variable "cpu_threshold_percent" {
  description = "CPU usage threshold for alerts (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition = var.cpu_threshold_percent >= 50 && var.cpu_threshold_percent <= 95
    error_message = "CPU threshold must be between 50 and 95 percent."
  }
}

variable "memory_threshold_percent" {
  description = "Memory usage threshold for alerts (percentage)"
  type        = number
  default     = 85
  
  validation {
    condition = var.memory_threshold_percent >= 50 && var.memory_threshold_percent <= 95
    error_message = "Memory threshold must be between 50 and 95 percent."
  }
}

variable "storage_threshold_percent" {
  description = "Storage utilization threshold for alerts (percentage)"
  type        = number
  default     = 85
  
  validation {
    condition = var.storage_threshold_percent >= 50 && var.storage_threshold_percent <= 95
    error_message = "Storage threshold must be between 50 and 95 percent."
  }
}

variable "alert_evaluation_frequency" {
  description = "Alert evaluation frequency"
  type        = string
  default     = "PT5M"
  
  validation {
    condition = can(regex("^PT[0-9]+M$", var.alert_evaluation_frequency))
    error_message = "Evaluation frequency must be in PT format (e.g., PT5M for 5 minutes)."
  }
}

variable "alert_window_size" {
  description = "Alert window size for evaluation"
  type        = string
  default     = "PT15M"
  
  validation {
    condition = can(regex("^PT[0-9]+M$", var.alert_window_size))
    error_message = "Window size must be in PT format (e.g., PT15M for 15 minutes)."
  }
}

# Networking Configuration
variable "enable_vnet_integration" {
  description = "Enable virtual network integration"
  type        = bool
  default     = true
}

variable "vnet_address_space" {
  description = "Virtual network address space"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition = length(var.vnet_address_space) > 0
    error_message = "At least one address space must be specified."
  }
}

variable "container_subnet_address_prefix" {
  description = "Container subnet address prefix"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition = can(cidrhost(var.container_subnet_address_prefix, 0))
    error_message = "Container subnet address prefix must be a valid CIDR block."
  }
}

# Security Configuration
variable "enable_https_only" {
  description = "Enable HTTPS only for storage account"
  type        = bool
  default     = true
}

variable "enable_blob_public_access" {
  description = "Enable public access to blobs"
  type        = bool
  default     = false
}

variable "enable_storage_firewall" {
  description = "Enable storage account firewall"
  type        = bool
  default     = true
}

# Tagging Configuration
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "StatefulWorkloadMonitoring"
    Environment = "Demo"
    ManagedBy   = "Terraform"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}