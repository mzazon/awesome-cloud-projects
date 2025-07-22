# Variable Definitions for Azure Policy and Resource Graph Implementation
# This file defines all configurable parameters for the governance solution

# Basic Configuration Variables
variable "resource_group_name" {
  description = "Name of the resource group for governance resources"
  type        = string
  default     = "rg-governance-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.resource_group_name))
    error_message = "Resource group name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "location" {
  description = "Azure region for deploying resources"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Italy North",
      "Australia East", "Australia Southeast", "East Asia", "Southeast Asia",
      "Japan East", "Japan West", "Korea Central", "India Central",
      "South Africa North", "UAE North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

# Policy Configuration Variables
variable "policy_assignment_scope" {
  description = "Scope for policy assignment (subscription, resource group, or management group)"
  type        = string
  default     = "subscription"
  
  validation {
    condition     = contains(["subscription", "resource_group", "management_group"], var.policy_assignment_scope)
    error_message = "Policy assignment scope must be one of: subscription, resource_group, management_group."
  }
}

variable "policy_enforcement_mode" {
  description = "Policy enforcement mode (Default or DoNotEnforce)"
  type        = string
  default     = "Default"
  
  validation {
    condition     = contains(["Default", "DoNotEnforce"], var.policy_enforcement_mode)
    error_message = "Policy enforcement mode must be either 'Default' or 'DoNotEnforce'."
  }
}

variable "required_tags" {
  description = "List of required tags that must be present on resources"
  type        = list(string)
  default     = ["Department", "Environment", "CostCenter"]
  
  validation {
    condition     = length(var.required_tags) > 0
    error_message = "At least one required tag must be specified."
  }
}

variable "excluded_resource_types" {
  description = "List of resource types to exclude from tagging requirements"
  type        = list(string)
  default = [
    "Microsoft.Network/networkSecurityGroups",
    "Microsoft.Network/routeTables",
    "Microsoft.Network/networkInterfaces",
    "Microsoft.Storage/storageAccounts/blobServices",
    "Microsoft.Storage/storageAccounts/fileServices",
    "Microsoft.Storage/storageAccounts/queueServices",
    "Microsoft.Storage/storageAccounts/tableServices"
  ]
}

# Monitoring Configuration Variables
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for compliance monitoring"
  type        = string
  default     = null
  
  validation {
    condition = var.log_analytics_workspace_name == null || can(regex("^[a-zA-Z0-9-]+$", var.log_analytics_workspace_name))
    error_message = "Log Analytics workspace name must contain only alphanumeric characters and hyphens."
  }
}

variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerGB2018", "PerNode", "Premium", "Standard", "Standalone"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, PerGB2018, PerNode, Premium, Standard, Standalone."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 7 and 730."
  }
}

variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts for policy violations"
  type        = bool
  default     = true
}

variable "alert_frequency_minutes" {
  description = "Frequency in minutes for policy violation alerts"
  type        = number
  default     = 5
  
  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.alert_frequency_minutes)
    error_message = "Alert frequency must be one of: 1, 5, 10, 15, 30, 60 minutes."
  }
}

variable "alert_window_size_minutes" {
  description = "Time window in minutes for policy violation alerts"
  type        = number
  default     = 15
  
  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.alert_window_size_minutes)
    error_message = "Alert window size must be one of: 1, 5, 10, 15, 30, 60 minutes."
  }
}

variable "alert_severity" {
  description = "Severity level for policy violation alerts (0-4)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alert_severity >= 0 && var.alert_severity <= 4
    error_message = "Alert severity must be between 0 (Critical) and 4 (Verbose)."
  }
}

# Automation Configuration Variables
variable "enable_automation_account" {
  description = "Enable Azure Automation Account for remediation workflows"
  type        = bool
  default     = true
}

variable "automation_account_sku" {
  description = "SKU for Azure Automation Account"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Free", "Basic"], var.automation_account_sku)
    error_message = "Automation Account SKU must be either 'Free' or 'Basic'."
  }
}

variable "enable_remediation_tasks" {
  description = "Enable automatic remediation tasks for policy violations"
  type        = bool
  default     = true
}

variable "remediation_mode" {
  description = "Remediation mode for policy violations (ReEvaluateCompliance or ExistingNonCompliant)"
  type        = string
  default     = "ExistingNonCompliant"
  
  validation {
    condition     = contains(["ReEvaluateCompliance", "ExistingNonCompliant"], var.remediation_mode)
    error_message = "Remediation mode must be either 'ReEvaluateCompliance' or 'ExistingNonCompliant'."
  }
}

# Dashboard Configuration Variables
variable "enable_dashboard" {
  description = "Create Azure Dashboard for compliance monitoring"
  type        = bool
  default     = true
}

variable "dashboard_name" {
  description = "Name for the compliance monitoring dashboard"
  type        = string
  default     = "tag-compliance-dashboard"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.dashboard_name))
    error_message = "Dashboard name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# Tagging Variables
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "Governance"
    Environment = "Demo"
    ManagedBy   = "Terraform"
    Solution    = "Azure Policy and Resource Graph"
  }
}

variable "cost_center_tag" {
  description = "Default cost center tag value for resource group inheritance"
  type        = string
  default     = "IT-Governance"
}

# Advanced Configuration Variables
variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for policy evaluation logs"
  type        = bool
  default     = true
}

variable "enable_resource_graph_queries" {
  description = "Create saved Resource Graph queries for compliance monitoring"
  type        = bool
  default     = true
}

variable "policy_definition_mode" {
  description = "Mode for policy definitions (All, Indexed, or NotSpecified)"
  type        = string
  default     = "Indexed"
  
  validation {
    condition     = contains(["All", "Indexed", "NotSpecified"], var.policy_definition_mode)
    error_message = "Policy definition mode must be one of: All, Indexed, NotSpecified."
  }
}

variable "management_group_id" {
  description = "Management group ID for policy assignment (when scope is management_group)"
  type        = string
  default     = null
}

variable "custom_policy_names" {
  description = "Custom names for policy definitions"
  type = object({
    require_department_tag    = optional(string, "require-department-tag")
    require_environment_tag   = optional(string, "require-environment-tag")
    inherit_costcenter_tag   = optional(string, "inherit-costcenter-tag")
    policy_initiative        = optional(string, "mandatory-tagging-initiative")
  })
  default = {}
}