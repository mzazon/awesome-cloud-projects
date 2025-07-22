# ===============================================
# Variables for Azure Governance Dashboard Infrastructure
# ===============================================
# This file defines all configurable parameters for the governance
# dashboard solution, allowing customization for different environments
# and organizational requirements.

# ===============================================
# General Configuration
# ===============================================

variable "resource_group_name" {
  description = "Name of the resource group for governance dashboard resources"
  type        = string
  default     = "rg-governance-dashboard"

  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
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
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "West Europe", "North Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Australia East",
      "Australia Southeast", "East Asia", "Southeast Asia", "Japan East",
      "Japan West", "Korea Central", "South India", "Central India"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    Project     = "governance-dashboard"
    ManagedBy   = "terraform"
    Purpose     = "compliance-monitoring"
  }
}

# ===============================================
# Log Analytics Workspace Configuration
# ===============================================

variable "workspace_name_prefix" {
  description = "Prefix for the Log Analytics workspace name"
  type        = string
  default     = "governance-workspace"

  validation {
    condition     = length(var.workspace_name_prefix) >= 4 && length(var.workspace_name_prefix) <= 58
    error_message = "Workspace name prefix must be between 4 and 58 characters to allow for suffix."
  }
}

variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"

  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.log_analytics_sku)
    error_message = "Log Analytics SKU must be one of: Free, Standalone, PerNode, PerGB2018."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in the workspace"
  type        = number
  default     = 30

  validation {
    condition     = var.log_analytics_retention_days >= 7 && var.log_analytics_retention_days <= 730
    error_message = "Log retention must be between 7 and 730 days."
  }
}

# ===============================================
# Monitor Workbook Configuration
# ===============================================

variable "workbook_name_prefix" {
  description = "Prefix for the Azure Monitor Workbook name"
  type        = string
  default     = "governance-dashboard"

  validation {
    condition     = length(var.workbook_name_prefix) >= 3 && length(var.workbook_name_prefix) <= 54
    error_message = "Workbook name prefix must be between 3 and 54 characters to allow for suffix."
  }
}

variable "workbook_display_name" {
  description = "Display name for the governance dashboard workbook"
  type        = string
  default     = "Azure Governance & Compliance Dashboard"

  validation {
    condition     = length(var.workbook_display_name) >= 1 && length(var.workbook_display_name) <= 100
    error_message = "Workbook display name must be between 1 and 100 characters."
  }
}

variable "workbook_description" {
  description = "Description for the governance dashboard workbook"
  type        = string
  default     = "Comprehensive governance dashboard providing real-time visibility into Azure resource compliance, policy violations, and security posture across multiple subscriptions."

  validation {
    condition     = length(var.workbook_description) <= 500
    error_message = "Workbook description must be 500 characters or less."
  }
}

# ===============================================
# Logic App Configuration
# ===============================================

variable "logic_app_name_prefix" {
  description = "Prefix for the Logic App workflow name"
  type        = string
  default     = "governance-automation"

  validation {
    condition     = length(var.logic_app_name_prefix) >= 3 && length(var.logic_app_name_prefix) <= 54
    error_message = "Logic App name prefix must be between 3 and 54 characters to allow for suffix."
  }
}

variable "notification_webhook_url" {
  description = "Webhook URL for sending governance alert notifications (e.g., Slack, Teams, or custom endpoint)"
  type        = string
  default     = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

  validation {
    condition     = can(regex("^https://", var.notification_webhook_url))
    error_message = "Notification webhook URL must be a valid HTTPS URL."
  }
}

# ===============================================
# Alert Configuration
# ===============================================

variable "action_group_name_prefix" {
  description = "Prefix for the Azure Monitor Action Group name"
  type        = string
  default     = "governance-alerts"

  validation {
    condition     = length(var.action_group_name_prefix) >= 3 && length(var.action_group_name_prefix) <= 54
    error_message = "Action group name prefix must be between 3 and 54 characters to allow for suffix."
  }
}

variable "alert_rule_name_prefix" {
  description = "Prefix for the Azure Monitor Alert Rule names"
  type        = string
  default     = "governance-alert"

  validation {
    condition     = length(var.alert_rule_name_prefix) >= 3 && length(var.alert_rule_name_prefix) <= 40
    error_message = "Alert rule name prefix must be between 3 and 40 characters to allow for suffix."
  }
}

variable "alert_email_addresses" {
  description = "List of email addresses to receive governance alerts"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for email in var.alert_email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid email format."
  }
}

variable "enable_governance_alerts" {
  description = "Enable or disable governance monitoring alerts"
  type        = bool
  default     = true
}

# ===============================================
# Governance Policy Configuration
# ===============================================

variable "required_tags" {
  description = "List of tags that must be present on all resources"
  type        = list(string)
  default     = ["Environment", "Owner", "CostCenter"]

  validation {
    condition     = length(var.required_tags) > 0 && length(var.required_tags) <= 10
    error_message = "Required tags list must contain between 1 and 10 tag names."
  }
}

variable "allowed_locations" {
  description = "List of Azure regions where resources are allowed to be deployed"
  type        = list(string)
  default     = ["East US", "West US", "Central US"]

  validation {
    condition     = length(var.allowed_locations) > 0 && length(var.allowed_locations) <= 50
    error_message = "Allowed locations list must contain between 1 and 50 locations."
  }
}

variable "policy_assignment_name_prefix" {
  description = "Prefix for Azure Policy assignment names"
  type        = string
  default     = "governance-policy"

  validation {
    condition     = length(var.policy_assignment_name_prefix) >= 3 && length(var.policy_assignment_name_prefix) <= 50
    error_message = "Policy assignment name prefix must be between 3 and 50 characters."
  }
}

variable "policy_enforcement_mode" {
  description = "Enforcement mode for Azure Policy assignments"
  type        = string
  default     = "Default"

  validation {
    condition     = contains(["Default", "DoNotEnforce"], var.policy_enforcement_mode)
    error_message = "Policy enforcement mode must be either 'Default' or 'DoNotEnforce'."
  }
}

# ===============================================
# Data Collection Configuration
# ===============================================

variable "dcr_name_prefix" {
  description = "Prefix for the Data Collection Rule name"
  type        = string
  default     = "governance-dcr"

  validation {
    condition     = length(var.dcr_name_prefix) >= 3 && length(var.dcr_name_prefix) <= 54
    error_message = "DCR name prefix must be between 3 and 54 characters to allow for suffix."
  }
}

# ===============================================
# Advanced Configuration
# ===============================================

variable "enable_advanced_security_monitoring" {
  description = "Enable advanced security monitoring features including Microsoft Defender for Cloud integration"
  type        = bool
  default     = false
}

variable "enable_cost_monitoring" {
  description = "Enable cost monitoring and budgeting alerts for governance resources"
  type        = bool
  default     = false
}

variable "governance_scope" {
  description = "Scope for governance monitoring (subscription, management-group, or resource-group)"
  type        = string
  default     = "subscription"

  validation {
    condition     = contains(["subscription", "management-group", "resource-group"], var.governance_scope)
    error_message = "Governance scope must be one of: subscription, management-group, resource-group."
  }
}

variable "custom_workbook_queries" {
  description = "Custom KQL queries to add to the governance workbook"
  type = map(object({
    title         = string
    query         = string
    visualization = string
    description   = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for query in var.custom_workbook_queries :
      contains(["table", "piechart", "barchart", "linechart", "scatterchart", "grid"], query.visualization)
    ])
    error_message = "Visualization type must be one of: table, piechart, barchart, linechart, scatterchart, grid."
  }
}

variable "automation_schedule" {
  description = "Schedule for automated governance checks and reporting"
  type = object({
    frequency = string
    interval  = number
    time_zone = optional(string, "UTC")
  })
  default = {
    frequency = "Hour"
    interval  = 1
    time_zone = "UTC"
  }

  validation {
    condition     = contains(["Minute", "Hour", "Day", "Week", "Month"], var.automation_schedule.frequency)
    error_message = "Automation schedule frequency must be one of: Minute, Hour, Day, Week, Month."
  }

  validation {
    condition     = var.automation_schedule.interval >= 1 && var.automation_schedule.interval <= 1000
    error_message = "Automation schedule interval must be between 1 and 1000."
  }
}

# ===============================================
# Security Configuration
# ===============================================

variable "enable_private_endpoints" {
  description = "Enable private endpoints for secure connectivity to Azure services"
  type        = bool
  default     = false
}

variable "network_access_tier" {
  description = "Network access configuration for Log Analytics workspace"
  type        = string
  default     = "Enabled"

  validation {
    condition     = contains(["Enabled", "Disabled"], var.network_access_tier)
    error_message = "Network access tier must be either 'Enabled' or 'Disabled'."
  }
}

variable "enable_managed_identity" {
  description = "Enable managed identity for Logic App authentication"
  type        = bool
  default     = true
}

# ===============================================
# Compliance Framework Configuration
# ===============================================

variable "compliance_frameworks" {
  description = "Compliance frameworks to monitor (e.g., SOX, HIPAA, PCI-DSS, GDPR)"
  type        = list(string)
  default     = ["Azure Security Benchmark"]

  validation {
    condition = alltrue([
      for framework in var.compliance_frameworks :
      contains([
        "Azure Security Benchmark",
        "NIST SP 800-53",
        "ISO 27001",
        "SOX",
        "HIPAA",
        "PCI-DSS",
        "GDPR",
        "FedRAMP",
        "CIS Controls"
      ], framework)
    ])
    error_message = "Compliance framework must be from the supported list."
  }
}