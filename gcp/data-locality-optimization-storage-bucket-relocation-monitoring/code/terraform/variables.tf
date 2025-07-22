# Variable definitions for data locality optimization infrastructure
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "primary_region" {
  description = "Primary Google Cloud region for initial bucket placement and function deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-east4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.primary_region)
    error_message = "Primary region must be a valid Google Cloud region."
  }
}

variable "secondary_region" {
  description = "Secondary Google Cloud region for potential bucket relocation"
  type        = string
  default     = "europe-west1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-east4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.secondary_region)
    error_message = "Secondary region must be a valid Google Cloud region."
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

variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (MB)"
  type        = number
  default     = 512
  validation {
    condition     = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions execution (seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "alert_threshold_ms" {
  description = "Storage access latency threshold in milliseconds for triggering alerts"
  type        = number
  default     = 100
  validation {
    condition     = var.alert_threshold_ms > 0 && var.alert_threshold_ms <= 1000
    error_message = "Alert threshold must be between 1 and 1000 milliseconds."
  }
}

variable "scheduler_timezone" {
  description = "Timezone for Cloud Scheduler jobs"
  type        = string
  default     = "America/New_York"
}

variable "scheduler_cron" {
  description = "Cron expression for periodic data locality analysis"
  type        = string
  default     = "0 2 * * *"
  validation {
    condition     = can(regex("^[0-9,\\-\\*\\/]+ [0-9,\\-\\*\\/]+ [0-9,\\-\\*\\/]+ [0-9,\\-\\*\\/]+ [0-9,\\-\\*\\/]+$", var.scheduler_cron))
    error_message = "Scheduler cron must be a valid cron expression."
  }
}

variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access for enhanced security"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for relocation notifications (optional)"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring with custom metrics and dashboards"
  type        = bool
  default     = true
}

variable "pubsub_message_retention" {
  description = "Message retention duration for Pub/Sub topic (hours)"
  type        = number
  default     = 168  # 7 days
  validation {
    condition     = var.pubsub_message_retention >= 10 && var.pubsub_message_retention <= 2400
    error_message = "Pub/Sub message retention must be between 10 minutes and 7 days (in hours)."
  }
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "data-locality"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}