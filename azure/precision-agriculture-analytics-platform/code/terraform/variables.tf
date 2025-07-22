# Variables for Azure precision agriculture analytics platform
# This file defines all configurable parameters for the infrastructure deployment

# Basic configuration variables
variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", 
      "Central US", "North Central US", "South Central US",
      "Canada Central", "Canada East",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North",
      "Australia East", "Australia Southeast", "Japan East", "Japan West",
      "Korea Central", "Southeast Asia", "East Asia"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports all required services."
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
  description = "Name of the precision agriculture project"
  type        = string
  default     = "precision-ag"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Resource naming variables
variable "resource_group_name" {
  description = "Name of the resource group (if not provided, will be auto-generated)"
  type        = string
  default     = ""
}

variable "resource_name_suffix" {
  description = "Suffix to append to resource names for uniqueness (if not provided, will be auto-generated)"
  type        = string
  default     = ""
}

# Azure Data Manager for Agriculture configuration
variable "adma_sku" {
  description = "SKU for Azure Data Manager for Agriculture instance"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.adma_sku)
    error_message = "ADMA SKU must be one of: Basic, Standard, Premium."
  }
}

variable "farm_metadata" {
  description = "Metadata for the demo farm configuration"
  type = object({
    name            = string
    total_area      = number
    crop_types      = list(string)
    farming_method  = string
    season          = string
  })
  default = {
    name           = "Demo Precision Farm"
    total_area     = 1000
    crop_types     = ["corn", "soybeans"]
    farming_method = "precision"
    season         = "2025"
  }
}

# IoT Hub configuration
variable "iot_hub_sku" {
  description = "SKU configuration for IoT Hub"
  type = object({
    name     = string
    capacity = number
  })
  default = {
    name     = "S1"
    capacity = 1
  }
  
  validation {
    condition = contains(["F1", "S1", "S2", "S3"], var.iot_hub_sku.name)
    error_message = "IoT Hub SKU name must be one of: F1, S1, S2, S3."
  }
}

variable "iot_hub_partition_count" {
  description = "Number of partitions for IoT Hub event hub endpoint"
  type        = number
  default     = 4
  
  validation {
    condition     = var.iot_hub_partition_count >= 2 && var.iot_hub_partition_count <= 128
    error_message = "IoT Hub partition count must be between 2 and 128."
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

# Storage account configuration
variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_access_tier" {
  description = "Access tier for blob storage"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be either Hot or Cool."
  }
}

variable "storage_containers" {
  description = "List of storage containers to create for agricultural data"
  type        = list(string)
  default     = ["crop-imagery", "field-boundaries", "weather-data", "analytics-results"]
}

# Azure AI Services configuration
variable "ai_services_sku" {
  description = "SKU for Azure AI Services (Cognitive Services)"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0", "S1", "S2", "S3", "S4"], var.ai_services_sku)
    error_message = "AI Services SKU must be one of: F0, S0, S1, S2, S3, S4."
  }
}

variable "ai_services_kind" {
  description = "Kind of Azure AI Services account"
  type        = string
  default     = "CognitiveServices"
  
  validation {
    condition     = contains(["CognitiveServices", "ComputerVision", "CustomVision.Training", "CustomVision.Prediction"], var.ai_services_kind)
    error_message = "AI Services kind must be a valid Cognitive Services type."
  }
}

# Azure Maps configuration
variable "maps_sku" {
  description = "SKU for Azure Maps account"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["S0", "S1"], var.maps_sku)
    error_message = "Azure Maps SKU must be either S0 or S1."
  }
}

# Stream Analytics configuration
variable "stream_analytics_sku" {
  description = "SKU for Stream Analytics job"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard"], var.stream_analytics_sku)
    error_message = "Stream Analytics SKU must be Standard."
  }
}

variable "stream_analytics_streaming_units" {
  description = "Number of streaming units for Stream Analytics job"
  type        = number
  default     = 3
  
  validation {
    condition     = var.stream_analytics_streaming_units >= 1 && var.stream_analytics_streaming_units <= 120
    error_message = "Streaming units must be between 1 and 120."
  }
}

variable "stream_analytics_events_policy" {
  description = "Policy for handling out-of-order events"
  type        = string
  default     = "Adjust"
  
  validation {
    condition     = contains(["Adjust", "Drop"], var.stream_analytics_events_policy)
    error_message = "Events policy must be either Adjust or Drop."
  }
}

variable "stream_analytics_late_arrival_max_delay" {
  description = "Maximum delay for late-arriving events in seconds"
  type        = number
  default     = 5
  
  validation {
    condition     = var.stream_analytics_late_arrival_max_delay >= 0 && var.stream_analytics_late_arrival_max_delay <= 1814400
    error_message = "Late arrival max delay must be between 0 and 1814400 seconds (21 days)."
  }
}

variable "stream_analytics_out_of_order_max_delay" {
  description = "Maximum delay for out-of-order events in seconds"
  type        = number
  default     = 10
  
  validation {
    condition     = var.stream_analytics_out_of_order_max_delay >= 0 && var.stream_analytics_out_of_order_max_delay <= 599
    error_message = "Out-of-order max delay must be between 0 and 599 seconds."
  }
}

# Azure Function App configuration
variable "function_app_service_plan_sku" {
  description = "SKU for Azure Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1", "P2", "P3"], var.function_app_service_plan_sku)
    error_message = "Function App service plan SKU must be valid consumption or premium plan SKU."
  }
}

variable "function_app_runtime" {
  description = "Runtime for Azure Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["python", "node", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: python, node, dotnet, java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Azure Function App"
  type        = string
  default     = "3.9"
}

# Sample IoT device configuration
variable "iot_device_id" {
  description = "ID for the sample IoT device"
  type        = string
  default     = "soil-sensor-field-01"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-._]{1,128}$", var.iot_device_id))
    error_message = "IoT device ID must be 1-128 characters and contain only alphanumeric characters, hyphens, periods, and underscores."
  }
}

# Tagging variables
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "precision-agriculture"
    Environment = "demo"
    Industry    = "agriculture"
    Workload    = "analytics"
    Purpose     = "precision-agriculture"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Cost management variables
variable "enable_cost_alerts" {
  description = "Enable cost management alerts for the deployment"
  type        = bool
  default     = false
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD for cost alerts"
  type        = number
  default     = 500
  
  validation {
    condition     = var.monthly_budget_limit > 0
    error_message = "Monthly budget limit must be greater than 0."
  }
}

# Security and compliance variables
variable "enable_advanced_threat_protection" {
  description = "Enable Advanced Threat Protection for storage account"
  type        = bool
  default     = false
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for Azure resources"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_retention_days" {
  description = "Retention period for Log Analytics workspace in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_workspace_retention_days >= 30 && var.log_analytics_workspace_retention_days <= 730
    error_message = "Log Analytics retention days must be between 30 and 730."
  }
}