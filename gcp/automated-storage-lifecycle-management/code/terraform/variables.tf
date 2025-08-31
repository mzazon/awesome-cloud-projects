# Variables for the Automated Storage Lifecycle Management solution
# These variables allow customization of the infrastructure deployment

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name. A random suffix will be added."
  type        = string
  default     = "storage-lifecycle-demo"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for enhanced security"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "Default storage class for the bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "lifecycle_rules" {
  description = "Lifecycle rules configuration for automated storage transitions"
  type = object({
    nearline_age_days  = number
    coldline_age_days  = number
    archive_age_days   = number
    delete_age_days    = number
  })
  default = {
    nearline_age_days = 30
    coldline_age_days = 90
    archive_age_days  = 365
    delete_age_days   = 2555
  }
  validation {
    condition = (
      var.lifecycle_rules.nearline_age_days < var.lifecycle_rules.coldline_age_days &&
      var.lifecycle_rules.coldline_age_days < var.lifecycle_rules.archive_age_days &&
      var.lifecycle_rules.archive_age_days < var.lifecycle_rules.delete_age_days
    )
    error_message = "Lifecycle rules must be in ascending order: nearline < coldline < archive < delete."
  }
}

variable "scheduler_job_schedule" {
  description = "Cron schedule for the Cloud Scheduler job (weekly reporting by default)"
  type        = string
  default     = "0 9 * * 1"
  validation {
    condition     = can(regex("^[0-9*,-/ ]+$", var.scheduler_job_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "webhook_url" {
  description = "Webhook URL for scheduler job notifications"
  type        = string
  default     = "https://httpbin.org/post"
  validation {
    condition     = can(regex("^https?://", var.webhook_url))
    error_message = "Webhook URL must be a valid HTTP or HTTPS URL."
  }
}

variable "enable_monitoring" {
  description = "Enable monitoring and logging for lifecycle events"
  type        = bool
  default     = true
}

variable "enable_sample_data" {
  description = "Create sample data files for testing lifecycle policies"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "storage-lifecycle-management"
    environment = "demo"
    managed-by  = "terraform"
  }
  validation {
    condition     = alltrue([for v in values(var.labels) : can(regex("^[a-z0-9_-]+$", v))])
    error_message = "Label values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "enable_versioning" {
  description = "Enable object versioning on the storage bucket"
  type        = bool
  default     = false
}

variable "retention_policy_days" {
  description = "Minimum retention period in days (0 to disable retention policy)"
  type        = number
  default     = 0
  validation {
    condition     = var.retention_policy_days >= 0
    error_message = "Retention policy days must be non-negative."
  }
}