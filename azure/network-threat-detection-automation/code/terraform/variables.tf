# Variables for Azure Network Threat Detection Infrastructure

# Basic Configuration Variables
variable "resource_group_name" {
  description = "Name of the resource group for network threat detection resources"
  type        = string
  default     = "rg-network-threat-detection"
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Performance tier of the storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication type for the storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_account_replication_type)
    error_message = "Storage account replication type must be one of: LRS, GRS, RAGRS, ZRS."
  }
}

variable "storage_account_access_tier" {
  description = "Access tier for the storage account"
  type        = string
  default     = "Hot"
  
  validation {
    condition = contains(["Hot", "Cool"], var.storage_account_access_tier)
    error_message = "Storage account access tier must be either Hot or Cool."
  }
}

# Log Analytics Configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition = contains(["Free", "PerNode", "PerGB2018", "Premium"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerNode, PerGB2018, Premium."
  }
}

variable "log_analytics_retention_in_days" {
  description = "Log Analytics workspace data retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = var.log_analytics_retention_in_days >= 30 && var.log_analytics_retention_in_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

# Network Security Group Configuration
variable "create_demo_nsg" {
  description = "Whether to create a demo Network Security Group for testing"
  type        = bool
  default     = true
}

variable "demo_nsg_name" {
  description = "Name for the demo Network Security Group"
  type        = string
  default     = "nsg-demo-threat-detection"
}

# NSG Flow Logs Configuration
variable "flow_logs_retention_policy_days" {
  description = "Number of days to retain flow logs"
  type        = number
  default     = 7
  
  validation {
    condition = var.flow_logs_retention_policy_days >= 1 && var.flow_logs_retention_policy_days <= 365
    error_message = "Flow logs retention must be between 1 and 365 days."
  }
}

variable "flow_logs_traffic_analytics_interval" {
  description = "Traffic analytics processing interval in minutes"
  type        = number
  default     = 60
  
  validation {
    condition = contains([10, 60], var.flow_logs_traffic_analytics_interval)
    error_message = "Traffic analytics interval must be either 10 or 60 minutes."
  }
}

# Alert Rules Configuration
variable "port_scan_threshold" {
  description = "Threshold for port scanning detection (number of unique ports)"
  type        = number
  default     = 20
  
  validation {
    condition = var.port_scan_threshold >= 5 && var.port_scan_threshold <= 100
    error_message = "Port scan threshold must be between 5 and 100."
  }
}

variable "port_scan_flow_count_threshold" {
  description = "Threshold for port scanning flow count"
  type        = number
  default     = 50
  
  validation {
    condition = var.port_scan_flow_count_threshold >= 10 && var.port_scan_flow_count_threshold <= 1000
    error_message = "Port scan flow count threshold must be between 10 and 1000."
  }
}

variable "data_exfiltration_threshold_bytes" {
  description = "Threshold for data exfiltration detection in bytes"
  type        = number
  default     = 1000000000  # 1GB
  
  validation {
    condition = var.data_exfiltration_threshold_bytes >= 100000000  # 100MB
    error_message = "Data exfiltration threshold must be at least 100MB."
  }
}

variable "failed_connection_threshold" {
  description = "Threshold for failed connection attempts"
  type        = number
  default     = 100
  
  validation {
    condition = var.failed_connection_threshold >= 10 && var.failed_connection_threshold <= 1000
    error_message = "Failed connection threshold must be between 10 and 1000."
  }
}

# Logic Apps Configuration
variable "security_team_email" {
  description = "Email address for security team notifications"
  type        = string
  default     = "security-team@company.com"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.security_team_email))
    error_message = "Security team email must be a valid email address."
  }
}

variable "enable_logic_apps" {
  description = "Whether to create Logic Apps for automated response"
  type        = bool
  default     = true
}

# Monitoring and Alerting Configuration
variable "enable_workbook_dashboard" {
  description = "Whether to create Azure Monitor Workbook dashboard"
  type        = bool
  default     = true
}

variable "alert_evaluation_frequency" {
  description = "Frequency for evaluating alert rules (in minutes)"
  type        = number
  default     = 5
  
  validation {
    condition = contains([1, 5, 10, 15, 30, 60], var.alert_evaluation_frequency)
    error_message = "Alert evaluation frequency must be one of: 1, 5, 10, 15, 30, 60 minutes."
  }
}

variable "alert_window_size" {
  description = "Time window for alert evaluation (in minutes)"
  type        = number
  default     = 60
  
  validation {
    condition = contains([5, 10, 15, 30, 60, 120, 240, 360, 720, 1440], var.alert_window_size)
    error_message = "Alert window size must be one of: 5, 10, 15, 30, 60, 120, 240, 360, 720, 1440 minutes."
  }
}

# Tagging Configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

# Network Watcher Configuration
variable "network_watcher_resource_group_name" {
  description = "Name of the resource group containing Network Watcher"
  type        = string
  default     = "NetworkWatcherRG"
}

variable "network_watcher_name" {
  description = "Name of the Network Watcher instance"
  type        = string
  default     = null  # Will be computed based on location
}