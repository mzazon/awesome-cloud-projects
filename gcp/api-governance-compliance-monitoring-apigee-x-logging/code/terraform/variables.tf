# Input Variables for API Governance and Compliance Monitoring
# This file defines all configurable parameters for the Terraform deployment

# Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{5,29}$", var.project_id))
    error_message = "Project ID must be 6-30 characters long, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The default region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid GCP region (e.g., us-central1, europe-west1)."
  }
}

variable "zone" {
  description = "The default zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone (e.g., us-central1-a, europe-west1-b)."
  }
}

# Apigee Configuration
variable "apigee_analytics_region" {
  description = "The analytics region for Apigee X organization"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.apigee_analytics_region)
    error_message = "Analytics region must be a valid Apigee X analytics region."
  }
}

variable "apigee_environment_name" {
  description = "Name for the Apigee environment"
  type        = string
  default     = "governance-env"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,31}$", var.apigee_environment_name))
    error_message = "Environment name must be 3-32 characters long, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "apigee_environment_display_name" {
  description = "Display name for the Apigee environment"
  type        = string
  default     = "API Governance Environment"
}

variable "apigee_billing_type" {
  description = "Billing type for Apigee organization (PAYG or SUBSCRIPTION)"
  type        = string
  default     = "PAYG"
  validation {
    condition     = contains(["PAYG", "SUBSCRIPTION"], var.apigee_billing_type)
    error_message = "Billing type must be either PAYG or SUBSCRIPTION."
  }
}

# BigQuery Configuration
variable "bigquery_dataset_id" {
  description = "BigQuery dataset ID for storing API governance logs"
  type        = string
  default     = "api_governance_logs"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{1,1024}$", var.bigquery_dataset_id))
    error_message = "Dataset ID must contain only letters, numbers, and underscores."
  }
}

variable "bigquery_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU", "asia-east1", "asia-northeast1", "asia-southeast1", "europe-west1", "europe-west2", "us-central1", "us-east1", "us-west1", "us-west2"], var.bigquery_location)
    error_message = "Location must be a valid BigQuery location."
  }
}

variable "bigquery_table_expiration_days" {
  description = "Number of days after which BigQuery tables will be automatically deleted"
  type        = number
  default     = 90
  validation {
    condition     = var.bigquery_table_expiration_days >= 1 && var.bigquery_table_expiration_days <= 365
    error_message = "Table expiration must be between 1 and 365 days."
  }
}

# Cloud Functions Configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition     = contains(["python39", "python310", "python311", "python312"], var.function_runtime)
    error_message = "Runtime must be a supported Python version."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "512Mi"
  validation {
    condition     = contains(["128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"], var.function_memory)
    error_message = "Memory must be a valid Cloud Functions memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

variable "function_min_instances" {
  description = "Minimum number of instances for Cloud Functions"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 100
    error_message = "Min instances must be between 0 and 100."
  }
}

variable "function_max_instances" {
  description = "Maximum number of instances for Cloud Functions"
  type        = number
  default     = 10
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

# Pub/Sub Configuration
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topics"
  type        = string
  default     = "86400s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., 86400s)."
  }
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscriptions"
  type        = number
  default     = 60
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Ack deadline must be between 10 and 600 seconds."
  }
}

# Cloud Storage Configuration
variable "storage_force_destroy" {
  description = "Allow force destroy of Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "storage_versioning_enabled" {
  description = "Enable versioning on Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "storage_lifecycle_age_days" {
  description = "Age in days for lifecycle rule on Cloud Storage buckets"
  type        = number
  default     = 90
  validation {
    condition     = var.storage_lifecycle_age_days >= 1 && var.storage_lifecycle_age_days <= 3650
    error_message = "Lifecycle age must be between 1 and 3650 days."
  }
}

# Monitoring Configuration
variable "monitoring_notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = "api-governance@example.com"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.monitoring_notification_email))
    error_message = "Must be a valid email address."
  }
}

variable "monitoring_alert_auto_close" {
  description = "Auto-close duration for monitoring alerts"
  type        = string
  default     = "1800s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.monitoring_alert_auto_close))
    error_message = "Auto-close duration must be in seconds format (e.g., 1800s)."
  }
}

variable "monitoring_error_rate_threshold" {
  description = "Error rate threshold for compliance violations (0.0 to 1.0)"
  type        = number
  default     = 0.1
  validation {
    condition     = var.monitoring_error_rate_threshold >= 0.0 && var.monitoring_error_rate_threshold <= 1.0
    error_message = "Error rate threshold must be between 0.0 and 1.0."
  }
}

# Logging Configuration
variable "log_retention_days" {
  description = "Number of days to retain logs in Cloud Logging"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "api-governance"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.resource_prefix))
    error_message = "Resource prefix must be 3-20 characters long, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Labels Configuration
variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "api-governance"
    environment = "dev"
    managed-by  = "terraform"
    purpose     = "compliance-monitoring"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z][a-z0-9-_]{0,62}$", k))])
    error_message = "Label keys must be 1-63 characters long, start with a letter, and contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

# Enable/Disable Features
variable "enable_apigee_organization" {
  description = "Enable creation of Apigee organization (expensive resource)"
  type        = bool
  default     = true
}

variable "enable_bigquery_export" {
  description = "Enable BigQuery export for logs"
  type        = bool
  default     = true
}

variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts"
  type        = bool
  default     = true
}

variable "enable_eventarc_triggers" {
  description = "Enable Eventarc triggers for automated response"
  type        = bool
  default     = true
}