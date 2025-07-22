# Input Variables for Azure IoT Operations Manufacturing Analytics Solution
# This file defines all configurable parameters for the Terraform deployment

# ==============================================================================
# RESOURCE NAMING AND LOCATION VARIABLES
# ==============================================================================

variable "location" {
  description = "The Azure region where all resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India"
    ], var.location)
    error_message = "Location must be a valid Azure region that supports IoT Operations and Event Hubs."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure resource group to create or use for all resources"
  type        = string
  default     = null
  
  validation {
    condition     = var.resource_group_name == null || length(var.resource_group_name) <= 90
    error_message = "Resource group name must be 90 characters or less."
  }
}

variable "environment" {
  description = "Environment identifier for resource naming and tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "test", "stage", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, test, stage, prod, demo."
  }
}

variable "solution_name" {
  description = "Solution name prefix for resource naming"
  type        = string
  default     = "manufacturing-analytics"
  
  validation {
    condition     = length(var.solution_name) <= 20 && can(regex("^[a-z0-9-]+$", var.solution_name))
    error_message = "Solution name must be 20 characters or less and contain only lowercase letters, numbers, and hyphens."
  }
}

# ==============================================================================
# EVENT HUBS CONFIGURATION VARIABLES
# ==============================================================================

variable "event_hubs_namespace_sku" {
  description = "Pricing tier for Event Hubs namespace (Basic, Standard, Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.event_hubs_namespace_sku)
    error_message = "Event Hubs namespace SKU must be Basic, Standard, or Premium."
  }
}

variable "event_hubs_capacity" {
  description = "Throughput units for Event Hubs namespace (1-20 for Standard, 1-100 for Premium)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.event_hubs_capacity >= 1 && var.event_hubs_capacity <= 100
    error_message = "Event Hubs capacity must be between 1 and 100 throughput units."
  }
}

variable "event_hubs_auto_inflate_enabled" {
  description = "Enable auto-inflate for Event Hubs namespace to handle traffic spikes"
  type        = bool
  default     = true
}

variable "event_hubs_maximum_throughput_units" {
  description = "Maximum throughput units when auto-inflate is enabled"
  type        = number
  default     = 10
  
  validation {
    condition     = var.event_hubs_maximum_throughput_units >= 1 && var.event_hubs_maximum_throughput_units <= 100
    error_message = "Maximum throughput units must be between 1 and 100."
  }
}

variable "telemetry_event_hub_partition_count" {
  description = "Number of partitions for the manufacturing telemetry event hub"
  type        = number
  default     = 4
  
  validation {
    condition     = var.telemetry_event_hub_partition_count >= 1 && var.telemetry_event_hub_partition_count <= 32
    error_message = "Event Hub partition count must be between 1 and 32."
  }
}

variable "telemetry_event_hub_message_retention" {
  description = "Message retention in days for telemetry event hub (1-7 days)"
  type        = number
  default     = 3
  
  validation {
    condition     = var.telemetry_event_hub_message_retention >= 1 && var.telemetry_event_hub_message_retention <= 7
    error_message = "Message retention must be between 1 and 7 days."
  }
}

# ==============================================================================
# STREAM ANALYTICS CONFIGURATION VARIABLES
# ==============================================================================

variable "stream_analytics_sku" {
  description = "SKU for Stream Analytics job (Standard or Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.stream_analytics_sku)
    error_message = "Stream Analytics SKU must be Standard or Premium."
  }
}

variable "stream_analytics_streaming_units" {
  description = "Number of streaming units for Stream Analytics job (1-192)"
  type        = number
  default     = 3
  
  validation {
    condition     = var.stream_analytics_streaming_units >= 1 && var.stream_analytics_streaming_units <= 192
    error_message = "Streaming units must be between 1 and 192."
  }
}

variable "stream_analytics_compatibility_level" {
  description = "Compatibility level for Stream Analytics job (1.0, 1.1, 1.2)"
  type        = string
  default     = "1.2"
  
  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.stream_analytics_compatibility_level)
    error_message = "Compatibility level must be 1.0, 1.1, or 1.2."
  }
}

# ==============================================================================
# LOG ANALYTICS AND MONITORING VARIABLES
# ==============================================================================

variable "log_analytics_sku" {
  description = "Pricing tier for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone", "Standard", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Standalone, Standard, Premium."
  }
}

variable "log_analytics_retention_days" {
  description = "Log retention in days for Log Analytics workspace (30-730 days)"
  type        = number
  default     = 90
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log retention must be between 30 and 730 days."
  }
}

# ==============================================================================
# IOT OPERATIONS CONFIGURATION VARIABLES
# ==============================================================================

variable "enable_iot_operations" {
  description = "Enable Azure IoT Operations deployment (requires Azure Arc-enabled Kubernetes)"
  type        = bool
  default     = false
}

variable "arc_cluster_name" {
  description = "Name of the Azure Arc-enabled Kubernetes cluster for IoT Operations"
  type        = string
  default     = null
}

variable "arc_cluster_resource_group" {
  description = "Resource group containing the Azure Arc-enabled Kubernetes cluster"
  type        = string
  default     = null
}

# ==============================================================================
# SECURITY AND ACCESS CONTROL VARIABLES
# ==============================================================================

variable "enable_managed_identity" {
  description = "Enable system-assigned managed identity for resources"
  type        = bool
  default     = true
}

variable "enable_private_endpoints" {
  description = "Enable private endpoints for secure network access"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of allowed IP address ranges for network access rules"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR notation (e.g., 192.168.1.0/24)."
  }
}

# ==============================================================================
# ALERTING AND NOTIFICATION VARIABLES
# ==============================================================================

variable "enable_alerts" {
  description = "Enable Azure Monitor alerts for manufacturing equipment monitoring"
  type        = bool
  default     = true
}

variable "alert_email_addresses" {
  description = "Email addresses to receive manufacturing equipment alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.alert_email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid email format."
  }
}

variable "alert_phone_numbers" {
  description = "Phone numbers to receive SMS alerts (format: +1234567890)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for phone in var.alert_phone_numbers : can(regex("^\\+[1-9]\\d{1,14}$", phone))
    ])
    error_message = "Phone numbers must be in international format (e.g., +1234567890)."
  }
}

# ==============================================================================
# COST OPTIMIZATION VARIABLES
# ==============================================================================

variable "enable_cost_optimization" {
  description = "Enable cost optimization features like auto-pause and scaling"
  type        = bool
  default     = true
}

variable "auto_pause_delay_minutes" {
  description = "Minutes of inactivity before pausing resources (0 = disabled)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.auto_pause_delay_minutes >= 0 && var.auto_pause_delay_minutes <= 10080
    error_message = "Auto-pause delay must be between 0 and 10080 minutes (7 days)."
  }
}

# ==============================================================================
# ADVANCED CONFIGURATION VARIABLES
# ==============================================================================

variable "custom_tags" {
  description = "Additional custom tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.custom_tags) <= 50
    error_message = "Maximum of 50 custom tags allowed."
  }
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for all applicable resources"
  type        = bool
  default     = true
}

variable "telemetry_sample_rate" {
  description = "Telemetry sampling rate percentage for performance optimization (1-100)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.telemetry_sample_rate >= 1 && var.telemetry_sample_rate <= 100
    error_message = "Telemetry sample rate must be between 1 and 100 percent."
  }
}