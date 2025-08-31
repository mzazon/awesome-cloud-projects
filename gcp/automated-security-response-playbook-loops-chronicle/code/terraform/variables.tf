# Variables for automated security response with Chronicle SOAR and Playbook Loops

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 6 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must be at least 6 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "organization_id" {
  description = "Google Cloud Organization ID for Security Command Center configuration"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "sec-automation"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "scc_tier" {
  description = "Security Command Center tier (STANDARD or PREMIUM)"
  type        = string
  default     = "PREMIUM"
  validation {
    condition     = contains(["STANDARD", "PREMIUM"], var.scc_tier)
    error_message = "SCC tier must be either STANDARD or PREMIUM."
  }
}

variable "threat_enrichment_function_config" {
  description = "Configuration for the threat enrichment Cloud Function"
  type = object({
    memory_mb         = number
    timeout_seconds   = number
    max_instances     = number
    runtime          = string
    entry_point      = string
  })
  default = {
    memory_mb         = 512
    timeout_seconds   = 300
    max_instances     = 100
    runtime          = "python312"
    entry_point      = "threat_enrichment"
  }
}

variable "automated_response_function_config" {
  description = "Configuration for the automated response Cloud Function"
  type = object({
    memory_mb         = number
    timeout_seconds   = number
    max_instances     = number
    runtime          = string
    entry_point      = string
  })
  default = {
    memory_mb         = 512
    timeout_seconds   = 300
    max_instances     = 50
    runtime          = "python312"
    entry_point      = "automated_response"
  }
}

variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topics (in seconds)"
  type        = string
  default     = "604800s"  # 7 days
}

variable "security_notification_filter" {
  description = "Filter for Security Command Center notifications"
  type        = string
  default     = "state=\"ACTIVE\" AND severity=\"HIGH\""
}

variable "enable_audit_logging" {
  description = "Enable audit logging for security operations"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain audit logs"
  type        = number
  default     = 90
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 30 and 3653 days."
  }
}

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "security-automation"
    managed-by  = "terraform"
    component   = "chronicle-soar-automation"
  }
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for security automation resources"
  type        = bool
  default     = true
}

variable "notification_channels" {
  description = "List of notification channels for alerting"
  type        = list(string)
  default     = []
}

variable "enable_secret_manager" {
  description = "Enable Secret Manager for storing sensitive configuration"
  type        = bool
  default     = true
}

variable "chronicle_soar_config" {
  description = "Chronicle SOAR configuration settings"
  type = object({
    playbook_name              = string
    max_loop_iterations        = number
    reputation_score_threshold = number
    enable_scope_lock         = bool
  })
  default = {
    playbook_name              = "Multi-Entity Threat Response"
    max_loop_iterations        = 100
    reputation_score_threshold = 7
    enable_scope_lock         = true
  }
}