# Variables for Azure Elastic SAN and VMSS Database Infrastructure
# This file defines all configurable parameters for the infrastructure deployment

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-elastic-san-demo"
}

variable "location" {
  description = "Azure region where resources will be deployed"
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
  description = "Name of the project for resource naming"
  type        = string
  default     = "elastic-san-db"
}

# Network Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for the database subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

# Elastic SAN Configuration
variable "elastic_san_base_size_tib" {
  description = "Base size of Elastic SAN in TiB"
  type        = number
  default     = 1
  
  validation {
    condition     = var.elastic_san_base_size_tib >= 1 && var.elastic_san_base_size_tib <= 100
    error_message = "Elastic SAN base size must be between 1 and 100 TiB."
  }
}

variable "elastic_san_extended_capacity_tib" {
  description = "Extended capacity of Elastic SAN in TiB"
  type        = number
  default     = 2
  
  validation {
    condition     = var.elastic_san_extended_capacity_tib >= 0 && var.elastic_san_extended_capacity_tib <= 400
    error_message = "Elastic SAN extended capacity must be between 0 and 400 TiB."
  }
}

variable "elastic_san_sku" {
  description = "SKU for Elastic SAN"
  type        = string
  default     = "Premium_LRS"
  
  validation {
    condition     = contains(["Premium_LRS", "Premium_ZRS"], var.elastic_san_sku)
    error_message = "Elastic SAN SKU must be either Premium_LRS or Premium_ZRS."
  }
}

# Storage Volume Configuration
variable "data_volume_size_gb" {
  description = "Size of the PostgreSQL data volume in GB"
  type        = number
  default     = 500
  
  validation {
    condition     = var.data_volume_size_gb >= 100 && var.data_volume_size_gb <= 10000
    error_message = "Data volume size must be between 100 and 10000 GB."
  }
}

variable "log_volume_size_gb" {
  description = "Size of the PostgreSQL log volume in GB"
  type        = number
  default     = 200
  
  validation {
    condition     = var.log_volume_size_gb >= 50 && var.log_volume_size_gb <= 5000
    error_message = "Log volume size must be between 50 and 5000 GB."
  }
}

# Virtual Machine Scale Set Configuration
variable "vmss_sku" {
  description = "SKU for Virtual Machine Scale Set instances"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "vmss_instances" {
  description = "Number of instances in the Virtual Machine Scale Set"
  type        = number
  default     = 2
  
  validation {
    condition     = var.vmss_instances >= 1 && var.vmss_instances <= 20
    error_message = "VMSS instances must be between 1 and 20."
  }
}

variable "vmss_upgrade_policy" {
  description = "Upgrade policy for Virtual Machine Scale Set"
  type        = string
  default     = "Manual"
  
  validation {
    condition     = contains(["Manual", "Automatic", "Rolling"], var.vmss_upgrade_policy)
    error_message = "VMSS upgrade policy must be Manual, Automatic, or Rolling."
  }
}

variable "admin_username" {
  description = "Admin username for VM instances"
  type        = string
  default     = "azureuser"
}

variable "disable_password_authentication" {
  description = "Disable password authentication for VM instances"
  type        = bool
  default     = true
}

# Auto-scaling Configuration
variable "autoscale_minimum_instances" {
  description = "Minimum number of instances for auto-scaling"
  type        = number
  default     = 2
  
  validation {
    condition     = var.autoscale_minimum_instances >= 1 && var.autoscale_minimum_instances <= 10
    error_message = "Minimum instances must be between 1 and 10."
  }
}

variable "autoscale_maximum_instances" {
  description = "Maximum number of instances for auto-scaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.autoscale_maximum_instances >= 2 && var.autoscale_maximum_instances <= 100
    error_message = "Maximum instances must be between 2 and 100."
  }
}

variable "autoscale_default_instances" {
  description = "Default number of instances for auto-scaling"
  type        = number
  default     = 2
}

variable "cpu_scale_out_threshold" {
  description = "CPU threshold for scaling out (percentage)"
  type        = number
  default     = 70
  
  validation {
    condition     = var.cpu_scale_out_threshold >= 50 && var.cpu_scale_out_threshold <= 95
    error_message = "CPU scale out threshold must be between 50 and 95."
  }
}

variable "cpu_scale_in_threshold" {
  description = "CPU threshold for scaling in (percentage)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.cpu_scale_in_threshold >= 10 && var.cpu_scale_in_threshold <= 50
    error_message = "CPU scale in threshold must be between 10 and 50."
  }
}

# PostgreSQL Configuration
variable "postgresql_administrator_login" {
  description = "Administrator login for PostgreSQL Flexible Server"
  type        = string
  default     = "pgadmin"
}

variable "postgresql_administrator_password" {
  description = "Administrator password for PostgreSQL Flexible Server"
  type        = string
  sensitive   = true
  default     = "SecurePassword123!"
  
  validation {
    condition     = length(var.postgresql_administrator_password) >= 8
    error_message = "PostgreSQL administrator password must be at least 8 characters long."
  }
}

variable "postgresql_sku_name" {
  description = "SKU name for PostgreSQL Flexible Server"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "postgresql_storage_mb" {
  description = "Storage size for PostgreSQL Flexible Server in MB"
  type        = number
  default     = 131072  # 128 GB
  
  validation {
    condition     = var.postgresql_storage_mb >= 32768 && var.postgresql_storage_mb <= 33554432
    error_message = "PostgreSQL storage must be between 32 GB and 32 TB."
  }
}

variable "postgresql_storage_tier" {
  description = "Storage tier for PostgreSQL Flexible Server"
  type        = string
  default     = "P30"
}

variable "postgresql_version" {
  description = "Version of PostgreSQL"
  type        = string
  default     = "14"
  
  validation {
    condition     = contains(["11", "12", "13", "14", "15"], var.postgresql_version)
    error_message = "PostgreSQL version must be 11, 12, 13, 14, or 15."
  }
}

variable "postgresql_high_availability" {
  description = "Enable high availability for PostgreSQL"
  type        = bool
  default     = true
}

variable "postgresql_zone" {
  description = "Availability zone for PostgreSQL primary server"
  type        = string
  default     = "1"
}

variable "postgresql_standby_zone" {
  description = "Availability zone for PostgreSQL standby server"
  type        = string
  default     = "2"
}

# Load Balancer Configuration
variable "load_balancer_sku" {
  description = "SKU for Azure Load Balancer"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard"], var.load_balancer_sku)
    error_message = "Load balancer SKU must be Basic or Standard."
  }
}

# Monitoring Configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be Free, PerNode, PerGB2018, or Premium."
  }
}

variable "log_analytics_retention_days" {
  description = "Retention period for Log Analytics workspace in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 2555
    error_message = "Log Analytics retention must be between 7 and 2555 days."
  }
}

# Alert Configuration
variable "alert_email_addresses" {
  description = "Email addresses for alert notifications"
  type        = list(string)
  default     = []
}

variable "cpu_alert_threshold" {
  description = "CPU threshold for alerts (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cpu_alert_threshold >= 50 && var.cpu_alert_threshold <= 95
    error_message = "CPU alert threshold must be between 50 and 95."
  }
}

# Tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "demo"
    environment = "elastic-san-demo"
    workload    = "database"
    performance = "high"
  }
}