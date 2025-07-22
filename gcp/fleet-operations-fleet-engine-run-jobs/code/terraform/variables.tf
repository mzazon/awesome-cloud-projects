# Core project configuration
variable "project_id" {
  description = "Google Cloud project ID for fleet operations"
  type        = string
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.project_id))
    error_message = "Project ID must be a valid Google Cloud project ID format."
  }
}

variable "region" {
  description = "Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]+$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone."
  }
}

# Fleet Engine configuration
variable "fleet_name" {
  description = "Name for the fleet management system"
  type        = string
  default     = "fleet-operations"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.fleet_name))
    error_message = "Fleet name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_fleet_engine" {
  description = "Enable Fleet Engine APIs and services"
  type        = bool
  default     = true
}

# Analytics job configuration
variable "analytics_job_name" {
  description = "Name for the fleet analytics Cloud Run job"
  type        = string
  default     = "fleet-analytics"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.analytics_job_name))
    error_message = "Analytics job name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "job_cpu_limit" {
  description = "CPU limit for the analytics job"
  type        = string
  default     = "1000m"
  validation {
    condition     = can(regex("^[0-9]+m?$", var.job_cpu_limit))
    error_message = "CPU limit must be a valid CPU value (e.g., 1000m, 2)."
  }
}

variable "job_memory_limit" {
  description = "Memory limit for the analytics job"
  type        = string
  default     = "2Gi"
  validation {
    condition     = can(regex("^[0-9]+([KMGT]i)?$", var.job_memory_limit))
    error_message = "Memory limit must be a valid memory value (e.g., 2Gi, 512Mi)."
  }
}

variable "job_timeout" {
  description = "Timeout for the analytics job in seconds"
  type        = number
  default     = 3600
  validation {
    condition     = var.job_timeout >= 60 && var.job_timeout <= 86400
    error_message = "Job timeout must be between 60 and 86400 seconds."
  }
}

variable "job_max_retries" {
  description = "Maximum number of retries for failed jobs"
  type        = number
  default     = 3
  validation {
    condition     = var.job_max_retries >= 0 && var.job_max_retries <= 10
    error_message = "Max retries must be between 0 and 10."
  }
}

# Storage configuration
variable "bucket_name" {
  description = "Name for the Cloud Storage bucket (will be suffixed with random string)"
  type        = string
  default     = "fleet-data"
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bucket_location" {
  description = "Location for the Cloud Storage bucket"
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU", "ASIA"], var.bucket_location)
    error_message = "Bucket location must be one of: US, EU, ASIA."
  }
}

variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD",
      "NEARLINE",
      "COLDLINE",
      "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# BigQuery configuration
variable "dataset_name" {
  description = "Name for the BigQuery dataset"
  type        = string
  default     = "fleet_analytics"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_name))
    error_message = "Dataset name must contain only letters, numbers, and underscores."
  }
}

variable "dataset_location" {
  description = "Location for the BigQuery dataset"
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU", "asia-southeast1", "us-central1"], var.dataset_location)
    error_message = "Dataset location must be a valid BigQuery location."
  }
}

variable "table_deletion_protection" {
  description = "Enable deletion protection for BigQuery tables"
  type        = bool
  default     = false
}

# Scheduler configuration
variable "enable_scheduler" {
  description = "Enable Cloud Scheduler for automated analytics processing"
  type        = bool
  default     = true
}

variable "daily_schedule" {
  description = "Cron schedule for daily analytics processing"
  type        = string
  default     = "0 2 * * *"
  validation {
    condition     = can(regex("^([0-9*,-/]+\\s+){4}[0-9*,-/]+$", var.daily_schedule))
    error_message = "Daily schedule must be a valid cron expression."
  }
}

variable "hourly_schedule" {
  description = "Cron schedule for hourly insights processing"
  type        = string
  default     = "0 * * * *"
  validation {
    condition     = can(regex("^([0-9*,-/]+\\s+){4}[0-9*,-/]+$", var.hourly_schedule))
    error_message = "Hourly schedule must be a valid cron expression."
  }
}

variable "time_zone" {
  description = "Time zone for scheduled jobs"
  type        = string
  default     = "America/New_York"
}

# Firestore configuration
variable "enable_firestore" {
  description = "Enable Firestore database for real-time fleet state"
  type        = bool
  default     = true
}

variable "firestore_location" {
  description = "Location for Firestore database"
  type        = string
  default     = "us-central"
  validation {
    condition = contains([
      "us-central",
      "us-east1",
      "us-west2",
      "europe-west1",
      "asia-southeast1"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region location."
  }
}

# Monitoring configuration
variable "enable_monitoring" {
  description = "Enable monitoring and alerting for fleet operations"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Container image configuration
variable "container_image_name" {
  description = "Name for the analytics container image"
  type        = string
  default     = "fleet-analytics"
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.container_image_name))
    error_message = "Container image name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "build_timeout" {
  description = "Timeout for container image build in seconds"
  type        = string
  default     = "600s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.build_timeout))
    error_message = "Build timeout must be in format '600s'."
  }
}

# Labels and tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "fleet-operations"
    environment = "production"
    managed-by  = "terraform"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Cost optimization
variable "enable_lifecycle_policy" {
  description = "Enable lifecycle policies for cost optimization"
  type        = bool
  default     = true
}

variable "nearline_age_days" {
  description = "Age in days when objects transition to Nearline storage"
  type        = number
  default     = 30
  validation {
    condition     = var.nearline_age_days >= 0 && var.nearline_age_days <= 365
    error_message = "Nearline age must be between 0 and 365 days."
  }
}

variable "coldline_age_days" {
  description = "Age in days when objects transition to Coldline storage"
  type        = number
  default     = 90
  validation {
    condition     = var.coldline_age_days >= 0 && var.coldline_age_days <= 365
    error_message = "Coldline age must be between 0 and 365 days."
  }
}