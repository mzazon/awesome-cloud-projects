# ==============================================================================
# Infrastructure Change Monitoring Variables
# ==============================================================================
# This file defines all configurable variables for the infrastructure change
# monitoring solution, enabling customization for different environments and
# compliance requirements.

# ==============================================================================
# Project and Region Configuration
# ==============================================================================

variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and organization"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# ==============================================================================
# Asset Monitoring Configuration
# ==============================================================================

variable "monitored_asset_types" {
  description = "List of Google Cloud asset types to monitor for changes. Use '.*' for all asset types"
  type        = list(string)
  default = [
    ".*" # Monitor all asset types by default
  ]
  
  validation {
    condition     = length(var.monitored_asset_types) > 0
    error_message = "At least one asset type must be specified for monitoring."
  }
}

variable "audit_data_retention_days" {
  description = "Number of days to retain audit data in BigQuery before automatic deletion"
  type        = number
  default     = 365
  
  validation {
    condition     = var.audit_data_retention_days >= 30 && var.audit_data_retention_days <= 3650
    error_message = "Audit data retention must be between 30 and 3650 days (10 years)."
  }
}

# ==============================================================================
# Alerting and Monitoring Configuration
# ==============================================================================

variable "enable_alerting" {
  description = "Enable Cloud Monitoring alert policies for infrastructure changes"
  type        = bool
  default     = true
}

variable "alert_email_addresses" {
  description = "List of email addresses to receive infrastructure change alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.alert_email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid email format."
  }
}

variable "change_rate_threshold" {
  description = "Threshold for infrastructure change rate alerts (changes per minute)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.change_rate_threshold > 0 && var.change_rate_threshold <= 1000
    error_message = "Change rate threshold must be between 1 and 1000 changes per minute."
  }
}

# ==============================================================================
# Function Configuration
# ==============================================================================

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Function processing asset changes"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Function execution in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

# ==============================================================================
# Pub/Sub Configuration
# ==============================================================================

variable "message_retention_duration" {
  description = "Duration to retain messages in Pub/Sub topic (in seconds)"
  type        = string
  default     = "86400s" # 24 hours
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., '86400s')."
  }
}

variable "subscription_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscription in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.subscription_ack_deadline_seconds >= 10 && var.subscription_ack_deadline_seconds <= 600
    error_message = "Subscription acknowledgment deadline must be between 10 and 600 seconds."
  }
}

variable "dead_letter_max_delivery_attempts" {
  description = "Maximum delivery attempts before sending to dead letter queue"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dead_letter_max_delivery_attempts >= 1 && var.dead_letter_max_delivery_attempts <= 100
    error_message = "Dead letter max delivery attempts must be between 1 and 100."
  }
}

# ==============================================================================
# BigQuery Configuration
# ==============================================================================

variable "bigquery_location" {
  description = "Location for BigQuery dataset (if different from region)"
  type        = string
  default     = null
  
  validation {
    condition = var.bigquery_location == null || contains([
      "US", "EU", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid BigQuery location or null to use region."
  }
}

variable "enable_bigquery_partitioning" {
  description = "Enable table partitioning in BigQuery for improved query performance"
  type        = bool
  default     = true
}

variable "enable_bigquery_clustering" {
  description = "Enable table clustering in BigQuery for improved query performance"
  type        = bool
  default     = true
}

# ==============================================================================
# Security and Access Control Configuration
# ==============================================================================

variable "allowed_asset_projects" {
  description = "List of project IDs allowed to send asset changes (empty list allows all projects)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for project in var.allowed_asset_projects : can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", project))
    ])
    error_message = "All project IDs must be valid Google Cloud project ID format."
  }
}

variable "restrict_to_organization" {
  description = "Organization ID to restrict monitoring to (null allows all organizations)"
  type        = string
  default     = null
  
  validation {
    condition     = var.restrict_to_organization == null || can(regex("^[0-9]+$", var.restrict_to_organization))
    error_message = "Organization ID must be numeric or null."
  }
}

# ==============================================================================
# Advanced Configuration
# ==============================================================================

variable "enable_function_vpc_connector" {
  description = "Enable VPC connector for Cloud Functions (for private network access)"
  type        = bool
  default     = false
}

variable "vpc_connector_name" {
  description = "Name of VPC connector to use for Cloud Functions (if enabled)"
  type        = string
  default     = null
  
  validation {
    condition     = var.vpc_connector_name == null || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.vpc_connector_name))
    error_message = "VPC connector name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_cloud_armor" {
  description = "Enable Cloud Armor protection for external endpoints"
  type        = bool
  default     = false
}

variable "custom_function_labels" {
  description = "Additional custom labels to apply to Cloud Functions"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.custom_function_labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring and custom metrics for all components"
  type        = bool
  default     = true
}

variable "enable_audit_logging" {
  description = "Enable Cloud Audit Logs for infrastructure monitoring components"
  type        = bool
  default     = true
}

# ==============================================================================
# Cost Optimization Configuration
# ==============================================================================

variable "enable_preemptible_resources" {
  description = "Enable preemptible/spot resources where applicable for cost optimization"
  type        = bool
  default     = false
}

variable "storage_class" {
  description = "Storage class for Cloud Storage buckets used by the solution"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_lifecycle_management" {
  description = "Enable lifecycle management for storage resources"
  type        = bool
  default     = true
}