# Core Configuration Variables
variable "resource_group_name" {
  description = "Name of the resource group for security operations resources"
  type        = string
  default     = "rg-security-ops"
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
      "Norway East", "Switzerland North", "UAE North", "South Africa North",
      "Australia East", "Australia Southeast", "East Asia", "Southeast Asia",
      "Japan East", "Japan West", "Korea Central", "India Central"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

# Log Analytics Workspace Variables
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for security data"
  type        = string
  default     = "law-security"
}

variable "log_analytics_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "PerGB2018", "Standalone"], var.log_analytics_sku)
    error_message = "SKU must be one of: Free, PerNode, PerGB2018, Standalone."
  }
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain log data"
  type        = number
  default     = 90
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Retention days must be between 30 and 730."
  }
}

# Microsoft Sentinel Variables
variable "sentinel_solution_name" {
  description = "Name of the Microsoft Sentinel solution"
  type        = string
  default     = "SecurityInsights"
}

variable "enable_ueba" {
  description = "Enable User and Entity Behavior Analytics (UEBA)"
  type        = bool
  default     = true
}

variable "ueba_data_sources" {
  description = "List of data sources for UEBA"
  type        = list(string)
  default     = ["AuditLogs", "AzureActivity", "SecurityEvent", "SigninLogs"]
}

# Logic Apps Variables
variable "logic_app_name" {
  description = "Name of the Logic App for incident response"
  type        = string
  default     = "la-incident-response"
}

variable "playbook_name" {
  description = "Name of the security playbook Logic App"
  type        = string
  default     = "playbook-user-response"
}

# Data Connectors Configuration
variable "enable_azure_ad_connector" {
  description = "Enable Azure AD data connector"
  type        = bool
  default     = true
}

variable "enable_azure_activity_connector" {
  description = "Enable Azure Activity data connector"
  type        = bool
  default     = true
}

variable "enable_security_events_connector" {
  description = "Enable Security Events data connector"
  type        = bool
  default     = true
}

variable "enable_office365_connector" {
  description = "Enable Office 365 data connector"
  type        = bool
  default     = true
}

# Analytics Rules Configuration
variable "enable_analytics_rules" {
  description = "Enable creation of analytics rules"
  type        = bool
  default     = true
}

variable "analytics_rules_config" {
  description = "Configuration for analytics rules"
  type = object({
    suspicious_signin = object({
      enabled           = bool
      query_frequency   = string
      query_period      = string
      trigger_threshold = number
      severity          = string
    })
    privilege_escalation = object({
      enabled           = bool
      query_frequency   = string
      query_period      = string
      trigger_threshold = number
      severity          = string
    })
  })
  default = {
    suspicious_signin = {
      enabled           = true
      query_frequency   = "PT5M"
      query_period      = "PT5M"
      trigger_threshold = 0
      severity          = "Medium"
    }
    privilege_escalation = {
      enabled           = true
      query_frequency   = "PT10M"
      query_period      = "PT10M"
      trigger_threshold = 0
      severity          = "High"
    }
  }
}

# Automation Configuration
variable "enable_automation" {
  description = "Enable Logic Apps automation"
  type        = bool
  default     = true
}

variable "notification_webhook_url" {
  description = "Webhook URL for high severity notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "logging_endpoint_url" {
  description = "Logging endpoint URL for standard responses (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

# Workbook Configuration
variable "enable_security_workbook" {
  description = "Enable deployment of security operations workbook"
  type        = bool
  default     = true
}

variable "workbook_name" {
  description = "Name of the security operations workbook"
  type        = string
  default     = "Security Operations Dashboard"
}

# Unified Security Operations Configuration
variable "enable_unified_operations" {
  description = "Enable unified security operations platform integration"
  type        = bool
  default     = true
}

variable "enable_defender_connector" {
  description = "Enable Microsoft Defender XDR connector"
  type        = bool
  default     = true
}

variable "defender_lookback_period" {
  description = "Lookback period for Defender threat intelligence"
  type        = string
  default     = "P7D"
}

# Tagging Configuration
variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default = {
    Purpose     = "security-operations"
    Environment = "production"
    Owner       = "security-team"
    Solution    = "unified-security-operations"
  }
}

# Random Suffix Configuration
variable "use_random_suffix" {
  description = "Use random suffix for resource names to ensure uniqueness"
  type        = bool
  default     = true
}

variable "random_suffix_length" {
  description = "Length of random suffix"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 8
    error_message = "Random suffix length must be between 4 and 8."
  }
}

# Security Configuration
variable "enable_private_endpoints" {
  description = "Enable private endpoints for secure connectivity"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources"
  type        = list(string)
  default     = []
}

# Cost Management
variable "enable_cost_alerts" {
  description = "Enable cost monitoring alerts"
  type        = bool
  default     = true
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD for cost monitoring"
  type        = number
  default     = 1000
}