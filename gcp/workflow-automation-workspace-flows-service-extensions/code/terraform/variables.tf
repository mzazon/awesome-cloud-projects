# Variable Definitions for Workflow Automation Infrastructure
# This file defines all configurable parameters for the solution

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 6 && can(regex("^[a-z0-9-]+$", var.project_id))
    error_message = "Project ID must be at least 6 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.region))
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone."
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

variable "resource_name_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "workflow-automation"
  
  validation {
    condition     = length(var.resource_name_prefix) <= 20 && can(regex("^[a-z0-9-]+$", var.resource_name_prefix))
    error_message = "Resource name prefix must be 20 characters or less and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_bucket_location" {
  description = "Location for the Cloud Storage bucket (multi-region or region)"
  type        = string
  default     = "US"
  
  validation {
    condition     = contains(["US", "EU", "ASIA", "us-central1", "us-east1", "europe-west1", "asia-southeast1"], var.storage_bucket_location)
    error_message = "Storage bucket location must be a valid multi-region or region."
  }
}

variable "storage_bucket_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_bucket_class)
    error_message = "Storage bucket class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = number
  default     = 512
  
  validation {
    condition     = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 MB and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (in seconds)"
  type        = number
  default     = 540
  
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 60 and 3600 seconds."
  }
}

variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub subscriptions"
  type        = string
  default     = "604800s" # 7 days
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., '604800s')."
  }
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscriptions (in seconds)"
  type        = number
  default     = 600
  
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

variable "max_delivery_attempts" {
  description = "Maximum delivery attempts for Pub/Sub dead letter policy"
  type        = number
  default     = 5
  
  validation {
    condition     = var.max_delivery_attempts >= 1 && var.max_delivery_attempts <= 100
    error_message = "Maximum delivery attempts must be between 1 and 100."
  }
}

variable "enable_apis" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "serviceextensions.googleapis.com",
    "admin.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com"
  ]
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment    = "dev"
    project        = "workflow-automation"
    managed-by     = "terraform"
    solution       = "workspace-flows"
  }
}

variable "service_account_roles" {
  description = "List of IAM roles to assign to the service account"
  type        = list(string)
  default = [
    "roles/cloudfunctions.developer",
    "roles/pubsub.editor",
    "roles/storage.objectAdmin",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/eventarc.eventReceiver"
  ]
}

variable "workspace_domain" {
  description = "Google Workspace domain for integration (optional)"
  type        = string
  default     = ""
}

variable "notification_email" {
  description = "Email address for workflow notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for the workflow solution"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Cloud Logging for the workflow solution"
  type        = bool
  default     = true
}

variable "enable_dead_letter" {
  description = "Enable dead letter queue for failed message processing"
  type        = bool
  default     = true
}