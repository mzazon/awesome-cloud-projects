# Variables for Azure IoT Edge and Machine Learning Anomaly Detection Infrastructure

# Basic Configuration Variables
variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "South Central US", "North Central US",
      "West Europe", "North Europe", "UK South", "UK West",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast"
    ], var.location)
    error_message = "The location must be a valid Azure region that supports IoT Hub and Machine Learning services."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase letters and numbers."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "anomaly-detection"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the Azure resource group. If not specified, will be auto-generated"
  type        = string
  default     = ""
}

# IoT Hub Configuration
variable "iot_hub_sku" {
  description = "SKU for the IoT Hub"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["F1", "B1", "B2", "B3", "S1", "S2", "S3"], var.iot_hub_sku)
    error_message = "IoT Hub SKU must be one of: F1, B1, B2, B3, S1, S2, S3."
  }
}

variable "iot_hub_partition_count" {
  description = "Number of partitions for IoT Hub event hub endpoint"
  type        = number
  default     = 2
  
  validation {
    condition     = var.iot_hub_partition_count >= 2 && var.iot_hub_partition_count <= 32
    error_message = "IoT Hub partition count must be between 2 and 32."
  }
}

variable "iot_hub_retention_days" {
  description = "Message retention time in days for IoT Hub"
  type        = number
  default     = 1
  
  validation {
    condition     = var.iot_hub_retention_days >= 1 && var.iot_hub_retention_days <= 7
    error_message = "IoT Hub retention days must be between 1 and 7."
  }
}

variable "edge_device_id" {
  description = "ID for the IoT Edge device"
  type        = string
  default     = "factory-edge-device-01"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.edge_device_id))
    error_message = "Edge device ID must contain only letters, numbers, and hyphens."
  }
}

# Machine Learning Workspace Configuration
variable "ml_workspace_sku" {
  description = "SKU for the Machine Learning workspace"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Enterprise"], var.ml_workspace_sku)
    error_message = "ML workspace SKU must be either 'Basic' or 'Enterprise'."
  }
}

variable "ml_compute_instance_size" {
  description = "VM size for ML compute instances"
  type        = string
  default     = "Standard_DS3_v2"
  
  validation {
    condition     = can(regex("^Standard_[A-Z0-9_]+$", var.ml_compute_instance_size))
    error_message = "ML compute instance size must be a valid Azure VM size."
  }
}

variable "ml_compute_min_instances" {
  description = "Minimum number of instances for ML compute cluster"
  type        = number
  default     = 0
  
  validation {
    condition     = var.ml_compute_min_instances >= 0 && var.ml_compute_min_instances <= 100
    error_message = "ML compute minimum instances must be between 0 and 100."
  }
}

variable "ml_compute_max_instances" {
  description = "Maximum number of instances for ML compute cluster"
  type        = number
  default     = 4
  
  validation {
    condition     = var.ml_compute_max_instances >= 1 && var.ml_compute_max_instances <= 100
    error_message = "ML compute maximum instances must be between 1 and 100."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "enable_hierarchical_namespace" {
  description = "Enable hierarchical namespace for Data Lake Storage Gen2"
  type        = bool
  default     = true
}

# Stream Analytics Configuration
variable "stream_analytics_sku" {
  description = "SKU for Stream Analytics job"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard"], var.stream_analytics_sku)
    error_message = "Stream Analytics SKU must be 'Standard'."
  }
}

variable "stream_analytics_streaming_units" {
  description = "Number of streaming units for Stream Analytics job"
  type        = number
  default     = 1
  
  validation {
    condition     = var.stream_analytics_streaming_units >= 1 && var.stream_analytics_streaming_units <= 120
    error_message = "Stream Analytics streaming units must be between 1 and 120."
  }
}

variable "stream_analytics_compatibility_level" {
  description = "Compatibility level for Stream Analytics job"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.stream_analytics_compatibility_level)
    error_message = "Stream Analytics compatibility level must be one of: 1.0, 1.1, 1.2."
  }
}

# Application Insights Configuration
variable "application_insights_type" {
  description = "Application type for Application Insights"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be either 'web' or 'other'."
  }
}

# Key Vault Configuration
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

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention days must be between 7 and 90."
  }
}

# Log Analytics Configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be a valid pricing tier."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain log data"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}

# Tags Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Anomaly Detection"
    Environment = "Development"
    Project     = "IoT Edge ML"
    Owner       = "DevOps Team"
  }
}

# Anomaly Detection Configuration
variable "anomaly_detection_threshold" {
  description = "Threshold for anomaly detection scores"
  type        = number
  default     = 3.5
  
  validation {
    condition     = var.anomaly_detection_threshold >= 0.0 && var.anomaly_detection_threshold <= 10.0
    error_message = "Anomaly detection threshold must be between 0.0 and 10.0."
  }
}

variable "anomaly_detection_window_minutes" {
  description = "Time window in minutes for anomaly detection"
  type        = number
  default     = 5
  
  validation {
    condition     = var.anomaly_detection_window_minutes >= 1 && var.anomaly_detection_window_minutes <= 60
    error_message = "Anomaly detection window must be between 1 and 60 minutes."
  }
}

# Network Security Configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for services"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}