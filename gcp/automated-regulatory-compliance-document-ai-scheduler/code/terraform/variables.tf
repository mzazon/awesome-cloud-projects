# Variables for the automated regulatory compliance system
# These variables allow customization of the infrastructure deployment

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 6 && can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
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
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
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
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "compliance"
  validation {
    condition     = length(var.resource_prefix) <= 20 && can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must be <= 20 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "document_ai_location" {
  description = "Location for Document AI processor (must support Document AI)"
  type        = string
  default     = "us"
  validation {
    condition = contains([
      "us", "eu", "asia-northeast1", "us-central1", "us-east1", "us-west1",
      "europe-west1", "europe-west2", "europe-west3", "asia-east1"
    ], var.document_ai_location)
    error_message = "Document AI location must be a supported region."
  }
}

variable "storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = number
  default     = 1024
  validation {
    condition     = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (in seconds)"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "report_function_memory" {
  description = "Memory allocation for report generation function (in MB)"
  type        = number
  default     = 512
  validation {
    condition     = var.report_function_memory >= 128 && var.report_function_memory <= 8192
    error_message = "Report function memory must be between 128 and 8192 MB."
  }
}

variable "report_function_timeout" {
  description = "Timeout for report generation function (in seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.report_function_timeout >= 60 && var.report_function_timeout <= 540
    error_message = "Report function timeout must be between 60 and 540 seconds."
  }
}

variable "bucket_lifecycle_age" {
  description = "Age in days after which objects in storage buckets are deleted"
  type        = number
  default     = 365
  validation {
    condition     = var.bucket_lifecycle_age >= 30
    error_message = "Bucket lifecycle age must be at least 30 days for compliance retention."
  }
}

variable "scheduler_timezone" {
  description = "Timezone for Cloud Scheduler jobs"
  type        = string
  default     = "America/New_York"
}

variable "daily_report_schedule" {
  description = "Cron schedule for daily compliance reports"
  type        = string
  default     = "0 8 * * *"
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.daily_report_schedule))
    error_message = "Daily report schedule must be a valid cron expression."
  }
}

variable "weekly_report_schedule" {
  description = "Cron schedule for weekly compliance reports"
  type        = string
  default     = "0 9 * * 1"
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.weekly_report_schedule))
    error_message = "Weekly report schedule must be a valid cron expression."
  }
}

variable "monthly_report_schedule" {
  description = "Cron schedule for monthly compliance reports"
  type        = string
  default     = "0 10 1 * *"
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.monthly_report_schedule))
    error_message = "Monthly report schedule must be a valid cron expression."
  }
}

variable "notification_email" {
  description = "Email address for compliance notifications and alerts"
  type        = string
  default     = "compliance@example.com"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on Cloud Storage buckets for audit trails"
  type        = bool
  default     = true
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for enhanced security"
  type        = bool
  default     = true
}

variable "force_destroy_buckets" {
  description = "Allow force destruction of buckets with contents (use with caution)"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "compliance-automation"
    managed-by  = "terraform"
    environment = "dev"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : 
      can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && 
      can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Labels must follow GCP naming conventions."
  }
}