# ==============================================================================
# Variable Definitions for Azure Service Bus Message Queue Infrastructure
# ==============================================================================
# This file defines all input variables used to customize the Service Bus
# deployment. Variables include validation rules and detailed descriptions
# to ensure proper configuration.
# ==============================================================================

# ==============================================================================
# GENERAL CONFIGURATION VARIABLES
# ==============================================================================

variable "resource_group_name" {
  description = "Name of the Azure resource group to create for Service Bus resources"
  type        = string
  default     = "rg-servicebus-messaging"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only letters, numbers, periods, underscores, and hyphens."
  }
}

variable "location" {
  description = "Azure region where Service Bus resources will be deployed"
  type        = string
  default     = "East US"

  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe', "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "Southeast Asia", "East Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India"
    ], var.location)
    error_message = "Location must be a valid Azure region name."
  }
}

variable "common_tags" {
  description = "Common tags to be applied to all resources for consistent resource management"
  type        = map(string)
  default = {
    environment   = "demo"
    project      = "servicebus-messaging"
    managed-by   = "terraform"
    recipe       = "simple-message-queue-service-bus"
  }
}

# ==============================================================================
# SERVICE BUS NAMESPACE CONFIGURATION
# ==============================================================================

variable "servicebus_namespace_name" {
  description = "Name of the Service Bus namespace (must be globally unique across Azure)"
  type        = string
  default     = "sbns-messaging-demo"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{4,49}$", var.servicebus_namespace_name))
    error_message = "Namespace name must be 6-50 characters, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "servicebus_sku" {
  description = "Service Bus namespace pricing tier (Basic, Standard, or Premium)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.servicebus_sku)
    error_message = "SKU must be one of: Basic, Standard, Premium."
  }
}

variable "local_auth_enabled" {
  description = "Enable Shared Access Signature (SAS) authentication for the Service Bus namespace"
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Enable public network access to the Service Bus namespace"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version required for connections to Service Bus"
  type        = string
  default     = "1.2"

  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be 1.0, 1.1, or 1.2."
  }
}

# ==============================================================================
# SERVICE BUS QUEUE CONFIGURATION
# ==============================================================================

variable "queue_name" {
  description = "Name of the Service Bus queue for message processing"
  type        = string
  default     = "orders"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.queue_name)) && length(var.queue_name) <= 260
    error_message = "Queue name must be 1-260 characters and contain only letters, numbers, periods, underscores, and hyphens."
  }
}

variable "default_message_ttl" {
  description = "Default time-to-live for messages in ISO 8601 duration format (e.g., P14D for 14 days)"
  type        = string
  default     = "P14D"

  validation {
    condition     = can(regex("^P([0-9]+D)?(T([0-9]+H)?([0-9]+M)?([0-9]+S)?)?$", var.default_message_ttl))
    error_message = "TTL must be in ISO 8601 duration format (e.g., P14D, PT1H30M)."
  }
}

variable "dead_lettering_on_message_expiration" {
  description = "Enable dead letter queue for expired messages to support error handling and recovery"
  type        = bool
  default     = true
}

variable "max_size_in_megabytes" {
  description = "Maximum queue size in megabytes (1024, 2048, 3072, 4096, 5120)"
  type        = number
  default     = 1024

  validation {
    condition     = contains([1024, 2048, 3072, 4096, 5120], var.max_size_in_megabytes)
    error_message = "Queue size must be one of: 1024, 2048, 3072, 4096, 5120 MB."
  }
}

variable "max_delivery_count" {
  description = "Maximum number of delivery attempts before a message is dead lettered"
  type        = number
  default     = 10

  validation {
    condition     = var.max_delivery_count >= 1 && var.max_delivery_count <= 2000
    error_message = "Max delivery count must be between 1 and 2000."
  }
}

variable "lock_duration" {
  description = "ISO 8601 duration for message lock timeout during processing (max 5 minutes)"
  type        = string
  default     = "PT1M"

  validation {
    condition     = can(regex("^PT([0-4]?[0-9]M|[1-4]M[0-5]?[0-9]S|[1-5]M|[1-9][0-9]?S|[1-2][0-9][0-9]S|300S)$", var.lock_duration))
    error_message = "Lock duration must be between PT30S and PT5M (30 seconds to 5 minutes) in ISO 8601 format."
  }
}

variable "batched_operations_enabled" {
  description = "Enable server-side batched operations for improved message processing throughput"
  type        = bool
  default     = true
}

# ==============================================================================
# ADVANCED QUEUE FEATURES
# ==============================================================================

variable "requires_duplicate_detection" {
  description = "Enable duplicate detection to automatically identify and remove duplicate messages"
  type        = bool
  default     = false
}

variable "duplicate_detection_history_time_window" {
  description = "Time window for duplicate detection in ISO 8601 duration format"
  type        = string
  default     = "PT10M"

  validation {
    condition     = can(regex("^PT([0-9]+M|[0-9]+H|[0-9]+H[0-9]+M)$", var.duplicate_detection_history_time_window))
    error_message = "Duplicate detection window must be in ISO 8601 format (e.g., PT10M, PT1H)."
  }
}

variable "requires_session" {
  description = "Enable message sessions for guaranteed FIFO processing within session groups"
  type        = bool
  default     = false
}

variable "partitioning_enabled" {
  description = "Enable queue partitioning for increased throughput (not available in Basic tier)"
  type        = bool
  default     = false
}

variable "express_enabled" {
  description = "Enable express entities that hold messages in memory (not supported in Premium tier)"
  type        = bool
  default     = false
}

# ==============================================================================
# CAPACITY AND PERFORMANCE VARIABLES
# ==============================================================================

variable "capacity" {
  description = "Messaging units for Premium tier (1, 2, 4, 8, or 16) or 0 for Basic/Standard"
  type        = number
  default     = 0

  validation {
    condition     = var.capacity == 0 || contains([1, 2, 4, 8, 16], var.capacity)
    error_message = "Capacity must be 0 for Basic/Standard or 1, 2, 4, 8, 16 for Premium tier."
  }
}

variable "premium_messaging_partitions" {
  description = "Number of messaging partitions for Premium tier (0, 1, 2, or 4)"
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, 2, 4], var.premium_messaging_partitions)
    error_message = "Premium messaging partitions must be 0, 1, 2, or 4."
  }
}