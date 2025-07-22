# ==============================================================================
# Variables for GuardDuty Threat Detection Infrastructure
# ==============================================================================

# ==============================================================================
# General Configuration
# ==============================================================================

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "guardduty-threat-detection"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    Project     = "GuardDuty Threat Detection"
    Terraform   = "true"
    Purpose     = "Security Monitoring"
  }
}

# ==============================================================================
# GuardDuty Configuration
# ==============================================================================

variable "finding_publishing_frequency" {
  description = "Frequency for publishing findings to CloudWatch Events"
  type        = string
  default     = "FIFTEEN_MINUTES"
  
  validation {
    condition = contains([
      "FIFTEEN_MINUTES", 
      "ONE_HOUR", 
      "SIX_HOURS"
    ], var.finding_publishing_frequency)
    error_message = "Finding publishing frequency must be one of: FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS."
  }
}

variable "enable_kubernetes_protection" {
  description = "Enable GuardDuty Kubernetes audit logs monitoring"
  type        = bool
  default     = true
}

variable "enable_s3_protection" {
  description = "Enable GuardDuty S3 protection for data access monitoring"
  type        = bool
  default     = true
}

variable "enable_malware_protection" {
  description = "Enable GuardDuty malware protection for EC2 instances"
  type        = bool
  default     = true
}

# ==============================================================================
# S3 Configuration for Findings Export
# ==============================================================================

variable "enable_s3_export" {
  description = "Enable exporting GuardDuty findings to S3"
  type        = bool
  default     = true
}

variable "enable_findings_lifecycle" {
  description = "Enable S3 lifecycle policy for findings retention management"
  type        = bool
  default     = true
}

variable "findings_retention_days" {
  description = "Number of days to retain GuardDuty findings in S3 before deletion"
  type        = number
  default     = 2555  # 7 years for compliance
  
  validation {
    condition     = var.findings_retention_days >= 1 && var.findings_retention_days <= 3650
    error_message = "Findings retention days must be between 1 and 3650 (10 years)."
  }
}

# ==============================================================================
# SNS Configuration for Alerting
# ==============================================================================

variable "notification_email" {
  description = "Email address to receive GuardDuty alerts (leave empty to skip email subscription)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "If provided, notification_email must be a valid email address."
  }
}

variable "enable_sns_encryption" {
  description = "Enable KMS encryption for SNS topic"
  type        = bool
  default     = true
}

# ==============================================================================
# EventBridge and Alerting Configuration
# ==============================================================================

variable "alert_severity_levels" {
  description = "List of GuardDuty severity levels that should trigger alerts"
  type        = list(number)
  default     = [4.0, 7.0, 8.0]  # Medium, High, and Critical findings
  
  validation {
    condition = alltrue([
      for level in var.alert_severity_levels : 
      level >= 0.1 && level <= 8.9
    ])
    error_message = "Severity levels must be between 0.1 and 8.9."
  }
}

# ==============================================================================
# CloudWatch Configuration
# ==============================================================================

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for proactive monitoring"
  type        = bool
  default     = true
}

variable "high_finding_threshold" {
  description = "Threshold for high number of findings alarm"
  type        = number
  default     = 10
  
  validation {
    condition     = var.high_finding_threshold >= 1 && var.high_finding_threshold <= 100
    error_message = "High finding threshold must be between 1 and 100."
  }
}

variable "dashboard_severity_filter" {
  description = "Minimum severity level to display in CloudWatch dashboard"
  type        = number
  default     = 4.0
  
  validation {
    condition     = var.dashboard_severity_filter >= 0.1 && var.dashboard_severity_filter <= 8.9
    error_message = "Dashboard severity filter must be between 0.1 and 8.9."
  }
}

# ==============================================================================
# Custom Threat Intelligence Configuration
# ==============================================================================

variable "enable_custom_threat_intel" {
  description = "Enable custom threat intelligence set"
  type        = bool
  default     = false
}

variable "threat_intel_set_location" {
  description = "S3 URI for custom threat intelligence set file (must be in same region as GuardDuty)"
  type        = string
  default     = ""
  
  validation {
    condition = var.threat_intel_set_location == "" || can(regex("^s3://[a-z0-9.-]+/.+", var.threat_intel_set_location))
    error_message = "If provided, threat_intel_set_location must be a valid S3 URI."
  }
}

variable "threat_intel_set_format" {
  description = "Format of the threat intelligence set file"
  type        = string
  default     = "TXT"
  
  validation {
    condition     = contains(["TXT", "STIX", "OTX_CSV", "ALIEN_VAULT", "PROOF_POINT", "FIRE_EYE"], var.threat_intel_set_format)
    error_message = "Threat intel set format must be one of: TXT, STIX, OTX_CSV, ALIEN_VAULT, PROOF_POINT, FIRE_EYE."
  }
}

# ==============================================================================
# Trusted IP Set Configuration
# ==============================================================================

variable "enable_trusted_ip_set" {
  description = "Enable trusted IP set to reduce false positives"
  type        = bool
  default     = false
}

variable "trusted_ip_set_location" {
  description = "S3 URI for trusted IP set file (must be in same region as GuardDuty)"
  type        = string
  default     = ""
  
  validation {
    condition = var.trusted_ip_set_location == "" || can(regex("^s3://[a-z0-9.-]+/.+", var.trusted_ip_set_location))
    error_message = "If provided, trusted_ip_set_location must be a valid S3 URI."
  }
}

# ==============================================================================
# Advanced Configuration Options
# ==============================================================================

variable "enable_data_source_protection" {
  description = "Map of data source protection settings"
  type = object({
    s3_logs                = optional(bool, true)
    kubernetes_audit_logs  = optional(bool, true)
    malware_protection     = optional(bool, true)
  })
  default = {
    s3_logs                = true
    kubernetes_audit_logs  = true
    malware_protection     = true
  }
}

variable "notification_endpoints" {
  description = "List of additional notification endpoints"
  type = list(object({
    protocol = string
    endpoint = string
  }))
  default = []
  
  validation {
    condition = alltrue([
      for endpoint in var.notification_endpoints :
      contains(["email", "sms", "http", "https", "sqs", "lambda"], endpoint.protocol)
    ])
    error_message = "Notification protocol must be one of: email, sms, http, https, sqs, lambda."
  }
}

variable "custom_dashboard_widgets" {
  description = "Additional custom widgets for the CloudWatch dashboard"
  type        = any
  default     = []
}

variable "alarm_actions" {
  description = "List of ARNs to notify when CloudWatch alarms change state"
  type        = list(string)
  default     = []
}

# ==============================================================================
# Multi-Account Configuration
# ==============================================================================

variable "enable_organization_config" {
  description = "Enable GuardDuty for AWS Organizations (requires appropriate permissions)"
  type        = bool
  default     = false
}

variable "auto_enable_organization_members" {
  description = "Automatically enable GuardDuty for new organization members"
  type        = string
  default     = "NONE"
  
  validation {
    condition     = contains(["ALL", "NEW", "NONE"], var.auto_enable_organization_members)
    error_message = "Auto enable organization members must be one of: ALL, NEW, NONE."
  }
}

variable "member_accounts" {
  description = "List of member accounts to invite to GuardDuty"
  type = list(object({
    account_id = string
    email      = string
  }))
  default = []
}

# ==============================================================================
# Cost Optimization Settings
# ==============================================================================

variable "data_source_configurations" {
  description = "Configuration for GuardDuty data sources to optimize costs"
  type = object({
    cloudtrail = optional(object({
      enable = optional(bool, true)
    }), {})
    dns_logs = optional(object({
      enable = optional(bool, true)
    }), {})
    flow_logs = optional(object({
      enable = optional(bool, true)
    }), {})
    s3_logs = optional(object({
      enable = optional(bool, true)
    }), {})
  })
  default = {
    cloudtrail = { enable = true }
    dns_logs   = { enable = true }
    flow_logs  = { enable = true }
    s3_logs    = { enable = true }
  }
}

variable "finding_publishing_criteria" {
  description = "Criteria for publishing findings to CloudWatch Events"
  type = object({
    criterion = optional(map(object({
      eq           = optional(list(string))
      neq          = optional(list(string))
      gt           = optional(number)
      gte          = optional(number)
      lt           = optional(number)
      lte          = optional(number)
    })), {})
  })
  default = {
    criterion = {
      severity = {
        gte = 4.0  # Only publish medium, high, and critical findings
      }
    }
  }
}