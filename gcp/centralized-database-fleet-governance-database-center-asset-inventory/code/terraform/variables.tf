# Variables for Centralized Database Fleet Governance Infrastructure
# Supports Google Cloud Database Center and Cloud Asset Inventory integration

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region format."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format."
  }
}

variable "environment" {
  description = "Environment label for resource naming and tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "create_sample_databases" {
  description = "Whether to create sample database instances for governance testing"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for production database instances"
  type        = bool
  default     = true
}

variable "database_backup_start_time" {
  description = "Start time for automated database backups (HH:MM format)"
  type        = string
  default     = "02:00"
  
  validation {
    condition = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.database_backup_start_time))
    error_message = "Backup start time must be in HH:MM format."
  }
}

variable "spanner_node_count" {
  description = "Number of nodes for Spanner instance"
  type        = number
  default     = 1
  
  validation {
    condition     = var.spanner_node_count >= 1 && var.spanner_node_count <= 10
    error_message = "Spanner node count must be between 1 and 10."
  }
}

variable "bigtable_num_nodes" {
  description = "Number of nodes for Bigtable cluster"
  type        = number
  default     = 1
  
  validation {
    condition     = var.bigtable_num_nodes >= 1 && var.bigtable_num_nodes <= 30
    error_message = "Bigtable node count must be between 1 and 30."
  }
}

variable "bigtable_instance_type" {
  description = "Instance type for Bigtable (PRODUCTION or DEVELOPMENT)"
  type        = string
  default     = "DEVELOPMENT"
  
  validation {
    condition     = contains(["PRODUCTION", "DEVELOPMENT"], var.bigtable_instance_type)
    error_message = "Bigtable instance type must be PRODUCTION or DEVELOPMENT."
  }
}

variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts and notification channels"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for governance alert notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "governance_scheduler_timezone" {
  description = "Timezone for governance automation scheduler"
  type        = string
  default     = "America/New_York"
}

variable "governance_check_schedule" {
  description = "Cron schedule for automated governance checks"
  type        = string
  default     = "0 */6 * * *"
  
  validation {
    condition = can(regex("^[0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+$", var.governance_check_schedule))
    error_message = "Schedule must be in valid cron format."
  }
}

variable "enable_asset_inventory_export" {
  description = "Enable automated Cloud Asset Inventory exports to BigQuery"
  type        = bool
  default     = true
}

variable "bigquery_dataset_location" {
  description = "Location for BigQuery dataset (must match region for optimal performance)"
  type        = string
  default     = ""
}

variable "storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "enable_workflows" {
  description = "Enable Cloud Workflows for automated governance processes"
  type        = bool
  default     = true
}

variable "cloud_function_runtime" {
  description = "Runtime for Cloud Functions (compliance reporting)"
  type        = string
  default     = "python39"
  
  validation {
    condition     = contains(["python39", "python310", "python311"], var.cloud_function_runtime)
    error_message = "Function runtime must be python39, python310, or python311."
  }
}

variable "enable_gemini_integration" {
  description = "Enable Gemini AI integration for intelligent insights"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "database-governance"
    managed-by  = "terraform"
    environment = "development"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}