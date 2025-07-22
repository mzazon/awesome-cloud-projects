# Variable definitions for video content moderation infrastructure

variable "resource_group_name" {
  description = "Name of the resource group for video moderation resources"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3", 
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", 
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North",
      "Southeast Asia", "East Asia", "Australia East", "Australia Southeast",
      "Japan East", "Japan West", "Korea Central", "India Central"
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
  description = "Project name used for resource naming"
  type        = string
  default     = "videomod"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name)) && length(var.project_name) <= 10
    error_message = "Project name must contain only lowercase letters and numbers, max 10 characters."
  }
}

variable "ai_vision_sku" {
  description = "SKU for Azure AI Vision service"
  type        = string
  default     = "S1"
  
  validation {
    condition     = contains(["F0", "S1"], var.ai_vision_sku)
    error_message = "AI Vision SKU must be F0 (free) or S1 (standard)."
  }
}

variable "eventhub_sku" {
  description = "SKU for Event Hubs namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.eventhub_sku)
    error_message = "Event Hub SKU must be Basic, Standard, or Premium."
  }
}

variable "eventhub_capacity" {
  description = "Throughput units for Event Hubs namespace"
  type        = number
  default     = 2
  
  validation {
    condition     = var.eventhub_capacity >= 1 && var.eventhub_capacity <= 20
    error_message = "Event Hub capacity must be between 1 and 20 throughput units."
  }
}

variable "eventhub_partition_count" {
  description = "Number of partitions for the Event Hub"
  type        = number
  default     = 4
  
  validation {
    condition     = var.eventhub_partition_count >= 2 && var.eventhub_partition_count <= 32
    error_message = "Partition count must be between 2 and 32."
  }
}

variable "eventhub_message_retention" {
  description = "Message retention in days for Event Hub"
  type        = number
  default     = 1
  
  validation {
    condition     = var.eventhub_message_retention >= 1 && var.eventhub_message_retention <= 7
    error_message = "Message retention must be between 1 and 7 days."
  }
}

variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be LRS, GRS, RAGRS, or ZRS."
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

variable "content_moderation_thresholds" {
  description = "Thresholds for content moderation decisions"
  type = object({
    adult_block_threshold  = number
    adult_review_threshold = number
    racy_block_threshold   = number
    racy_review_threshold  = number
  })
  default = {
    adult_block_threshold  = 0.7
    adult_review_threshold = 0.5
    racy_block_threshold   = 0.6
    racy_review_threshold  = 0.4
  }
  
  validation {
    condition = alltrue([
      var.content_moderation_thresholds.adult_block_threshold >= 0 && var.content_moderation_thresholds.adult_block_threshold <= 1,
      var.content_moderation_thresholds.adult_review_threshold >= 0 && var.content_moderation_thresholds.adult_review_threshold <= 1,
      var.content_moderation_thresholds.racy_block_threshold >= 0 && var.content_moderation_thresholds.racy_block_threshold <= 1,
      var.content_moderation_thresholds.racy_review_threshold >= 0 && var.content_moderation_thresholds.racy_review_threshold <= 1,
      var.content_moderation_thresholds.adult_block_threshold > var.content_moderation_thresholds.adult_review_threshold,
      var.content_moderation_thresholds.racy_block_threshold > var.content_moderation_thresholds.racy_review_threshold
    ])
    error_message = "All thresholds must be between 0 and 1, and block thresholds must be higher than review thresholds."
  }
}

variable "enable_auto_inflate" {
  description = "Enable auto-inflate for Event Hubs namespace"
  type        = bool
  default     = true
}

variable "maximum_throughput_units" {
  description = "Maximum throughput units for auto-inflate"
  type        = number
  default     = 10
  
  validation {
    condition     = var.maximum_throughput_units >= 1 && var.maximum_throughput_units <= 20
    error_message = "Maximum throughput units must be between 1 and 20."
  }
}

variable "enable_monitoring" {
  description = "Enable Azure Monitor diagnostics and Log Analytics"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Retention period for diagnostic logs in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 730
    error_message = "Log retention must be between 1 and 730 days."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "video-moderation"
    environment = "demo"
    managed_by  = "terraform"
  }
}