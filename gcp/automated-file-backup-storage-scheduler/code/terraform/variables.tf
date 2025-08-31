# Input variables for the automated file backup solution
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
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

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "primary_bucket_name" {
  description = "Name for the primary storage bucket (will be suffixed with random string if not globally unique)"
  type        = string
  default     = "primary-data"
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$", var.primary_bucket_name))
    error_message = "Bucket name must be a valid GCS bucket name (lowercase, alphanumeric, dots, dashes, underscores)."
  }
}

variable "backup_bucket_name" {
  description = "Name for the backup storage bucket (will be suffixed with random string if not globally unique)"
  type        = string
  default     = "backup-data"
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$", var.backup_bucket_name))
    error_message = "Bucket name must be a valid GCS bucket name (lowercase, alphanumeric, dots, dashes, underscores)."
  }
}

variable "function_name" {
  description = "Name for the Cloud Function"
  type        = string
  default     = "backup-function"
  validation {
    condition     = can(regex("^[a-zA-Z]([a-zA-Z0-9_-]*[a-zA-Z0-9])?$", var.function_name))
    error_message = "Function name must start with a letter and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "scheduler_job_name" {
  description = "Name for the Cloud Scheduler job"
  type        = string
  default     = "backup-daily-job"
  validation {
    condition     = can(regex("^[a-zA-Z]([a-zA-Z0-9_-]*[a-zA-Z0-9])?$", var.scheduler_job_name))
    error_message = "Scheduler job name must start with a letter and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "backup_schedule" {
  description = "Cron schedule for backup job (default: daily at 2 AM UTC)"
  type        = string
  default     = "0 2 * * *"
  validation {
    condition     = can(regex("^([0-9*,-/]+\\s+){4}[0-9*,-/]+$", var.backup_schedule))
    error_message = "Backup schedule must be a valid cron expression."
  }
}

variable "primary_storage_class" {
  description = "Storage class for the primary bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.primary_storage_class)
    error_message = "Primary storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "backup_storage_class" {
  description = "Storage class for the backup bucket"
  type        = string
  default     = "NEARLINE"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.backup_storage_class)
    error_message = "Backup storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function (in MB)"
  type        = number
  default     = 256
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function (in seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on storage buckets"
  type        = bool
  default     = true
}

variable "create_sample_files" {
  description = "Create sample files in the primary bucket for testing"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "automated-backup"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}