# Input Variables for Security Posture Assessment Infrastructure
# This file defines all configurable parameters for the security posture assessment solution

variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1)."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "organization_id" {
  description = "Google Cloud Organization ID for Security Command Center configuration"
  type        = string
  validation {
    condition     = can(regex("^[0-9]+$", var.organization_id))
    error_message = "Organization ID must be a numeric string."
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

# Security Configuration Variables
variable "security_posture_template" {
  description = "Security posture template to use for baseline security controls"
  type        = string
  default     = "secure_by_default_essential"
  validation {
    condition = contains([
      "secure_by_default_essential",
      "secure_by_default_standard",
      "secure_by_default_comprehensive"
    ], var.security_posture_template)
    error_message = "Security posture template must be one of the supported Google Cloud templates."
  }
}

variable "security_evaluation_schedule" {
  description = "Cron schedule for automated security evaluations"
  type        = string
  default     = "0 */6 * * *"  # Every 6 hours
  validation {
    condition     = can(regex("^[0-9*/,-]+\\s+[0-9*/,-]+\\s+[0-9*/,-]+\\s+[0-9*/,-]+\\s+[0-9*/,-]+$", var.security_evaluation_schedule))
    error_message = "Security evaluation schedule must be a valid cron expression."
  }
}

variable "enable_critical_alert_notifications" {
  description = "Enable immediate notifications for critical security findings"
  type        = bool
  default     = true
}

# Cloud Function Configuration
variable "function_runtime" {
  description = "Runtime for the security remediation Cloud Function"
  type        = string
  default     = "python39"
  validation {
    condition = contains([
      "python39",
      "python310",
      "python311",
      "nodejs16",
      "nodejs18",
      "nodejs20"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Google Cloud Functions runtime."
  }
}

variable "function_memory_mb" {
  description = "Memory allocation for the security remediation Cloud Function (MB)"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, or 2048 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for the security remediation Cloud Function (seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

# Pub/Sub Configuration
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topic (e.g., 604800s for 7 days)"
  type        = string
  default     = "604800s"
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscription (seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Pub/Sub acknowledgment deadline must be between 10 and 600 seconds."
  }
}

# Storage Configuration
variable "storage_location" {
  description = "Location for Cloud Storage bucket (regional or multi-regional)"
  type        = string
  default     = "US"
}

variable "storage_force_destroy" {
  description = "Allow destruction of non-empty storage bucket (use with caution)"
  type        = bool
  default     = false
}

# Workload Manager Configuration
variable "workload_manager_rules" {
  description = "Custom validation rules for Workload Manager"
  type = map(object({
    description = string
    type        = string
    severity    = string
  }))
  default = {
    "ensure-vm-shielded" = {
      description = "Verify VMs have Shielded VM enabled"
      type        = "COMPUTE_ENGINE"
      severity    = "HIGH"
    }
    "check-storage-encryption" = {
      description = "Ensure Cloud Storage uses customer-managed encryption"
      type        = "CLOUD_STORAGE"
      severity    = "CRITICAL"
    }
    "verify-network-security" = {
      description = "Validate network security configurations"
      type        = "COMPUTE_NETWORK"
      severity    = "HIGH"
    }
  }
}

# Monitoring Configuration
variable "create_monitoring_dashboard" {
  description = "Create Cloud Monitoring dashboard for security metrics"
  type        = bool
  default     = true
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for security alerts"
  type        = list(string)
  default     = []
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "security-posture"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "resource_suffix" {
  description = "Suffix for resource names (leave empty for auto-generated)"
  type        = string
  default     = ""
}

# Tagging and Labeling
variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    component   = "security-posture"
    managed-by  = "terraform"
  }
}

# IAM Configuration
variable "create_custom_service_account" {
  description = "Create a custom service account for security automation"
  type        = bool
  default     = true
}

variable "service_account_roles" {
  description = "List of IAM roles to assign to the security automation service account"
  type        = list(string)
  default = [
    "roles/securitycenter.admin",
    "roles/workloadmanager.admin",
    "roles/cloudfunctions.invoker",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ]
}

# Network Configuration
variable "network_name" {
  description = "Name of the VPC network for resources (leave empty to use default)"
  type        = string
  default     = ""
}

variable "subnet_name" {
  description = "Name of the subnet for resources (leave empty to use default)"
  type        = string
  default     = ""
}

# Cost Management
variable "budget_amount" {
  description = "Budget amount for cost monitoring (set to 0 to disable budget creation)"
  type        = number
  default     = 100
}

variable "budget_threshold_percent" {
  description = "Budget threshold percentage for alerts"
  type        = number
  default     = 80
  validation {
    condition     = var.budget_threshold_percent > 0 && var.budget_threshold_percent <= 100
    error_message = "Budget threshold must be between 1 and 100 percent."
  }
}

# Feature Flags
variable "enable_workload_manager" {
  description = "Enable Workload Manager infrastructure validation"
  type        = bool
  default     = true
}

variable "enable_automated_remediation" {
  description = "Enable automated remediation Cloud Function"
  type        = bool
  default     = true
}

variable "enable_security_monitoring" {
  description = "Enable security monitoring dashboard and alerts"
  type        = bool
  default     = true
}