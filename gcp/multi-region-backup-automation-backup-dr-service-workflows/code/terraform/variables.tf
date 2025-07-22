# Variables for GCP Multi-Region Backup Automation Infrastructure
# These variables allow customization of the backup automation deployment

# Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

# Regional Configuration
variable "primary_region" {
  description = "Primary region for backup operations and workflow deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.primary_region))
    error_message = "Primary region must be a valid GCP region (e.g., us-central1)."
  }
}

variable "secondary_region" {
  description = "Secondary region for cross-region backup replication"
  type        = string
  default     = "us-east1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.secondary_region))
    error_message = "Secondary region must be a valid GCP region (e.g., us-east1)."
  }
}

# Backup Configuration
variable "backup_retention_days" {
  description = "Minimum enforced retention duration for backups in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 1 and 365 days."
  }
}

variable "backup_vault_access_restriction" {
  description = "Access restriction level for backup vaults"
  type        = string
  default     = "WITHIN_ORGANIZATION"
  
  validation {
    condition = contains([
      "ACCESS_RESTRICTION_UNSPECIFIED",
      "WITHIN_PROJECT", 
      "WITHIN_ORGANIZATION",
      "UNRESTRICTED",
      "WITHIN_ORG_BUT_UNRESTRICTED_FOR_BA"
    ], var.backup_vault_access_restriction)
    error_message = "Invalid access restriction. Must be one of: ACCESS_RESTRICTION_UNSPECIFIED, WITHIN_PROJECT, WITHIN_ORGANIZATION, UNRESTRICTED, WITHIN_ORG_BUT_UNRESTRICTED_FOR_BA."
  }
}

# Workflow Scheduling Configuration
variable "backup_schedule" {
  description = "Cron schedule for automated backup execution (default: daily at 2 AM)"
  type        = string
  default     = "0 2 * * *"
  
  validation {
    condition = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.backup_schedule))
    error_message = "Backup schedule must be a valid cron expression (e.g., '0 2 * * *')."
  }
}

variable "validation_schedule" {
  description = "Cron schedule for backup validation runs (default: weekly on Sunday at 3 AM)"
  type        = string
  default     = "0 3 * * 0"
  
  validation {
    condition = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.validation_schedule))
    error_message = "Validation schedule must be a valid cron expression (e.g., '0 3 * * 0')."
  }
}

variable "schedule_timezone" {
  description = "Timezone for backup and validation schedules"
  type        = string
  default     = "America/New_York"
  
  validation {
    condition = can(regex("^[A-Za-z_]+/[A-Za-z_]+$", var.schedule_timezone))
    error_message = "Timezone must be a valid IANA timezone (e.g., America/New_York)."
  }
}

# Test Instance Configuration
variable "create_test_resources" {
  description = "Whether to create test compute instances for backup validation"
  type        = bool
  default     = true
}

variable "test_instance_machine_type" {
  description = "Machine type for the test compute instance"
  type        = string
  default     = "e2-medium"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]*$", var.test_instance_machine_type))
    error_message = "Machine type must be a valid GCP machine type (e.g., e2-medium)."
  }
}

variable "test_instance_zone" {
  description = "Zone for the test compute instance (must be in primary region)"
  type        = string
  default     = ""
}

variable "test_disk_size_gb" {
  description = "Size of the test data disk in GB"
  type        = number
  default     = 10
  
  validation {
    condition     = var.test_disk_size_gb >= 10 && var.test_disk_size_gb <= 1000
    error_message = "Test disk size must be between 10 and 1000 GB."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Whether to create monitoring dashboards and alert policies"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for backup failure notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Workflow Configuration
variable "workflow_call_log_level" {
  description = "Logging level for workflow executions"
  type        = string
  default     = "LOG_ERRORS_ONLY"
  
  validation {
    condition = contains([
      "CALL_LOG_LEVEL_UNSPECIFIED",
      "LOG_ALL_CALLS",
      "LOG_ERRORS_ONLY",
      "LOG_NONE"
    ], var.workflow_call_log_level)
    error_message = "Invalid call log level. Must be one of: CALL_LOG_LEVEL_UNSPECIFIED, LOG_ALL_CALLS, LOG_ERRORS_ONLY, LOG_NONE."
  }
}

variable "workflow_execution_history_level" {
  description = "Execution history level for workflow runs"
  type        = string
  default     = "EXECUTION_HISTORY_DETAILED"
  
  validation {
    condition = contains([
      "EXECUTION_HISTORY_LEVEL_UNSPECIFIED",
      "EXECUTION_HISTORY_BASIC",
      "EXECUTION_HISTORY_DETAILED"
    ], var.workflow_execution_history_level)
    error_message = "Invalid execution history level. Must be one of: EXECUTION_HISTORY_LEVEL_UNSPECIFIED, EXECUTION_HISTORY_BASIC, EXECUTION_HISTORY_DETAILED."
  }
}

# Resource Naming and Tagging
variable "resource_prefix" {
  description = "Prefix for naming all resources (will be combined with random suffix)"
  type        = string
  default     = "backup-automation"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment tag for resources (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z]([a-z0-9_-]{0,61}[a-z0-9])?$", k))
    ])
    error_message = "Label keys must start with a letter, contain only lowercase letters, numbers, underscores, and hyphens, be 1-63 characters, and end with a letter or number."
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label values must contain only lowercase letters, numbers, underscores, and hyphens, and be 0-63 characters."
  }
}

# Service Account Configuration
variable "service_account_description" {
  description = "Description for the backup automation service account"
  type        = string
  default     = "Service account for multi-region backup automation workflows"
}

# API Configuration
variable "required_apis" {
  description = "List of APIs required for backup automation"
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "backupdr.googleapis.com",
    "workflows.googleapis.com",
    "cloudscheduler.googleapis.com",
    "monitoring.googleapis.com",
    "iam.googleapis.com"
  ]
}