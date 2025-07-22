# Common variables
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-arc-data-services"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US",
      "UK South", "UK West", "West Europe", "North Europe",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast"
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

# Kubernetes cluster variables
variable "kubernetes_cluster_name" {
  description = "Name of the existing Kubernetes cluster"
  type        = string
  default     = ""
}

variable "kubernetes_cluster_resource_group" {
  description = "Resource group containing the Kubernetes cluster"
  type        = string
  default     = ""
}

variable "create_aks_cluster" {
  description = "Whether to create a new AKS cluster or use existing"
  type        = bool
  default     = true
}

variable "aks_node_count" {
  description = "Number of nodes in the AKS cluster"
  type        = number
  default     = 3
  
  validation {
    condition     = var.aks_node_count >= 1 && var.aks_node_count <= 10
    error_message = "Node count must be between 1 and 10."
  }
}

variable "aks_node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_DS2_v2"
}

variable "aks_kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.27.7"
}

# Azure Arc Data Services variables
variable "arc_data_controller_name" {
  description = "Name of the Azure Arc Data Controller"
  type        = string
  default     = "arc-dc-controller"
}

variable "arc_data_controller_namespace" {
  description = "Kubernetes namespace for Arc Data Controller"
  type        = string
  default     = "arc"
}

variable "arc_connectivity_mode" {
  description = "Connectivity mode for Arc Data Controller"
  type        = string
  default     = "direct"
  
  validation {
    condition     = contains(["direct", "indirect"], var.arc_connectivity_mode)
    error_message = "Connectivity mode must be either 'direct' or 'indirect'."
  }
}

# SQL Managed Instance variables
variable "sql_mi_name" {
  description = "Name of the SQL Managed Instance"
  type        = string
  default     = "sql-mi-arc"
}

variable "sql_mi_cores_request" {
  description = "CPU cores request for SQL MI"
  type        = number
  default     = 2
  
  validation {
    condition     = var.sql_mi_cores_request >= 1 && var.sql_mi_cores_request <= 8
    error_message = "CPU cores request must be between 1 and 8."
  }
}

variable "sql_mi_cores_limit" {
  description = "CPU cores limit for SQL MI"
  type        = number
  default     = 4
  
  validation {
    condition     = var.sql_mi_cores_limit >= 1 && var.sql_mi_cores_limit <= 16
    error_message = "CPU cores limit must be between 1 and 16."
  }
}

variable "sql_mi_memory_request" {
  description = "Memory request for SQL MI"
  type        = string
  default     = "2Gi"
}

variable "sql_mi_memory_limit" {
  description = "Memory limit for SQL MI"
  type        = string
  default     = "4Gi"
}

variable "sql_mi_storage_class" {
  description = "Storage class for SQL MI"
  type        = string
  default     = "default"
}

variable "sql_mi_data_volume_size" {
  description = "Data volume size for SQL MI"
  type        = string
  default     = "5Gi"
}

variable "sql_mi_logs_volume_size" {
  description = "Logs volume size for SQL MI"
  type        = string
  default     = "5Gi"
}

variable "sql_mi_service_tier" {
  description = "Service tier for SQL MI"
  type        = string
  default     = "GeneralPurpose"
  
  validation {
    condition     = contains(["GeneralPurpose", "BusinessCritical"], var.sql_mi_service_tier)
    error_message = "Service tier must be either 'GeneralPurpose' or 'BusinessCritical'."
  }
}

variable "sql_mi_admin_username" {
  description = "Admin username for SQL MI"
  type        = string
  default     = "arcadmin"
  sensitive   = true
}

variable "sql_mi_admin_password" {
  description = "Admin password for SQL MI"
  type        = string
  default     = ""
  sensitive   = true
  
  validation {
    condition     = length(var.sql_mi_admin_password) >= 8
    error_message = "Password must be at least 8 characters long."
  }
}

# Log Analytics variables
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = "law-arc-monitoring"
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.log_analytics_sku)
    error_message = "SKU must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

variable "log_analytics_retention_days" {
  description = "Retention period in days for Log Analytics"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Retention days must be between 7 and 730."
  }
}

# Monitoring and alerting variables
variable "enable_monitoring" {
  description = "Enable Azure Monitor integration"
  type        = bool
  default     = true
}

variable "enable_alerting" {
  description = "Enable monitoring alerts"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = "admin@company.com"
}

variable "cpu_alert_threshold" {
  description = "CPU utilization threshold for alerts (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cpu_alert_threshold >= 1 && var.cpu_alert_threshold <= 100
    error_message = "CPU alert threshold must be between 1 and 100."
  }
}

variable "storage_alert_threshold" {
  description = "Storage utilization threshold for alerts (percentage)"
  type        = number
  default     = 85
  
  validation {
    condition     = var.storage_alert_threshold >= 1 && var.storage_alert_threshold <= 100
    error_message = "Storage alert threshold must be between 1 and 100."
  }
}

# Security and governance variables
variable "enable_azure_policy" {
  description = "Enable Azure Policy for governance"
  type        = bool
  default     = true
}

variable "enable_rbac" {
  description = "Enable Role-Based Access Control"
  type        = bool
  default     = true
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Purpose     = "arc-data-services"
    ManagedBy   = "terraform"
  }
}