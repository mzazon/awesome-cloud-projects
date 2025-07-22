# Resource Group Configuration
variable "resource_group_name" {
  description = "Name of the resource group for Arc governance resources"
  type        = string
  default     = "rg-arc-governance"
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

# Log Analytics Workspace Configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for monitoring"
  type        = string
  default     = "law-arc-governance"
}

variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.log_analytics_sku)
    error_message = "Invalid Log Analytics SKU. Must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain log analytics data"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 7 and 730 days."
  }
}

# Arc-enabled Kubernetes Configuration
variable "arc_k8s_cluster_name" {
  description = "Name for the Arc-enabled Kubernetes cluster"
  type        = string
  default     = "arc-k8s-cluster"
}

# Service Principal Configuration
variable "service_principal_name" {
  description = "Name for the service principal used for Arc onboarding"
  type        = string
  default     = "sp-arc-onboarding"
}

# Policy Configuration
variable "enable_arc_servers_baseline" {
  description = "Enable security baseline policy for Arc-enabled servers"
  type        = bool
  default     = true
}

variable "enable_k8s_container_security" {
  description = "Enable container security policy for Arc-enabled Kubernetes"
  type        = bool
  default     = true
}

variable "policy_assignment_enforcement_mode" {
  description = "Enforcement mode for policy assignments"
  type        = string
  default     = "Default"
  
  validation {
    condition     = contains(["Default", "DoNotEnforce"], var.policy_assignment_enforcement_mode)
    error_message = "Policy enforcement mode must be either 'Default' or 'DoNotEnforce'."
  }
}

# Data Collection Rule Configuration
variable "enable_performance_monitoring" {
  description = "Enable performance monitoring for Arc-enabled servers"
  type        = bool
  default     = true
}

variable "performance_counter_sample_rate" {
  description = "Sample rate in seconds for performance counters"
  type        = number
  default     = 60
  
  validation {
    condition     = var.performance_counter_sample_rate >= 15 && var.performance_counter_sample_rate <= 3600
    error_message = "Performance counter sample rate must be between 15 and 3600 seconds."
  }
}

# Tagging Configuration
variable "environment" {
  description = "Environment tag for resources"
  type        = string
  default     = "demo"
}

variable "purpose" {
  description = "Purpose tag for resources"
  type        = string
  default     = "hybrid-governance"
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Monitoring Configuration
variable "enable_azure_monitor_containers" {
  description = "Enable Azure Monitor for Containers on Arc-enabled Kubernetes"
  type        = bool
  default     = true
}

variable "enable_azure_policy_addon" {
  description = "Enable Azure Policy add-on for Arc-enabled Kubernetes"
  type        = bool
  default     = true
}

# Resource Graph Configuration
variable "create_shared_queries" {
  description = "Create shared Resource Graph queries for compliance monitoring"
  type        = bool
  default     = true
}

# Naming Configuration
variable "naming_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "arc"
  
  validation {
    condition     = length(var.naming_prefix) <= 10
    error_message = "Naming prefix must be 10 characters or less."
  }
}

variable "use_random_suffix" {
  description = "Add random suffix to resource names for uniqueness"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_system_assigned_identity" {
  description = "Enable system-assigned managed identity for policy assignments"
  type        = bool
  default     = true
}

variable "create_custom_role_definitions" {
  description = "Create custom role definitions for Arc management"
  type        = bool
  default     = false
}