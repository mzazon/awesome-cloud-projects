# Core Configuration Variables
variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-content-processing"
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
  description = "Name of the project for resource naming"
  type        = string
  default     = "content-processing"
}

# Cognitive Services Configuration
variable "cognitive_services_sku" {
  description = "SKU for Cognitive Services Language resource"
  type        = string
  default     = "S"
  
  validation {
    condition     = contains(["F0", "S"], var.cognitive_services_sku)
    error_message = "Cognitive Services SKU must be F0 (free) or S (standard)."
  }
}

# Event Hub Configuration
variable "event_hub_sku" {
  description = "SKU for Event Hub namespace"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.event_hub_sku)
    error_message = "Event Hub SKU must be Basic, Standard, or Premium."
  }
}

variable "event_hub_capacity" {
  description = "Throughput units for Event Hub"
  type        = number
  default     = 1
  
  validation {
    condition     = var.event_hub_capacity >= 1 && var.event_hub_capacity <= 20
    error_message = "Event Hub capacity must be between 1 and 20."
  }
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
  default     = 7
  
  validation {
    condition     = var.event_hub_message_retention >= 1 && var.event_hub_message_retention <= 7
    error_message = "Message retention must be between 1 and 7 days."
  }
}

variable "event_hub_auto_inflate_enabled" {
  description = "Enable auto-inflate for Event Hub"
  type        = bool
  default     = true
}

variable "event_hub_maximum_throughput_units" {
  description = "Maximum throughput units for auto-inflate"
  type        = number
  default     = 10
  
  validation {
    condition     = var.event_hub_maximum_throughput_units >= 1 && var.event_hub_maximum_throughput_units <= 20
    error_message = "Maximum throughput units must be between 1 and 20."
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
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_account_replication_type)
    error_message = "Storage replication type must be LRS, GRS, RAGRS, or ZRS."
  }
}

variable "storage_account_access_tier" {
  description = "Access tier for storage account"
  type        = string
  default     = "Hot"
  
  validation {
    condition     = contains(["Hot", "Cool"], var.storage_account_access_tier)
    error_message = "Storage access tier must be Hot or Cool."
  }
}

# Logic App Configuration
variable "logic_app_enabled" {
  description = "Enable Logic App creation"
  type        = bool
  default     = true
}

# Alert Configuration
variable "alert_email" {
  description = "Email address for negative sentiment alerts"
  type        = string
  default     = "admin@company.com"
}

# Tagging Configuration
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "content-processing"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# Random Suffix Configuration
variable "use_random_suffix" {
  description = "Use random suffix for globally unique resource names"
  type        = bool
  default     = true
}