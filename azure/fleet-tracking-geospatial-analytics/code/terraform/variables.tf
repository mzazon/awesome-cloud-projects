# Variables for Azure Geospatial Analytics Infrastructure
# This file defines all configurable parameters for the deployment

# Core Configuration Variables
variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "geospatial-analytics"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "Central US",
      "North Central US", "South Central US", "West Central US",
      "North Europe", "West Europe", "UK South", "UK West",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the resource group (will be created if not exists)"
  type        = string
  default     = null
}

# Event Hub Configuration
variable "eventhub_namespace_sku" {
  description = "SKU for Event Hub namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.eventhub_namespace_sku)
    error_message = "Event Hub namespace SKU must be Basic, Standard, or Premium."
  }
}

variable "eventhub_namespace_capacity" {
  description = "Capacity (throughput units) for Event Hub namespace"
  type        = number
  default     = 2
  
  validation {
    condition     = var.eventhub_namespace_capacity >= 1 && var.eventhub_namespace_capacity <= 20
    error_message = "Event Hub namespace capacity must be between 1 and 20 throughput units."
  }
}

variable "eventhub_partition_count" {
  description = "Number of partitions for the Event Hub"
  type        = number
  default     = 4
  
  validation {
    condition     = var.eventhub_partition_count >= 2 && var.eventhub_partition_count <= 32
    error_message = "Event Hub partition count must be between 2 and 32."
  }
}

variable "eventhub_message_retention" {
  description = "Message retention in days for Event Hub"
  type        = number
  default     = 1
  
  validation {
    condition     = var.eventhub_message_retention >= 1 && var.eventhub_message_retention <= 7
    error_message = "Event Hub message retention must be between 1 and 7 days."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

# Stream Analytics Configuration
variable "stream_analytics_sku" {
  description = "SKU for Stream Analytics job"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "StandardV2"], var.stream_analytics_sku)
    error_message = "Stream Analytics SKU must be Standard or StandardV2."
  }
}

variable "stream_analytics_streaming_units" {
  description = "Number of streaming units for Stream Analytics job"
  type        = number
  default     = 3
  
  validation {
    condition     = var.stream_analytics_streaming_units >= 1 && var.stream_analytics_streaming_units <= 192
    error_message = "Stream Analytics streaming units must be between 1 and 192."
  }
}

variable "stream_analytics_events_late_arrival_max_delay" {
  description = "Maximum delay in seconds for late-arriving events"
  type        = number
  default     = 5
  
  validation {
    condition     = var.stream_analytics_events_late_arrival_max_delay >= 0
    error_message = "Late arrival max delay must be non-negative."
  }
}

variable "stream_analytics_events_out_of_order_max_delay" {
  description = "Maximum delay in seconds for out-of-order events"
  type        = number
  default     = 0
  
  validation {
    condition     = var.stream_analytics_events_out_of_order_max_delay >= 0
    error_message = "Out-of-order max delay must be non-negative."
  }
}

variable "stream_analytics_output_error_policy" {
  description = "Output error policy for Stream Analytics"
  type        = string
  default     = "Drop"
  
  validation {
    condition     = contains(["Stop", "Drop"], var.stream_analytics_output_error_policy)
    error_message = "Output error policy must be Stop or Drop."
  }
}

# Cosmos DB Configuration
variable "cosmos_db_consistency_level" {
  description = "Consistency level for Cosmos DB"
  type        = string
  default     = "Eventual"
  
  validation {
    condition = contains([
      "Eventual", "ConsistentPrefix", "Session", "BoundedStaleness", "Strong"
    ], var.cosmos_db_consistency_level)
    error_message = "Cosmos DB consistency level must be Eventual, ConsistentPrefix, Session, BoundedStaleness, or Strong."
  }
}

variable "cosmos_db_max_staleness_prefix" {
  description = "Maximum staleness prefix for BoundedStaleness consistency"
  type        = number
  default     = 100000
  
  validation {
    condition     = var.cosmos_db_max_staleness_prefix >= 10 && var.cosmos_db_max_staleness_prefix <= 2147483647
    error_message = "Max staleness prefix must be between 10 and 2147483647."
  }
}

variable "cosmos_db_max_interval_in_seconds" {
  description = "Maximum interval in seconds for BoundedStaleness consistency"
  type        = number
  default     = 300
  
  validation {
    condition     = var.cosmos_db_max_interval_in_seconds >= 5 && var.cosmos_db_max_interval_in_seconds <= 86400
    error_message = "Max interval must be between 5 and 86400 seconds."
  }
}

variable "cosmos_db_throughput" {
  description = "Throughput (RU/s) for Cosmos DB container"
  type        = number
  default     = 400
  
  validation {
    condition     = var.cosmos_db_throughput >= 400 && var.cosmos_db_throughput <= 1000000
    error_message = "Cosmos DB throughput must be between 400 and 1000000 RU/s."
  }
}

variable "cosmos_db_enable_automatic_failover" {
  description = "Enable automatic failover for Cosmos DB"
  type        = bool
  default     = false
}

variable "cosmos_db_enable_multiple_write_locations" {
  description = "Enable multiple write locations for Cosmos DB"
  type        = bool
  default     = false
}

# Azure Maps Configuration
variable "azure_maps_sku" {
  description = "SKU for Azure Maps account"
  type        = string
  default     = "G2"
  
  validation {
    condition     = contains(["S0", "S1", "G2"], var.azure_maps_sku)
    error_message = "Azure Maps SKU must be S0, S1, or G2."
  }
}

variable "azure_maps_kind" {
  description = "Kind of Azure Maps account"
  type        = string
  default     = "Gen2"
  
  validation {
    condition     = contains(["Gen1", "Gen2"], var.azure_maps_kind)
    error_message = "Azure Maps kind must be Gen1 or Gen2."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Azure Monitor and alerting"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
  }
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging for resources"
  type        = bool
  default     = true
}

# Geofencing Configuration
variable "default_geofence_coordinates" {
  description = "Default geofence polygon coordinates (longitude, latitude pairs)"
  type = list(object({
    longitude = number
    latitude  = number
  }))
  default = [
    { longitude = -122.135, latitude = 47.642 },
    { longitude = -122.135, latitude = 47.658 },
    { longitude = -122.112, latitude = 47.658 },
    { longitude = -122.112, latitude = 47.642 },
    { longitude = -122.135, latitude = 47.642 }
  ]
}

variable "depot_location" {
  description = "Depot location coordinates for distance calculations"
  type = object({
    longitude = number
    latitude  = number
  })
  default = {
    longitude = -122.123
    latitude  = 47.650
  }
}

variable "speed_limit_threshold" {
  description = "Speed limit threshold for alerts (in units used by vehicles)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.speed_limit_threshold > 0
    error_message = "Speed limit threshold must be greater than 0."
  }
}

# Tagging Configuration
variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "geospatial-analytics"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Network Security Configuration
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for supported services"
  type        = bool
  default     = false
}

# Backup and Disaster Recovery Configuration
variable "enable_backup" {
  description = "Enable backup for applicable resources"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 99
    error_message = "Backup retention days must be between 1 and 99."
  }
}