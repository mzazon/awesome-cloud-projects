# Project configuration variables
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource naming and tagging variables
variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "workforce-analytics"
    component   = "workspace-events"
    managed-by  = "terraform"
  }
}

# BigQuery configuration variables
variable "dataset_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "US"
}

variable "dataset_description" {
  description = "Description for the BigQuery dataset"
  type        = string
  default     = "Workforce Analytics Data Warehouse for Google Workspace Events"
}

variable "bigquery_table_expiration_days" {
  description = "Number of days after which BigQuery tables will expire (0 for no expiration)"
  type        = number
  default     = 0
  validation {
    condition     = var.bigquery_table_expiration_days >= 0
    error_message = "Table expiration days must be >= 0."
  }
}

# Pub/Sub configuration variables
variable "message_retention_duration" {
  description = "How long to retain unacknowledged messages in the subscription"
  type        = string
  default     = "604800s" # 7 days
}

variable "ack_deadline_seconds" {
  description = "Maximum time a subscriber can take to acknowledge a message"
  type        = number
  default     = 600
  validation {
    condition     = var.ack_deadline_seconds >= 10 && var.ack_deadline_seconds <= 600
    error_message = "Ack deadline must be between 10 and 600 seconds."
  }
}

variable "enable_message_ordering" {
  description = "Whether to enable message ordering for the subscription"
  type        = bool
  default     = true
}

# Cloud Run Worker Pool configuration variables
variable "worker_pool_min_instances" {
  description = "Minimum number of worker pool instances"
  type        = number
  default     = 1
  validation {
    condition     = var.worker_pool_min_instances >= 0
    error_message = "Minimum instances must be >= 0."
  }
}

variable "worker_pool_max_instances" {
  description = "Maximum number of worker pool instances"
  type        = number
  default     = 10
  validation {
    condition     = var.worker_pool_max_instances >= 1
    error_message = "Maximum instances must be >= 1."
  }
}

variable "worker_pool_memory" {
  description = "Memory allocation for worker pool instances"
  type        = string
  default     = "1Gi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.worker_pool_memory)
    error_message = "Memory must be a valid Cloud Run memory allocation."
  }
}

variable "worker_pool_cpu" {
  description = "CPU allocation for worker pool instances"
  type        = string
  default     = "1"
  validation {
    condition = contains([
      "0.08", "0.17", "0.25", "0.33", "0.5", "0.75", "1", "2", "4", "6", "8"
    ], var.worker_pool_cpu)
    error_message = "CPU must be a valid Cloud Run CPU allocation."
  }
}

variable "container_image" {
  description = "Container image for the worker pool (will be built if not provided)"
  type        = string
  default     = ""
}

# Cloud Storage configuration variables
variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Whether to enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "lifecycle_age_days" {
  description = "Number of days after which objects are deleted (0 to disable)"
  type        = number
  default     = 90
  validation {
    condition     = var.lifecycle_age_days >= 0
    error_message = "Lifecycle age days must be >= 0."
  }
}

# API enablement variables
variable "enable_apis" {
  description = "Whether to enable required APIs (disable if APIs are already enabled)"
  type        = bool
  default     = true
}

variable "required_apis" {
  description = "List of APIs required for the workforce analytics solution"
  type        = list(string)
  default = [
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "workspaceevents.googleapis.com",
    "storage.googleapis.com"
  ]
}

# Monitoring configuration variables
variable "create_monitoring_dashboard" {
  description = "Whether to create Cloud Monitoring dashboard"
  type        = bool
  default     = true
}

variable "create_alerting_policies" {
  description = "Whether to create alerting policies"
  type        = bool
  default     = true
}

variable "notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

# Security configuration variables
variable "create_custom_service_account" {
  description = "Whether to create a custom service account for the worker pool"
  type        = bool
  default     = true
}

variable "service_account_roles" {
  description = "IAM roles to assign to the worker pool service account"
  type        = list(string)
  default = [
    "roles/bigquery.dataEditor",
    "roles/pubsub.subscriber",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ]
}