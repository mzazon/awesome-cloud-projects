# Project and region configuration
variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for resources"
  type        = string
  default     = "us-central1-a"
}

# Resource naming and tagging
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "error-monitor"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
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

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    recipe      = "error-monitoring-debugging"
    managed-by  = "terraform"
    component   = "observability"
  }
}

# Cloud Functions configuration
variable "error_processor_memory" {
  description = "Memory allocation for error processor function (in MB)"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.error_processor_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "error_processor_timeout" {
  description = "Timeout for error processor function (in seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.error_processor_timeout >= 1 && var.error_processor_timeout <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

variable "alert_router_memory" {
  description = "Memory allocation for alert router function (in MB)"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.alert_router_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "debug_automation_memory" {
  description = "Memory allocation for debug automation function (in MB)"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.debug_automation_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "debug_automation_timeout" {
  description = "Timeout for debug automation function (in seconds)"
  type        = number
  default     = 120
  validation {
    condition     = var.debug_automation_timeout >= 1 && var.debug_automation_timeout <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

# Storage configuration
variable "storage_bucket_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "asia-east1", "asia-southeast1"
    ], var.storage_bucket_location)
    error_message = "Location must be a valid Cloud Storage location."
  }
}

variable "storage_bucket_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_bucket_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# Firestore configuration
variable "firestore_location" {
  description = "Location for Firestore database"
  type        = string
  default     = "us-central"
  validation {
    condition = contains([
      "us-central", "us-east1", "us-west2", "us-west3", "us-west4",
      "europe-west", "europe-west2", "europe-west3", "asia-northeast1"
    ], var.firestore_location)
    error_message = "Location must be a valid Firestore location."
  }
}

# Notification configuration
variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "notification_email" {
  description = "Email address for critical error notifications"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

# Monitoring configuration
variable "enable_monitoring_dashboard" {
  description = "Whether to create a Cloud Monitoring dashboard"
  type        = bool
  default     = true
}

variable "error_rate_threshold" {
  description = "Error rate threshold for alerting (errors per minute)"
  type        = number
  default     = 5
  validation {
    condition     = var.error_rate_threshold > 0
    error_message = "Error rate threshold must be greater than 0."
  }
}

# Log sink configuration
variable "enable_error_log_sink" {
  description = "Whether to create a log sink for error events"
  type        = bool
  default     = true
}

variable "log_sink_filter" {
  description = "Log filter for error events"
  type        = string
  default     = "protoPayload.serviceName=\"clouderrorreporting.googleapis.com\""
}

# Sample application configuration
variable "deploy_sample_app" {
  description = "Whether to deploy the sample error-generating application"
  type        = bool
  default     = true
}

variable "sample_app_memory" {
  description = "Memory allocation for sample application (in MB)"
  type        = number
  default     = 128
  validation {
    condition     = contains([128, 256, 512, 1024], var.sample_app_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024."
  }
}

# IAM and security configuration
variable "create_service_accounts" {
  description = "Whether to create dedicated service accounts for functions"
  type        = bool
  default     = true
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}