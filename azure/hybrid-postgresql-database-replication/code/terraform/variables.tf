# Variables for Azure Hybrid PostgreSQL Database Replication Infrastructure
# This file defines all the configurable parameters for the infrastructure deployment

# Basic Configuration
variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9-._]{1,90}$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters long and can contain alphanumeric characters, hyphens, periods, and underscores."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", "Central US", "South Central US",
      "North Central US", "West Central US", "Canada Central", "Canada East", "North Europe", 
      "West Europe", "UK South", "UK West", "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central", "Australia East", "Australia Southeast", "Brazil South",
      "Southeast Asia", "East Asia", "Japan East", "Japan West", "Korea Central", "South India",
      "Central India", "West India", "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
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
  default     = "hybrid-postgres"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

# Azure Arc Configuration
variable "arc_data_controller_name" {
  description = "Name of the Azure Arc Data Controller"
  type        = string
  default     = "arc-dc-postgres"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.arc_data_controller_name))
    error_message = "Arc Data Controller name must be 3-63 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "arc_postgres_name" {
  description = "Name of the Arc-enabled PostgreSQL instance"
  type        = string
  default     = "postgres-hybrid"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.arc_postgres_name))
    error_message = "Arc PostgreSQL name must be 3-63 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "kubernetes_namespace" {
  description = "Kubernetes namespace for Arc data services"
  type        = string
  default     = "arc-data"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{1,63}$", var.kubernetes_namespace))
    error_message = "Kubernetes namespace must be 1-63 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "arc_connectivity_mode" {
  description = "Arc connectivity mode (indirect or direct)"
  type        = string
  default     = "indirect"
  
  validation {
    condition     = contains(["indirect", "direct"], var.arc_connectivity_mode)
    error_message = "Arc connectivity mode must be either 'indirect' or 'direct'."
  }
}

# PostgreSQL Configuration
variable "postgresql_admin_username" {
  description = "Administrator username for PostgreSQL servers"
  type        = string
  default     = "pgadmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{1,63}$", var.postgresql_admin_username))
    error_message = "PostgreSQL admin username must start with a letter and be 2-64 characters long."
  }
}

variable "postgresql_admin_password" {
  description = "Administrator password for PostgreSQL servers"
  type        = string
  sensitive   = true
  
  validation {
    condition     = can(regex("^.{8,128}$", var.postgresql_admin_password))
    error_message = "PostgreSQL admin password must be 8-128 characters long."
  }
}

variable "postgresql_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "14"
  
  validation {
    condition     = contains(["11", "12", "13", "14", "15"], var.postgresql_version)
    error_message = "PostgreSQL version must be one of: 11, 12, 13, 14, 15."
  }
}

variable "azure_postgresql_sku" {
  description = "SKU for Azure Database for PostgreSQL Flexible Server"
  type        = string
  default     = "Standard_D2ds_v4"
  
  validation {
    condition = contains([
      "Standard_B1ms", "Standard_B2s", "Standard_B2ms", "Standard_B4ms", "Standard_B8ms", "Standard_B12ms", "Standard_B16ms", "Standard_B20ms",
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3", "Standard_D16s_v3", "Standard_D32s_v3", "Standard_D48s_v3", "Standard_D64s_v3",
      "Standard_D2ds_v4", "Standard_D4ds_v4", "Standard_D8ds_v4", "Standard_D16ds_v4", "Standard_D32ds_v4", "Standard_D48ds_v4", "Standard_D64ds_v4",
      "Standard_E2s_v3", "Standard_E4s_v3", "Standard_E8s_v3", "Standard_E16s_v3", "Standard_E32s_v3", "Standard_E48s_v3", "Standard_E64s_v3"
    ], var.azure_postgresql_sku)
    error_message = "Azure PostgreSQL SKU must be a valid Flexible Server SKU."
  }
}

variable "azure_postgresql_storage_mb" {
  description = "Storage size in MB for Azure Database for PostgreSQL"
  type        = number
  default     = 131072
  
  validation {
    condition     = var.azure_postgresql_storage_mb >= 32768 && var.azure_postgresql_storage_mb <= 16777216
    error_message = "Azure PostgreSQL storage must be between 32GB (32768 MB) and 16TB (16777216 MB)."
  }
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "Backup retention days must be between 7 and 35."
  }
}

variable "high_availability_enabled" {
  description = "Enable high availability for Azure PostgreSQL"
  type        = bool
  default     = false
}

# Arc PostgreSQL Resource Configuration
variable "arc_postgres_cpu_requests" {
  description = "CPU requests for Arc PostgreSQL (in cores)"
  type        = string
  default     = "2"
  
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?$", var.arc_postgres_cpu_requests))
    error_message = "CPU requests must be a valid number (e.g., '2' or '2.5')."
  }
}

variable "arc_postgres_cpu_limits" {
  description = "CPU limits for Arc PostgreSQL (in cores)"
  type        = string
  default     = "4"
  
  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?$", var.arc_postgres_cpu_limits))
    error_message = "CPU limits must be a valid number (e.g., '4' or '4.5')."
  }
}

variable "arc_postgres_memory_requests" {
  description = "Memory requests for Arc PostgreSQL"
  type        = string
  default     = "4Gi"
  
  validation {
    condition     = can(regex("^[0-9]+([KMGT]i?)?$", var.arc_postgres_memory_requests))
    error_message = "Memory requests must be a valid Kubernetes resource quantity (e.g., '4Gi', '8192Mi')."
  }
}

variable "arc_postgres_memory_limits" {
  description = "Memory limits for Arc PostgreSQL"
  type        = string
  default     = "8Gi"
  
  validation {
    condition     = can(regex("^[0-9]+([KMGT]i?)?$", var.arc_postgres_memory_limits))
    error_message = "Memory limits must be a valid Kubernetes resource quantity (e.g., '8Gi', '16384Mi')."
  }
}

variable "arc_postgres_storage_size" {
  description = "Storage size for Arc PostgreSQL data"
  type        = string
  default     = "50Gi"
  
  validation {
    condition     = can(regex("^[0-9]+([KMGT]i?)?$", var.arc_postgres_storage_size))
    error_message = "Storage size must be a valid Kubernetes resource quantity (e.g., '50Gi', '100Gi')."
  }
}

variable "arc_postgres_logs_storage_size" {
  description = "Storage size for Arc PostgreSQL logs"
  type        = string
  default     = "10Gi"
  
  validation {
    condition     = can(regex("^[0-9]+([KMGT]i?)?$", var.arc_postgres_logs_storage_size))
    error_message = "Logs storage size must be a valid Kubernetes resource quantity (e.g., '10Gi', '20Gi')."
  }
}

variable "arc_postgres_replicas" {
  description = "Number of replicas for Arc PostgreSQL"
  type        = number
  default     = 1
  
  validation {
    condition     = var.arc_postgres_replicas >= 1 && var.arc_postgres_replicas <= 5
    error_message = "Number of replicas must be between 1 and 5."
  }
}

# Event Grid Configuration
variable "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  type        = string
  default     = null
  
  validation {
    condition     = var.event_grid_topic_name == null || can(regex("^[a-zA-Z0-9-]{3,50}$", var.event_grid_topic_name))
    error_message = "Event Grid topic name must be 3-50 characters long and contain only letters, numbers, and hyphens."
  }
}

variable "event_grid_sku" {
  description = "SKU for Event Grid topic"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Premium"], var.event_grid_sku)
    error_message = "Event Grid SKU must be either 'Basic' or 'Premium'."
  }
}

# Data Factory Configuration
variable "data_factory_name" {
  description = "Name of the Azure Data Factory"
  type        = string
  default     = null
  
  validation {
    condition     = var.data_factory_name == null || can(regex("^[a-zA-Z0-9-]{3,63}$", var.data_factory_name))
    error_message = "Data Factory name must be 3-63 characters long and contain only letters, numbers, and hyphens."
  }
}

variable "data_factory_public_network_enabled" {
  description = "Enable public network access for Data Factory"
  type        = bool
  default     = true
}

variable "data_factory_managed_virtual_network_enabled" {
  description = "Enable managed virtual network for Data Factory"
  type        = bool
  default     = false
}

# Key Vault Configuration
variable "key_vault_name" {
  description = "Name of the Azure Key Vault"
  type        = string
  default     = null
  
  validation {
    condition     = var.key_vault_name == null || can(regex("^[a-zA-Z0-9-]{3,24}$", var.key_vault_name))
    error_message = "Key Vault name must be 3-24 characters long and contain only letters, numbers, and hyphens."
  }
}

variable "key_vault_sku" {
  description = "SKU for Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "key_vault_enabled_for_disk_encryption" {
  description = "Enable Key Vault for disk encryption"
  type        = bool
  default     = true
}

variable "key_vault_enabled_for_template_deployment" {
  description = "Enable Key Vault for template deployment"
  type        = bool
  default     = true
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection for Key Vault"
  type        = bool
  default     = false
}

# Log Analytics Configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = null
  
  validation {
    condition     = var.log_analytics_workspace_name == null || can(regex("^[a-zA-Z0-9-]{4,63}$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must be 4-63 characters long and contain only letters, numbers, and hyphens."
  }
}

variable "log_analytics_retention_days" {
  description = "Retention period for Log Analytics workspace in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 7 and 730."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerGB2018", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid pricing tier."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Azure Monitor and Application Insights"
  type        = bool
  default     = true
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for resources"
  type        = bool
  default     = true
}

variable "enable_metrics" {
  description = "Enable metrics collection"
  type        = bool
  default     = true
}

# Network Configuration
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access PostgreSQL servers"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([
      for ip_range in var.allowed_ip_ranges :
      can(regex("^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\\/([0-9]|[1-2][0-9]|3[0-2]))?$", ip_range))
    ])
    error_message = "All IP ranges must be valid CIDR notation (e.g., '10.0.0.0/8', '192.168.1.0/24')."
  }
}

# Tags Configuration
variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default = {
    Purpose     = "Hybrid PostgreSQL Replication"
    Environment = "Demo"
    Project     = "Infrastructure Recipe"
  }
}

# Advanced Configuration
variable "replication_lag_threshold_seconds" {
  description = "Threshold for replication lag alerts in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.replication_lag_threshold_seconds >= 60 && var.replication_lag_threshold_seconds <= 3600
    error_message = "Replication lag threshold must be between 60 and 3600 seconds."
  }
}

variable "pipeline_schedule" {
  description = "Schedule for the replication pipeline (cron format)"
  type        = string
  default     = "0 */5 * * * *"
  
  validation {
    condition     = can(regex("^[0-5]?[0-9]\\s+([0-5]?[0-9]|\\*)\\s+(\\*|[0-1]?[0-9]|2[0-3])\\s+(\\*|[1-2]?[0-9]|3[0-1])\\s+(\\*|[1-9]|1[0-2])\\s+(\\*|[0-6])$", var.pipeline_schedule))
    error_message = "Pipeline schedule must be a valid cron expression."
  }
}

variable "enable_backup" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "enable_ssl" {
  description = "Enforce SSL connection for PostgreSQL"
  type        = bool
  default     = true
}

variable "enable_firewall_rules" {
  description = "Enable firewall rules for PostgreSQL servers"
  type        = bool
  default     = true
}

variable "create_service_principal" {
  description = "Create a service principal for Arc Data Controller"
  type        = bool
  default     = true
}

variable "kubernetes_storage_class" {
  description = "Storage class for Kubernetes volumes"
  type        = string
  default     = "default"
}