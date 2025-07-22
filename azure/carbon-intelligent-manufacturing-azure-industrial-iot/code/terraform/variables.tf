# Variables for Smart Factory Carbon Footprint Monitoring Infrastructure

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India",
      "UAE North", "South Africa North"
    ], var.location)
    error_message = "The location must be a valid Azure region."
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
  default     = "smart-factory-carbon"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# IoT Hub Configuration
variable "iot_hub_sku" {
  description = "The SKU tier for the IoT Hub"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["F1", "S1", "S2", "S3"], var.iot_hub_sku)
    error_message = "IoT Hub SKU must be one of: F1, S1, S2, S3."
  }
}

variable "iot_hub_capacity" {
  description = "The number of units for the IoT Hub"
  type        = number
  default     = 1
  
  validation {
    condition     = var.iot_hub_capacity >= 1 && var.iot_hub_capacity <= 200
    error_message = "IoT Hub capacity must be between 1 and 200."
  }
}

variable "iot_hub_partition_count" {
  description = "The number of partitions for IoT Hub device-to-cloud messages"
  type        = number
  default     = 4
  
  validation {
    condition     = var.iot_hub_partition_count >= 2 && var.iot_hub_partition_count <= 32
    error_message = "IoT Hub partition count must be between 2 and 32."
  }
}

# Data Explorer Configuration
variable "kusto_sku_name" {
  description = "The SKU name for the Data Explorer cluster"
  type        = string
  default     = "Standard_D11_v2"
  
  validation {
    condition = contains([
      "Standard_D11_v2", "Standard_D12_v2", "Standard_D13_v2", "Standard_D14_v2",
      "Standard_DS13_v2+1TB_PS", "Standard_DS13_v2+2TB_PS", "Standard_DS14_v2+3TB_PS",
      "Standard_DS14_v2+4TB_PS", "Standard_L4s", "Standard_L8s", "Standard_L16s"
    ], var.kusto_sku_name)
    error_message = "Invalid Data Explorer SKU. Please choose a supported SKU."
  }
}

variable "kusto_capacity" {
  description = "The number of instances for the Data Explorer cluster"
  type        = number
  default     = 2
  
  validation {
    condition     = var.kusto_capacity >= 2 && var.kusto_capacity <= 1000
    error_message = "Data Explorer capacity must be between 2 and 1000."
  }
}

variable "kusto_database_cache_period" {
  description = "Hot cache period for the Data Explorer database (ISO 8601 duration)"
  type        = string
  default     = "P30D"
  
  validation {
    condition     = can(regex("^P([0-9]+Y)?([0-9]+M)?([0-9]+D)?$", var.kusto_database_cache_period))
    error_message = "Cache period must be in ISO 8601 duration format (e.g., P30D for 30 days)."
  }
}

variable "kusto_database_retention_period" {
  description = "Data retention period for the Data Explorer database (ISO 8601 duration)"
  type        = string
  default     = "P365D"
  
  validation {
    condition     = can(regex("^P([0-9]+Y)?([0-9]+M)?([0-9]+D)?$", var.kusto_database_retention_period))
    error_message = "Retention period must be in ISO 8601 duration format (e.g., P365D for 365 days)."
  }
}

# Event Hubs Configuration
variable "eventhub_sku" {
  description = "The SKU tier for Event Hubs namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.eventhub_sku)
    error_message = "Event Hubs SKU must be one of: Basic, Standard, Premium."
  }
}

variable "eventhub_capacity" {
  description = "The throughput units for Event Hubs namespace"
  type        = number
  default     = 1
  
  validation {
    condition     = var.eventhub_capacity >= 1 && var.eventhub_capacity <= 20
    error_message = "Event Hubs capacity must be between 1 and 20 throughput units."
  }
}

variable "eventhub_partition_count" {
  description = "The number of partitions for the Event Hub"
  type        = number
  default     = 4
  
  validation {
    condition     = var.eventhub_partition_count >= 2 && var.eventhub_partition_count <= 32
    error_message = "Event Hub partition count must be between 2 and 32."
  }
}

variable "eventhub_message_retention" {
  description = "The number of days to retain messages in the Event Hub"
  type        = number
  default     = 7
  
  validation {
    condition     = var.eventhub_message_retention >= 1 && var.eventhub_message_retention <= 7
    error_message = "Event Hub message retention must be between 1 and 7 days."
  }
}

# Function App Configuration
variable "function_app_sku_tier" {
  description = "The pricing tier for the Function App service plan"
  type        = string
  default     = "Dynamic"
  
  validation {
    condition     = contains(["Dynamic", "Premium", "Standard", "Basic"], var.function_app_sku_tier)
    error_message = "Function App SKU tier must be one of: Dynamic, Premium, Standard, Basic."
  }
}

variable "function_app_sku_size" {
  description = "The size for the Function App service plan"
  type        = string
  default     = "Y1"
  
  validation {
    condition = contains([
      "Y1", "EP1", "EP2", "EP3", "S1", "S2", "S3", "B1", "B2", "B3"
    ], var.function_app_sku_size)
    error_message = "Invalid Function App SKU size. Please choose a supported size."
  }
}

variable "storage_account_tier" {
  description = "The performance tier for storage accounts"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either 'Standard' or 'Premium'."
  }
}

variable "storage_account_replication_type" {
  description = "The replication type for storage accounts"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Carbon Calculation Configuration
variable "carbon_emission_factor" {
  description = "Carbon emission factor in kg CO2 per kWh (default: grid average)"
  type        = number
  default     = 0.4
  
  validation {
    condition     = var.carbon_emission_factor >= 0 && var.carbon_emission_factor <= 2.0
    error_message = "Carbon emission factor must be between 0 and 2.0 kg CO2/kWh."
  }
}

variable "enable_monitoring" {
  description = "Enable Application Insights and monitoring for Function Apps"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Enable backup for critical resources"
  type        = bool
  default     = true
}

# Tagging Configuration
variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    Purpose     = "carbon-monitoring"
    Environment = "development"
    Project     = "smart-factory"
    ManagedBy   = "terraform"
  }
  
  validation {
    condition     = contains(keys(var.tags), "Purpose") && contains(keys(var.tags), "Environment")
    error_message = "Tags must include 'Purpose' and 'Environment' keys."
  }
}

# Security Configuration
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources (CIDR format)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be in valid CIDR format."
  }
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for enhanced security"
  type        = bool
  default     = false
}