# Variables for GCP Asset Inventory Documentation Infrastructure

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
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
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

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "asset-docs"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "storage_bucket_location" {
  description = "Location for the Cloud Storage bucket (multi-region or region)"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "ASIA",  # Multi-regional
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.storage_bucket_location)
    error_message = "Storage bucket location must be a valid GCP location."
  }
}

variable "storage_class" {
  description = "Storage class for the documentation bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function (MB)"
  type        = number
  default     = 512
  
  validation {
    condition     = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function execution (seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of concurrent function instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Function max instances must be between 1 and 3000."
  }
}

variable "schedule_cron" {
  description = "Cron schedule for automated documentation generation (UTC timezone)"
  type        = string
  default     = "0 9 * * *"  # Daily at 9 AM UTC
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.schedule_cron))
    error_message = "Schedule must be a valid cron expression (minute hour day month day_of_week)."
  }
}

variable "schedule_timezone" {
  description = "Timezone for the scheduled documentation generation"
  type        = string
  default     = "UTC"
}

variable "enable_versioning" {
  description = "Enable versioning on the documentation storage bucket"
  type        = bool
  default     = true
}

variable "enable_public_access_prevention" {
  description = "Enable public access prevention on the storage bucket"
  type        = bool
  default     = true
}

variable "lifecycle_age_days" {
  description = "Number of days after which to transition objects to a cheaper storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_age_days >= 1
    error_message = "Lifecycle age must be at least 1 day."
  }
}

variable "function_source_dir" {
  description = "Local directory containing Cloud Function source code"
  type        = string
  default     = "../../function-source"
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    application = "asset-documentation"
    managed-by  = "terraform"
  }
  
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Maximum of 64 labels are allowed per resource."
  }
}

variable "notification_email" {
  description = "Email address for notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}