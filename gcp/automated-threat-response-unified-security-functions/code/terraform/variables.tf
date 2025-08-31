# Variables for Automated Threat Response Infrastructure
# This file defines all configurable parameters for the security automation system

# Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.region))
    error_message = "Region must be a valid GCP region format."
  }
}

# Security Configuration
variable "security_findings_log_filter" {
  description = "Log filter for Security Command Center findings to trigger automated response"
  type        = string
  default     = "protoPayload.serviceName=\"securitycenter.googleapis.com\" OR jsonPayload.source=\"security-center\" OR jsonPayload.category=\"THREAT_DETECTION\" OR severity>=\"WARNING\""
}

variable "enable_security_command_center" {
  description = "Whether to enable Security Command Center services (requires premium/enterprise subscription)"
  type        = bool
  default     = true
}

# Pub/Sub Configuration
variable "topic_names" {
  description = "Names for Pub/Sub topics used in the threat response system"
  type = object({
    main_topic         = string
    remediation_topic  = string
    notification_topic = string
  })
  default = {
    main_topic         = "threat-response-topic"
    remediation_topic  = "threat-remediation-topic"
    notification_topic = "threat-notification-topic"
  }
}

variable "subscription_names" {
  description = "Names for Pub/Sub subscriptions"
  type = object({
    main_subscription         = string
    remediation_subscription  = string
    notification_subscription = string
  })
  default = {
    main_subscription         = "threat-response-sub"
    remediation_subscription  = "threat-remediation-sub"
    notification_subscription = "threat-notification-sub"
  }
}

variable "message_retention_duration" {
  description = "How long to retain messages in Pub/Sub subscriptions"
  type        = string
  default     = "604800s" # 7 days
}

variable "ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscriptions in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.ack_deadline_seconds >= 10 && var.ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

# Cloud Functions Configuration
variable "function_names" {
  description = "Names for Cloud Functions in the threat response system"
  type = object({
    triage_function       = string
    remediation_function  = string
    notification_function = string
  })
  default = {
    triage_function       = "security-triage"
    remediation_function  = "automated-remediation"
    notification_function = "security-notification"
  }
}

variable "function_runtime" {
  description = "Runtime environment for Cloud Functions"
  type        = string
  default     = "python39"
  validation {
    condition = contains([
      "python37", "python38", "python39", "python310", "python311",
      "nodejs14", "nodejs16", "nodejs18", "nodejs20",
      "go116", "go118", "go119", "go120", "go121",
      "java11", "java17", "java21"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

variable "triage_function_config" {
  description = "Configuration for the security triage function"
  type = object({
    memory_mb     = number
    timeout_s     = number
    max_instances = number
  })
  default = {
    memory_mb     = 512
    timeout_s     = 300
    max_instances = 100
  }
  validation {
    condition     = var.triage_function_config.memory_mb >= 128 && var.triage_function_config.memory_mb <= 8192
    error_message = "Memory allocation must be between 128 MB and 8192 MB."
  }
}

variable "remediation_function_config" {
  description = "Configuration for the automated remediation function"
  type = object({
    memory_mb     = number
    timeout_s     = number
    max_instances = number
  })
  default = {
    memory_mb     = 1024
    timeout_s     = 540
    max_instances = 50
  }
  validation {
    condition     = var.remediation_function_config.memory_mb >= 256 && var.remediation_function_config.memory_mb <= 8192
    error_message = "Memory allocation must be between 256 MB and 8192 MB."
  }
}

variable "notification_function_config" {
  description = "Configuration for the security notification function"
  type = object({
    memory_mb     = number
    timeout_s     = number
    max_instances = number
  })
  default = {
    memory_mb     = 256
    timeout_s     = 60
    max_instances = 200
  }
  validation {
    condition     = var.notification_function_config.memory_mb >= 128 && var.notification_function_config.memory_mb <= 2048
    error_message = "Memory allocation must be between 128 MB and 2048 MB."
  }
}

# Logging Configuration
variable "log_sink_name" {
  description = "Name for the Cloud Logging sink that exports security findings"
  type        = string
  default     = "security-findings-sink"
}

variable "enable_audit_logging" {
  description = "Whether to enable comprehensive audit logging for security operations"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain security logs"
  type        = number
  default     = 90
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 30 and 3653 days."
  }
}

# Monitoring Configuration
variable "enable_monitoring_alerts" {
  description = "Whether to create Cloud Monitoring alert policies for security events"
  type        = bool
  default     = true
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for security alerts"
  type        = list(string)
  default     = []
}

variable "critical_findings_threshold" {
  description = "Threshold for triggering alerts on critical security findings"
  type        = number
  default     = 5
  validation {
    condition     = var.critical_findings_threshold > 0
    error_message = "Critical findings threshold must be greater than 0."
  }
}

# Resource Naming and Tagging
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "security-automation"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "labels" {
  description = "Labels to apply to all resources for organization and cost tracking"
  type        = map(string)
  default = {
    environment = "production"
    purpose     = "security-automation"
    managed-by  = "terraform"
    team        = "security"
  }
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Maximum of 64 labels allowed per resource."
  }
}

# IAM and Security Configuration
variable "create_service_accounts" {
  description = "Whether to create dedicated service accounts for each function"
  type        = bool
  default     = true
}

variable "enable_vpc_connector" {
  description = "Whether to create VPC connector for secure function networking"
  type        = bool
  default     = false
}

variable "allowed_ingress_sources" {
  description = "List of source ranges allowed to invoke functions (when using HTTPS trigger)"
  type        = list(string)
  default     = []
}

# Integration Configuration
variable "slack_webhook_url" {
  description = "Slack webhook URL for security notifications (stored as secret)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "pagerduty_integration_key" {
  description = "PagerDuty integration key for critical alerts (stored as secret)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_external_integrations" {
  description = "Whether to enable integrations with external security tools"
  type        = bool
  default     = false
}

# Development and Testing Configuration
variable "enable_debug_logging" {
  description = "Whether to enable debug-level logging for troubleshooting"
  type        = bool
  default     = false
}

variable "function_source_archive_bucket" {
  description = "Cloud Storage bucket for storing function source code archives"
  type        = string
  default     = ""
}

variable "create_source_bucket" {
  description = "Whether to create a new bucket for function source code"
  type        = bool
  default     = true
}