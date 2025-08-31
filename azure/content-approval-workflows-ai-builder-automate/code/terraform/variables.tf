# Variables for Content Approval Workflows Infrastructure

variable "resource_group_name" {
  description = "Name of the resource group for content approval resources"
  type        = string
  default     = "rg-content-approval"
}

variable "location" {
  description = "Azure region for resources"
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

variable "tenant_id" {
  description = "Azure AD tenant ID (will be auto-detected if not provided)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "content-approval"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,20}$", var.project_name))
    error_message = "Project name must be alphanumeric with hyphens, 1-20 characters."
  }
}

variable "sharepoint_site_name" {
  description = "SharePoint site name for document library"
  type        = string
  default     = "ContentApprovalWorkflows"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9]{1,64}$", var.sharepoint_site_name))
    error_message = "SharePoint site name must be alphanumeric, 1-64 characters."
  }
}

variable "document_library_name" {
  description = "Name of the SharePoint document library"
  type        = string
  default     = "DocumentsForApproval"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9]{1,64}$", var.document_library_name))
    error_message = "Document library name must be alphanumeric, 1-64 characters."
  }
}

variable "ai_builder_region" {
  description = "Region for AI Builder services (must support Azure OpenAI)"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US 2", "West Europe", "UK South",
      "France Central", "Switzerland North", "Australia East", "Japan East"
    ], var.ai_builder_region)
    error_message = "AI Builder region must support Azure OpenAI Service."
  }
}

variable "approval_workflow_settings" {
  description = "Configuration settings for approval workflows"
  type = object({
    low_risk_auto_approve     = optional(bool, true)
    medium_risk_approval_hours = optional(number, 48)
    high_risk_approval_hours   = optional(number, 24)
    critical_risk_approval_hours = optional(number, 12)
    escalation_enabled        = optional(bool, true)
    escalation_hours          = optional(number, 72)
  })
  default = {
    low_risk_auto_approve     = true
    medium_risk_approval_hours = 48
    high_risk_approval_hours   = 24
    critical_risk_approval_hours = 12
    escalation_enabled        = true
    escalation_hours          = 72
  }
}

variable "teams_integration" {
  description = "Microsoft Teams integration settings"
  type = object({
    enable_adaptive_cards = optional(bool, true)
    enable_channel_notifications = optional(bool, true)
    default_team_name = optional(string, "Content Team")
    notification_channel = optional(string, "approvals")
  })
  default = {
    enable_adaptive_cards = true
    enable_channel_notifications = true
    default_team_name = "Content Team"
    notification_channel = "approvals"
  }
}

variable "security_settings" {
  description = "Security configuration for the solution"
  type = object({
    enable_audit_logging = optional(bool, true)
    enable_data_loss_prevention = optional(bool, true)
    retention_period_days = optional(number, 2555) # 7 years default
    enable_encryption_at_rest = optional(bool, true)
    enable_conditional_access = optional(bool, true)
  })
  default = {
    enable_audit_logging = true
    enable_data_loss_prevention = true
    retention_period_days = 2555
    enable_encryption_at_rest = true
    enable_conditional_access = true
  }
}

variable "power_platform_settings" {
  description = "Power Platform environment configuration"
  type = object({
    environment_display_name = optional(string, "Content Approval Environment")
    environment_description = optional(string, "Environment for intelligent content approval workflows")
    enable_ai_builder = optional(bool, true)
    enable_power_automate_premium = optional(bool, true)
    data_loss_prevention_policy = optional(string, "Business")
  })
  default = {
    environment_display_name = "Content Approval Environment"
    environment_description = "Environment for intelligent content approval workflows"
    enable_ai_builder = true
    enable_power_automate_premium = true
    data_loss_prevention_policy = "Business"
  }
}

variable "monitoring_settings" {
  description = "Monitoring and analytics configuration"
  type = object({
    enable_application_insights = optional(bool, true)
    enable_log_analytics = optional(bool, true)
    log_retention_days = optional(number, 90)
    enable_alerts = optional(bool, true)
    alert_email = optional(string, "")
  })
  default = {
    enable_application_insights = true
    enable_log_analytics = true
    log_retention_days = 90
    enable_alerts = true
    alert_email = ""
  }
}

variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "ContentApproval"
    Owner       = "Platform Team"
    CostCenter  = "IT"
    Workload    = "Collaboration"
  }
}