# General Configuration
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-iot-digital-twins"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "iot-digital-twins"
}

# Azure Digital Twins Configuration
variable "digital_twins_name" {
  description = "Name of the Azure Digital Twins instance"
  type        = string
  default     = ""
}

# Azure IoT Central Configuration
variable "iot_central_name" {
  description = "Name of the Azure IoT Central application"
  type        = string
  default     = ""
}

variable "iot_central_subdomain" {
  description = "Subdomain for IoT Central application"
  type        = string
  default     = ""
}

variable "iot_central_sku" {
  description = "SKU for IoT Central application"
  type        = string
  default     = "ST2"
  validation {
    condition     = contains(["ST0", "ST1", "ST2"], var.iot_central_sku)
    error_message = "IoT Central SKU must be one of: ST0, ST1, ST2."
  }
}

variable "iot_central_template" {
  description = "Template for IoT Central application"
  type        = string
  default     = "iotc-pnp-preview"
}

# Event Hub Configuration
variable "event_hub_namespace_name" {
  description = "Name of the Event Hub namespace"
  type        = string
  default     = ""
}

variable "event_hub_name" {
  description = "Name of the Event Hub"
  type        = string
  default     = "telemetry-hub"
}

variable "event_hub_partition_count" {
  description = "Number of partitions for Event Hub"
  type        = number
  default     = 4
  validation {
    condition     = var.event_hub_partition_count >= 1 && var.event_hub_partition_count <= 32
    error_message = "Event Hub partition count must be between 1 and 32."
  }
}

variable "event_hub_message_retention" {
  description = "Message retention in days for Event Hub"
  type        = number
  default     = 1
  validation {
    condition     = var.event_hub_message_retention >= 1 && var.event_hub_message_retention <= 7
    error_message = "Event Hub message retention must be between 1 and 7 days."
  }
}

variable "event_hub_namespace_sku" {
  description = "SKU for Event Hub namespace"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.event_hub_namespace_sku)
    error_message = "Event Hub namespace SKU must be one of: Basic, Standard, Premium."
  }
}

variable "event_hub_capacity" {
  description = "Capacity for Event Hub namespace"
  type        = number
  default     = 1
  validation {
    condition     = var.event_hub_capacity >= 1 && var.event_hub_capacity <= 20
    error_message = "Event Hub capacity must be between 1 and 20."
  }
}

# Azure Data Explorer Configuration
variable "data_explorer_cluster_name" {
  description = "Name of the Azure Data Explorer cluster"
  type        = string
  default     = ""
}

variable "data_explorer_database_name" {
  description = "Name of the Azure Data Explorer database"
  type        = string
  default     = "iottelemetry"
}

variable "data_explorer_sku" {
  description = "SKU for Azure Data Explorer cluster"
  type        = string
  default     = "Dev(No SLA)_Standard_E2a_v4"
}

variable "data_explorer_capacity" {
  description = "Capacity for Azure Data Explorer cluster"
  type        = number
  default     = 1
  validation {
    condition     = var.data_explorer_capacity >= 1
    error_message = "Data Explorer capacity must be at least 1."
  }
}

variable "data_explorer_hot_cache_period" {
  description = "Hot cache period for Data Explorer database"
  type        = string
  default     = "P7D"
}

variable "data_explorer_soft_delete_period" {
  description = "Soft delete period for Data Explorer database"
  type        = string
  default     = "P30D"
}

# Function App Configuration
variable "function_app_name" {
  description = "Name of the Function App"
  type        = string
  default     = ""
}

variable "storage_account_name" {
  description = "Name of the storage account for Function App"
  type        = string
  default     = ""
}

variable "storage_account_tier" {
  description = "Tier for storage account"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
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

variable "function_app_service_plan_sku" {
  description = "SKU for Function App service plan"
  type        = string
  default     = "Y1"
}

# Time Series Insights Configuration
variable "time_series_insights_name" {
  description = "Name of the Time Series Insights environment"
  type        = string
  default     = ""
}

variable "time_series_insights_sku" {
  description = "SKU for Time Series Insights environment"
  type        = string
  default     = "L1"
  validation {
    condition     = contains(["L1"], var.time_series_insights_sku)
    error_message = "Time Series Insights SKU must be L1."
  }
}

variable "time_series_insights_capacity" {
  description = "Capacity for Time Series Insights environment"
  type        = number
  default     = 1
  validation {
    condition     = var.time_series_insights_capacity >= 1
    error_message = "Time Series Insights capacity must be at least 1."
  }
}

# Digital Twin Model Configuration
variable "digital_twin_model_id" {
  description = "DTMI for the industrial equipment model"
  type        = string
  default     = "dtmi:com:example:IndustrialEquipment;1"
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "demo"
    Project     = "iot-digital-twins"
    Purpose     = "recipe"
  }
}

# User Object ID for RBAC assignments
variable "user_object_id" {
  description = "Object ID of the user for RBAC assignments (optional - will use current user if not provided)"
  type        = string
  default     = null
}

# Network Configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for services"
  type        = bool
  default     = false
}

variable "virtual_network_name" {
  description = "Name of the virtual network (required if enable_private_endpoints is true)"
  type        = string
  default     = ""
}

variable "subnet_name" {
  description = "Name of the subnet for private endpoints (required if enable_private_endpoints is true)"
  type        = string
  default     = ""
}

# Monitoring Configuration
variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for services"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 7 and 730."
  }
}