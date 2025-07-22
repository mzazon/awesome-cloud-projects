# Variables for MLOps Pipeline with AKS and Azure Machine Learning
# This file defines all configurable parameters for the infrastructure deployment

# Resource naming and location variables
variable "resource_group_name" {
  description = "Name of the resource group to create"
  type        = string
  default     = "rg-mlops-pipeline"
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US",
      "North Europe", "West Europe", "UK South", "UK West",
      "Southeast Asia", "East Asia", "Japan East", "Japan West",
      "Australia East", "Australia Southeast"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^(dev|test|staging|prod|demo)$", var.environment))
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

# Azure Machine Learning Workspace variables
variable "ml_workspace_name" {
  description = "Name of the Azure Machine Learning workspace"
  type        = string
  default     = "mlw-mlops-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{2,32}$", var.ml_workspace_name))
    error_message = "ML workspace name must be 3-33 characters, start with alphanumeric, and contain only letters, numbers, hyphens, and underscores."
  }
}

# Storage account variables
variable "storage_account_prefix" {
  description = "Prefix for storage account names (will be appended with random suffix)"
  type        = string
  default     = "stmlops"
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,11}$", var.storage_account_prefix))
    error_message = "Storage account prefix must be 3-11 characters, lowercase letters and numbers only."
  }
}

# Azure Container Registry variables
variable "acr_name_prefix" {
  description = "Prefix for Azure Container Registry name (will be appended with random suffix)"
  type        = string
  default     = "acrmlops"
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,11}$", var.acr_name_prefix))
    error_message = "ACR name prefix must be 3-11 characters, lowercase letters and numbers only."
  }
}

variable "acr_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "ACR SKU must be Basic, Standard, or Premium."
  }
}

# Key Vault variables
variable "key_vault_name_prefix" {
  description = "Prefix for Key Vault name (will be appended with random suffix)"
  type        = string
  default     = "kv-mlops"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,11}$", var.key_vault_name_prefix))
    error_message = "Key Vault name prefix must be 2-12 characters, start with letter, and contain only letters, numbers, and hyphens."
  }
}

# Application Insights variables
variable "app_insights_name_prefix" {
  description = "Prefix for Application Insights name"
  type        = string
  default     = "mlops-insights"
}

# Log Analytics variables
variable "log_analytics_name_prefix" {
  description = "Prefix for Log Analytics workspace name"
  type        = string
  default     = "mlops-logs"
}

# Azure Kubernetes Service variables
variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-mlops-cluster"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,62}$", var.aks_cluster_name))
    error_message = "AKS cluster name must be 1-63 characters, start with alphanumeric, and contain only letters, numbers, hyphens, and underscores."
  }
}

# AKS System Node Pool variables
variable "aks_system_node_count" {
  description = "Initial number of nodes in the system node pool"
  type        = number
  default     = 2
  
  validation {
    condition     = var.aks_system_node_count >= 1 && var.aks_system_node_count <= 10
    error_message = "System node count must be between 1 and 10."
  }
}

variable "aks_system_min_nodes" {
  description = "Minimum number of nodes in the system node pool"
  type        = number
  default     = 2
  
  validation {
    condition     = var.aks_system_min_nodes >= 1 && var.aks_system_min_nodes <= 10
    error_message = "System minimum nodes must be between 1 and 10."
  }
}

variable "aks_system_max_nodes" {
  description = "Maximum number of nodes in the system node pool"
  type        = number
  default     = 5
  
  validation {
    condition     = var.aks_system_max_nodes >= 2 && var.aks_system_max_nodes <= 20
    error_message = "System maximum nodes must be between 2 and 20."
  }
}

variable "aks_system_vm_size" {
  description = "VM size for system node pool"
  type        = string
  default     = "Standard_DS3_v2"
  
  validation {
    condition = contains([
      "Standard_DS2_v2", "Standard_DS3_v2", "Standard_DS4_v2",
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3",
      "Standard_B2s", "Standard_B4ms", "Standard_B8ms"
    ], var.aks_system_vm_size)
    error_message = "System VM size must be a valid Azure VM size suitable for AKS."
  }
}

# AKS ML Node Pool variables
variable "aks_ml_node_count" {
  description = "Initial number of nodes in the ML node pool"
  type        = number
  default     = 2
  
  validation {
    condition     = var.aks_ml_node_count >= 1 && var.aks_ml_node_count <= 10
    error_message = "ML node count must be between 1 and 10."
  }
}

variable "aks_ml_min_nodes" {
  description = "Minimum number of nodes in the ML node pool"
  type        = number
  default     = 1
  
  validation {
    condition     = var.aks_ml_min_nodes >= 1 && var.aks_ml_min_nodes <= 10
    error_message = "ML minimum nodes must be between 1 and 10."
  }
}

variable "aks_ml_max_nodes" {
  description = "Maximum number of nodes in the ML node pool"
  type        = number
  default     = 4
  
  validation {
    condition     = var.aks_ml_max_nodes >= 2 && var.aks_ml_max_nodes <= 20
    error_message = "ML maximum nodes must be between 2 and 20."
  }
}

variable "aks_ml_vm_size" {
  description = "VM size for ML node pool"
  type        = string
  default     = "Standard_DS3_v2"
  
  validation {
    condition = contains([
      "Standard_DS2_v2", "Standard_DS3_v2", "Standard_DS4_v2",
      "Standard_D2s_v3", "Standard_D4s_v3", "Standard_D8s_v3",
      "Standard_NC6s_v3", "Standard_NC12s_v3", "Standard_NC24s_v3",
      "Standard_ND40rs_v2"
    ], var.aks_ml_vm_size)
    error_message = "ML VM size must be a valid Azure VM size suitable for ML workloads."
  }
}

# Monitoring and alerting variables
variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address."
  }
}

# Optional variables for advanced configurations
variable "enable_private_cluster" {
  description = "Enable private AKS cluster"
  type        = bool
  default     = false
}

variable "enable_azure_policy" {
  description = "Enable Azure Policy for AKS"
  type        = bool
  default     = false
}

variable "enable_network_policy" {
  description = "Enable network policy for AKS"
  type        = bool
  default     = false
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = null
  
  validation {
    condition     = var.kubernetes_version == null || can(regex("^1\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Kubernetes version must be in format '1.x.x' or null for default."
  }
}

# Cost optimization variables
variable "enable_spot_instances" {
  description = "Enable spot instances for ML node pool"
  type        = bool
  default     = false
}

variable "spot_max_price" {
  description = "Maximum price for spot instances (-1 for on-demand price)"
  type        = number
  default     = -1
  
  validation {
    condition     = var.spot_max_price == -1 || var.spot_max_price > 0
    error_message = "Spot max price must be -1 (on-demand) or a positive number."
  }
}

# Network security variables
variable "authorized_ip_ranges" {
  description = "List of authorized IP ranges for AKS API server access"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.authorized_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All authorized IP ranges must be valid CIDR blocks."
  }
}

# Backup and disaster recovery variables
variable "enable_backup" {
  description = "Enable backup for storage accounts"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}