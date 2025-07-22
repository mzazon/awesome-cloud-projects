# Project configuration variables
variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{5,29}$", var.project_id))
    error_message = "The project_id must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "The region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource naming variables
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens, and cannot start or end with a hyphen."
  }
}

variable "application_name" {
  description = "Name of the application for resource naming"
  type        = string
  default     = "code-review-automation"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.application_name))
    error_message = "Application name must contain only lowercase letters, numbers, and hyphens, and cannot start or end with a hyphen."
  }
}

# Service configuration variables
variable "code_review_service_name" {
  description = "Name for the code review Cloud Run service"
  type        = string
  default     = "code-review-service"
}

variable "docs_service_name" {
  description = "Name for the documentation update Cloud Run service"
  type        = string
  default     = "docs-service"
}

variable "notification_service_name" {
  description = "Name for the notification Cloud Run service"
  type        = string
  default     = "notification-service"
}

# Pub/Sub configuration variables
variable "pubsub_topic_name" {
  description = "Name for the Pub/Sub topic"
  type        = string
  default     = "code-events"
}

variable "pubsub_subscription_name" {
  description = "Name for the Pub/Sub subscription"
  type        = string
  default     = "code-processing"
}

variable "pubsub_message_retention_duration" {
  description = "How long to retain undelivered messages in the subscription"
  type        = string
  default     = "604800s" # 7 days
}

variable "pubsub_ack_deadline_seconds" {
  description = "Maximum time after a subscriber receives a message before the subscriber should acknowledge the message"
  type        = number
  default     = 600 # 10 minutes
}

# Cloud Storage configuration variables
variable "storage_bucket_name" {
  description = "Name for the Cloud Storage bucket (will have random suffix appended)"
  type        = string
  default     = "code-artifacts"
}

variable "storage_bucket_location" {
  description = "Location for the Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "storage_bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# Cloud Run configuration variables
variable "cloud_run_cpu_limit" {
  description = "CPU limit for Cloud Run services"
  type        = string
  default     = "1000m"
}

variable "cloud_run_memory_limit" {
  description = "Memory limit for Cloud Run services"
  type        = string
  default     = "512Mi"
}

variable "cloud_run_max_instances" {
  description = "Maximum number of instances for Cloud Run services"
  type        = number
  default     = 10
}

variable "cloud_run_min_instances" {
  description = "Minimum number of instances for Cloud Run services"
  type        = number
  default     = 0
}

variable "cloud_run_timeout_seconds" {
  description = "Request timeout for Cloud Run services"
  type        = number
  default     = 300
}

# Google Workspace configuration variables
variable "workspace_domain" {
  description = "Google Workspace domain for API access"
  type        = string
  default     = ""
}

variable "workspace_admin_email" {
  description = "Google Workspace admin email for service account delegation"
  type        = string
  default     = ""
}

# Monitoring and alerting configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring dashboard and alerts"
  type        = bool
  default     = true
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

# Cloud Scheduler configuration
variable "enable_scheduler" {
  description = "Enable Cloud Scheduler jobs for maintenance"
  type        = bool
  default     = true
}

variable "weekly_review_schedule" {
  description = "Cron schedule for weekly documentation review (UTC)"
  type        = string
  default     = "0 9 * * 1" # Monday at 9 AM UTC
}

variable "monthly_cleanup_schedule" {
  description = "Cron schedule for monthly cleanup (UTC)"
  type        = string
  default     = "0 2 1 * *" # First day of month at 2 AM UTC
}

variable "weekly_summary_schedule" {
  description = "Cron schedule for weekly summary generation (UTC)"
  type        = string
  default     = "0 3 * * 0" # Sunday at 3 AM UTC
}

# Security configuration
variable "allowed_ingress" {
  description = "Allowed ingress for Cloud Run services"
  type        = string
  default     = "all"
  validation {
    condition = contains([
      "all", "internal", "internal-and-cloud-load-balancing"
    ], var.allowed_ingress)
    error_message = "Allowed ingress must be one of: all, internal, internal-and-cloud-load-balancing."
  }
}

variable "service_account_name" {
  description = "Name for the Google Workspace service account"
  type        = string
  default     = "workspace-automation"
}

# Container image configuration
variable "container_registry" {
  description = "Container registry to use for Cloud Run images"
  type        = string
  default     = "gcr.io"
  validation {
    condition = contains([
      "gcr.io", "us.gcr.io", "eu.gcr.io", "asia.gcr.io",
      "us-central1-docker.pkg.dev", "us-east1-docker.pkg.dev", "europe-west1-docker.pkg.dev"
    ], var.container_registry)
    error_message = "Container registry must be a valid GCR or Artifact Registry URL."
  }
}

# Labels and tags
variable "labels" {
  description = "A map of labels to apply to resources"
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "purpose"    = "code-review-automation"
  }
}

# API enablement
variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "required_apis" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "cloudscheduler.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "gmail.googleapis.com",
    "docs.googleapis.com",
    "drive.googleapis.com",
    "admin.googleapis.com",
    "cloudbuild.googleapis.com"
  ]
}