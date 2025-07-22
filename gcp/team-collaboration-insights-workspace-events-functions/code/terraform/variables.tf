# Variables for Team Collaboration Insights with Workspace Events API
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for deploying regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for deploying zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "workspace-analytics"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.resource_prefix))
    error_message = "Resource prefix must be 3-21 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
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

# Pub/Sub Configuration
variable "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for Workspace events"
  type        = string
  default     = "workspace-events-topic"
}

variable "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription"
  type        = string
  default     = "workspace-events-subscription"
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscription in seconds"
  type        = number
  default     = 600
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

# Cloud Functions Configuration
variable "functions_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312",
      "nodejs18", "nodejs20", "go121", "java17", "java21"
    ], var.functions_runtime)
    error_message = "Runtime must be a supported Cloud Functions runtime."
  }
}

variable "event_processor_memory" {
  description = "Memory allocation for event processor function in MB"
  type        = number
  default     = 256
  validation {
    condition     = var.event_processor_memory >= 128 && var.event_processor_memory <= 8192
    error_message = "Memory must be between 128 MB and 8192 MB."
  }
}

variable "event_processor_timeout" {
  description = "Timeout for event processor function in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.event_processor_timeout >= 1 && var.event_processor_timeout <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

variable "analytics_api_memory" {
  description = "Memory allocation for analytics API function in MB"
  type        = number
  default     = 512
  validation {
    condition     = var.analytics_api_memory >= 128 && var.analytics_api_memory <= 8192
    error_message = "Memory must be between 128 MB and 8192 MB."
  }
}

variable "analytics_api_timeout" {
  description = "Timeout for analytics API function in seconds"
  type        = number
  default     = 120
  validation {
    condition     = var.analytics_api_timeout >= 1 && var.analytics_api_timeout <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

# Firestore Configuration
variable "firestore_location" {
  description = "Location for Firestore database"
  type        = string
  default     = "nam5"
  validation {
    condition = contains([
      "nam5", "us-central", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "eur3", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or regional location."
  }
}

variable "firestore_type" {
  description = "Type of Firestore database"
  type        = string
  default     = "FIRESTORE_NATIVE"
  validation {
    condition     = contains(["FIRESTORE_NATIVE", "DATASTORE_MODE"], var.firestore_type)
    error_message = "Firestore type must be either FIRESTORE_NATIVE or DATASTORE_MODE."
  }
}

# Service Account Configuration
variable "service_account_display_name" {
  description = "Display name for the Workspace Events service account"
  type        = string
  default     = "Workspace Events Service Account"
}

# Workspace Events API Configuration
variable "workspace_domain" {
  description = "Google Workspace domain for event monitoring (leave empty to configure manually)"
  type        = string
  default     = ""
}

variable "enable_workspace_events_api" {
  description = "Whether to enable Workspace Events API (requires manual domain configuration)"
  type        = bool
  default     = true
}

# Resource Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "workspace-analytics"
    managed-by  = "terraform"
    environment = "dev"
  }
}

# Monitoring and Alerting
variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring for the solution"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Whether to enable detailed logging for Cloud Functions"
  type        = bool
  default     = true
}

# Security Configuration
variable "allow_unauthenticated_analytics_api" {
  description = "Whether to allow unauthenticated access to analytics API (not recommended for production)"
  type        = bool
  default     = false
}

variable "enable_audit_logs" {
  description = "Whether to enable audit logs for the project"
  type        = bool
  default     = true
}