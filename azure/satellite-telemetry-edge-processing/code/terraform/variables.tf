# Variables for Azure Orbital and Azure Local edge-to-orbit data processing infrastructure
# This file defines all configurable parameters for the deployment

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "eastus"
  
  validation {
    condition = contains([
      "eastus", "westus2", "northeurope", "westeurope", 
      "southeastasia", "japaneast", "australiaeast"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports Azure Orbital services."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9-_]{1,90}$", var.resource_group_name))
    error_message = "Resource group name must be 1-90 characters and contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project/mission"
  type        = string
  default     = "orbital-edge"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters, lowercase alphanumeric and hyphens only."
  }
}

# Satellite Configuration Variables
variable "spacecraft_name" {
  description = "Name of the spacecraft to register with Azure Orbital"
  type        = string
  default     = "earth-obs-satellite"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,50}$", var.spacecraft_name))
    error_message = "Spacecraft name must be 1-50 characters, alphanumeric, hyphens, and underscores only."
  }
}

variable "norad_id" {
  description = "NORAD ID of the satellite (required for orbital tracking)"
  type        = string
  default     = "12345"
  
  validation {
    condition     = can(regex("^[0-9]{1,6}$", var.norad_id))
    error_message = "NORAD ID must be 1-6 digits."
  }
}

variable "tle_line1" {
  description = "Two-Line Element (TLE) line 1 for orbital parameters"
  type        = string
  default     = "1 25544U 98067A   08264.51782528 -.00002182  00000-0 -11606-4 0  2927"
  
  validation {
    condition     = can(regex("^1 .{67}$", var.tle_line1))
    error_message = "TLE line 1 must start with '1' and be 69 characters total."
  }
}

variable "tle_line2" {
  description = "Two-Line Element (TLE) line 2 for orbital parameters"
  type        = string
  default     = "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.72125391563537"
  
  validation {
    condition     = can(regex("^2 .{67}$", var.tle_line2))
    error_message = "TLE line 2 must start with '2' and be 69 characters total."
  }
}

# Communication Configuration Variables
variable "center_frequency_mhz" {
  description = "Center frequency for satellite communication in MHz"
  type        = number
  default     = 2250.0
  
  validation {
    condition     = var.center_frequency_mhz >= 1000 && var.center_frequency_mhz <= 40000
    error_message = "Center frequency must be between 1000 and 40000 MHz."
  }
}

variable "bandwidth_mhz" {
  description = "Bandwidth for satellite communication in MHz"
  type        = number
  default     = 15.0
  
  validation {
    condition     = var.bandwidth_mhz >= 1 && var.bandwidth_mhz <= 100
    error_message = "Bandwidth must be between 1 and 100 MHz."
  }
}

variable "minimum_elevation_degrees" {
  description = "Minimum elevation angle for satellite contacts in degrees"
  type        = number
  default     = 5
  
  validation {
    condition     = var.minimum_elevation_degrees >= 0 && var.minimum_elevation_degrees <= 90
    error_message = "Minimum elevation must be between 0 and 90 degrees."
  }
}

variable "minimum_contact_duration" {
  description = "Minimum viable contact duration in minutes"
  type        = number
  default     = 10
  
  validation {
    condition     = var.minimum_contact_duration >= 1 && var.minimum_contact_duration <= 60
    error_message = "Minimum contact duration must be between 1 and 60 minutes."
  }
}

# IoT Hub Configuration Variables
variable "iot_hub_sku" {
  description = "SKU for IoT Hub (B1, B2, B3, S1, S2, S3)"
  type        = string
  default     = "S2"
  
  validation {
    condition     = contains(["B1", "B2", "B3", "S1", "S2", "S3"], var.iot_hub_sku)
    error_message = "IoT Hub SKU must be one of: B1, B2, B3, S1, S2, S3."
  }
}

variable "iot_hub_capacity" {
  description = "Number of IoT Hub units"
  type        = number
  default     = 1
  
  validation {
    condition     = var.iot_hub_capacity >= 1 && var.iot_hub_capacity <= 200
    error_message = "IoT Hub capacity must be between 1 and 200 units."
  }
}

variable "iot_hub_partition_count" {
  description = "Number of partitions for IoT Hub Event Hub-compatible endpoint"
  type        = number
  default     = 8
  
  validation {
    condition     = var.iot_hub_partition_count >= 2 && var.iot_hub_partition_count <= 32
    error_message = "IoT Hub partition count must be between 2 and 32."
  }
}

# Storage Configuration Variables
variable "storage_account_tier" {
  description = "Storage account tier (Standard or Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type (LRS, GRS, RAGRS, ZRS)"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS."
  }
}

variable "storage_access_tier" {
  description = "Storage account access tier (Hot or Cool)"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_access_tier)
    error_message = "Storage access tier must be either Hot or Cool."
  }
}

variable "enable_hierarchical_namespace" {
  description = "Enable hierarchical namespace for Data Lake Storage Gen2"
  type        = bool
  default     = true
}

# Function App Configuration Variables
variable "function_app_service_plan_sku" {
  description = "SKU for Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition     = contains(["Y1", "EP1", "EP2", "EP3", "P1v2", "P2v2", "P3v2"], var.function_app_service_plan_sku)
    error_message = "Function App service plan SKU must be one of: Y1, EP1, EP2, EP3, P1v2, P2v2, P3v2."
  }
}

variable "function_app_runtime" {
  description = "Runtime for Function App"
  type        = string
  default     = "python"
  
  validation {
    condition     = contains(["python", "node", "dotnet", "java"], var.function_app_runtime)
    error_message = "Function App runtime must be one of: python, node, dotnet, java."
  }
}

variable "function_app_runtime_version" {
  description = "Runtime version for Function App"
  type        = string
  default     = "3.11"
}

# Azure Local Configuration Variables
variable "azure_local_cluster_name" {
  description = "Name of the Azure Local cluster"
  type        = string
  default     = null
  
  validation {
    condition     = var.azure_local_cluster_name == null || can(regex("^[a-zA-Z0-9-_]{1,50}$", var.azure_local_cluster_name))
    error_message = "Azure Local cluster name must be 1-50 characters, alphanumeric, hyphens, and underscores only."
  }
}

variable "enable_azure_local" {
  description = "Enable Azure Local deployment (requires physical hardware)"
  type        = bool
  default     = false
}

variable "azure_local_location" {
  description = "Location for Azure Local deployment"
  type        = string
  default     = "eastus"
}

# Monitoring Configuration Variables
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standalone."
  }
}

variable "log_analytics_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log retention period must be between 7 and 730 days."
  }
}

variable "enable_monitoring" {
  description = "Enable comprehensive monitoring and alerting"
  type        = bool
  default     = true
}

# Network Configuration Variables
variable "enable_private_endpoints" {
  description = "Enable private endpoints for secure communication"
  type        = bool
  default     = false
}

variable "virtual_network_address_space" {
  description = "Address space for virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition     = alltrue([for addr in var.virtual_network_address_space : can(cidrhost(addr, 0))])
    error_message = "All virtual network address spaces must be valid CIDR blocks."
  }
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for subnets"
  type = object({
    orbital_subnet    = string
    function_subnet   = string
    storage_subnet    = string
    local_subnet      = string
  })
  default = {
    orbital_subnet    = "10.0.1.0/24"
    function_subnet   = "10.0.2.0/24"
    storage_subnet    = "10.0.3.0/24"
    local_subnet      = "10.0.4.0/24"
  }
  
  validation {
    condition = alltrue([
      for prefix in values(var.subnet_address_prefixes) : can(cidrhost(prefix, 0))
    ])
    error_message = "All subnet address prefixes must be valid CIDR blocks."
  }
}

# Security Configuration Variables
variable "enable_key_vault" {
  description = "Enable Azure Key Vault for secrets management"
  type        = bool
  default     = true
}

variable "key_vault_sku" {
  description = "SKU for Azure Key Vault (standard or premium)"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either standard or premium."
  }
}

variable "enable_rbac" {
  description = "Enable Role-Based Access Control"
  type        = bool
  default     = true
}

# Tagging Variables
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "orbital-edge-processing"
    Environment = "production"
    Mission     = "earth-observation"
    ManagedBy   = "terraform"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Advanced Configuration Variables
variable "enable_data_lake_analytics" {
  description = "Enable Data Lake Analytics for large-scale processing"
  type        = bool
  default     = false
}

variable "enable_ai_services" {
  description = "Enable Azure AI Services for satellite data analysis"
  type        = bool
  default     = false
}

variable "enable_power_bi_integration" {
  description = "Enable Power BI integration for mission control dashboard"
  type        = bool
  default     = false
}

variable "satellite_data_retention_days" {
  description = "Retention period for satellite data in days"
  type        = number
  default     = 90
  
  validation {
    condition     = var.satellite_data_retention_days >= 7 && var.satellite_data_retention_days <= 2555
    error_message = "Satellite data retention period must be between 7 and 2555 days."
  }
}

variable "enable_disaster_recovery" {
  description = "Enable disaster recovery and backup"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "Backup retention period must be between 7 and 365 days."
  }
}