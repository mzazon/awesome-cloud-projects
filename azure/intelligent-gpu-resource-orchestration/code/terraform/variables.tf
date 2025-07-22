# Variables for Azure GPU orchestration infrastructure
# These variables allow customization of the deployment for different environments

variable "resource_group_name" {
  description = "Name of the resource group for GPU orchestration resources"
  type        = string
  default     = "rg-gpu-orchestration"
  
  validation {
    condition     = length(var.resource_group_name) > 0 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "Azure region for resource deployment (must support GPU compute)"
  type        = string
  default     = "West US 3"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US 2", "West US 3", "Central US", "South Central US",
      "North Europe", "West Europe", "UK South", "France Central", "Germany West Central",
      "Southeast Asia", "East Asia", "Japan East", "Australia East", "Canada Central"
    ], var.location)
    error_message = "Location must be a region that supports GPU compute and Container Apps."
  }
}

variable "environment" {
  description = "Environment tag for resource identification"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "gpu-orchestration"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Container Apps Configuration
variable "aca_min_replicas" {
  description = "Minimum number of Container App replicas for ML inference"
  type        = number
  default     = 0
  
  validation {
    condition     = var.aca_min_replicas >= 0 && var.aca_min_replicas <= 25
    error_message = "Container App min replicas must be between 0 and 25."
  }
}

variable "aca_max_replicas" {
  description = "Maximum number of Container App replicas for ML inference"
  type        = number
  default     = 10
  
  validation {
    condition     = var.aca_max_replicas >= 1 && var.aca_max_replicas <= 25
    error_message = "Container App max replicas must be between 1 and 25."
  }
}

variable "aca_cpu_cores" {
  description = "CPU cores allocated to each Container App replica"
  type        = number
  default     = 4.0
  
  validation {
    condition     = contains([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0, 3.25, 3.5, 3.75, 4.0], var.aca_cpu_cores)
    error_message = "CPU cores must be a valid Container Apps CPU allocation (0.25 to 4.0 in 0.25 increments)."
  }
}

variable "aca_memory_gi" {
  description = "Memory in GiB allocated to each Container App replica"
  type        = string
  default     = "8Gi"
  
  validation {
    condition     = contains(["0.5Gi", "1Gi", "1.5Gi", "2Gi", "2.5Gi", "3Gi", "3.5Gi", "4Gi", "4.5Gi", "5Gi", "5.5Gi", "6Gi", "6.5Gi", "7Gi", "7.5Gi", "8Gi"], var.aca_memory_gi)
    error_message = "Memory must be a valid Container Apps memory allocation."
  }
}

variable "container_image" {
  description = "Container image for ML inference application"
  type        = string
  default     = "mcr.microsoft.com/azuredocs/aci-tutorial-app"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._/-]+$", var.container_image))
    error_message = "Container image must be a valid container registry path."
  }
}

# Azure Batch Configuration
variable "batch_vm_size" {
  description = "Azure Batch VM size for GPU processing (must be GPU-enabled)"
  type        = string
  default     = "Standard_NC6s_v3"
  
  validation {
    condition = contains([
      "Standard_NC6s_v3", "Standard_NC12s_v3", "Standard_NC24s_v3",
      "Standard_ND40rs_v2", "Standard_NC6s_v2", "Standard_NC12s_v2", "Standard_NC24s_v2",
      "Standard_NC4as_T4_v3", "Standard_NC8as_T4_v3", "Standard_NC16as_T4_v3", "Standard_NC64as_T4_v3"
    ], var.batch_vm_size)
    error_message = "VM size must be a GPU-enabled Azure VM size."
  }
}

variable "batch_max_dedicated_nodes" {
  description = "Maximum number of dedicated nodes in Batch pool"
  type        = number
  default     = 0
  
  validation {
    condition     = var.batch_max_dedicated_nodes >= 0 && var.batch_max_dedicated_nodes <= 100
    error_message = "Max dedicated nodes must be between 0 and 100."
  }
}

variable "batch_max_low_priority_nodes" {
  description = "Maximum number of low-priority nodes in Batch pool"
  type        = number
  default     = 4
  
  validation {
    condition     = var.batch_max_low_priority_nodes >= 0 && var.batch_max_low_priority_nodes <= 1000
    error_message = "Max low-priority nodes must be between 0 and 1000."
  }
}

variable "batch_target_low_priority_nodes" {
  description = "Initial target number of low-priority nodes in Batch pool"
  type        = number
  default     = 2
  
  validation {
    condition     = var.batch_target_low_priority_nodes >= 0
    error_message = "Target low-priority nodes must be non-negative."
  }
}

# Monitoring and Alerting Configuration
variable "enable_monitoring_alerts" {
  description = "Enable Azure Monitor alerts for GPU utilization and costs"
  type        = bool
  default     = true
}

variable "gpu_utilization_alert_threshold" {
  description = "Threshold for GPU utilization alert (requests per minute)"
  type        = number
  default     = 50
  
  validation {
    condition     = var.gpu_utilization_alert_threshold > 0
    error_message = "GPU utilization threshold must be positive."
  }
}

variable "batch_queue_depth_alert_threshold" {
  description = "Threshold for batch queue depth alert (number of messages)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.batch_queue_depth_alert_threshold > 0
    error_message = "Batch queue depth threshold must be positive."
  }
}

variable "cost_alert_threshold" {
  description = "Daily cost threshold for GPU usage alerts (USD)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.cost_alert_threshold > 0
    error_message = "Cost alert threshold must be positive."
  }
}

# Configuration Parameters for Key Vault
variable "realtime_threshold_ms" {
  description = "Response time threshold for real-time vs batch routing (milliseconds)"
  type        = number
  default     = 2000
  
  validation {
    condition     = var.realtime_threshold_ms > 0
    error_message = "Real-time threshold must be positive."
  }
}

variable "batch_cost_threshold" {
  description = "Cost threshold for batch processing routing (USD per hour)"
  type        = number
  default     = 0.50
  
  validation {
    condition     = var.batch_cost_threshold > 0
    error_message = "Batch cost threshold must be positive."
  }
}

variable "model_version" {
  description = "ML model version for deployment"
  type        = string
  default     = "v1.0"
  
  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+$", var.model_version))
    error_message = "Model version must follow semantic versioning pattern (e.g., v1.0)."
  }
}

variable "gpu_memory_limit_mb" {
  description = "GPU memory limit in MB for ML model inference"
  type        = number
  default     = 16384
  
  validation {
    condition     = var.gpu_memory_limit_mb > 0 && var.gpu_memory_limit_mb <= 81920
    error_message = "GPU memory limit must be between 1 MB and 80 GB (81920 MB)."
  }
}

# Function App Configuration
variable "function_app_runtime" {
  description = "Runtime stack for Azure Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["python", "node", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function app runtime must be one of: python, node, dotnet, java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Azure Function App"
  type        = string
  default     = "3.11"
  
  validation {
    condition     = length(var.function_app_runtime_version) > 0
    error_message = "Function app runtime version must not be empty."
  }
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Common Tags
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "GPU Orchestration"
    Recipe      = "orchestrating-dynamic-gpu-resource-allocation"
    ManagedBy   = "Terraform"
  }
}