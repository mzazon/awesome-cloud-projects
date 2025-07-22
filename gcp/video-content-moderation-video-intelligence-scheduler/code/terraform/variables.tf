# Required Variables
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, digits, and hyphens."
  }
}

# Core Configuration Variables
variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
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

# Resource Naming Variables
variable "bucket_name_suffix" {
  description = "Optional suffix for bucket name uniqueness. If null, a random suffix will be generated"
  type        = string
  default     = null
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness and organization"
  type        = string
  default     = "video-moderation"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

# Cloud Function Configuration
variable "function_timeout" {
  description = "Cloud Function timeout in seconds (max 540 for gen2)"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds for generation 2 functions."
  }
}

variable "function_memory" {
  description = "Cloud Function memory allocation (e.g., 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi)"
  type        = string
  default     = "1Gi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi", "16Gi", "32Gi"
    ], var.function_memory)
    error_message = "Function memory must be a valid memory size (128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi, 16Gi, or 32Gi)."
  }
}

variable "function_max_instances" {
  description = "Maximum number of Cloud Function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function max instances must be between 1 and 1000."
  }
}

variable "function_cpu" {
  description = "CPU allocation for Cloud Function (0.083, 0.167, 0.333, 0.583, 1, 2, 4, 8)"
  type        = string
  default     = "1"
  validation {
    condition = contains([
      "0.083", "0.167", "0.333", "0.583", "1", "2", "4", "8"
    ], var.function_cpu)
    error_message = "Function CPU must be a valid CPU allocation value."
  }
}

# Cloud Scheduler Configuration
variable "schedule_expression" {
  description = "Cron expression for the scheduler job (default: every 4 hours)"
  type        = string
  default     = "0 */4 * * *"
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.schedule_expression))
    error_message = "Schedule expression must be a valid cron expression (5 fields: minute hour day month day-of-week)."
  }
}

variable "schedule_timezone" {
  description = "Timezone for the scheduler job"
  type        = string
  default     = "America/New_York"
}

# Pub/Sub Configuration
variable "message_retention_duration" {
  description = "Pub/Sub message retention duration (e.g., 24h, 7d)"
  type        = string
  default     = "24h"
  validation {
    condition     = can(regex("^[0-9]+[smhd]$", var.message_retention_duration))
    error_message = "Message retention duration must be in format like '24h', '7d', '30m', etc."
  }
}

variable "ack_deadline_seconds" {
  description = "Pub/Sub subscription acknowledgment deadline in seconds"
  type        = number
  default     = 600
  validation {
    condition     = var.ack_deadline_seconds >= 10 && var.ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

# Cloud Storage Configuration
variable "storage_class" {
  description = "Cloud Storage bucket storage class"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable Cloud Storage bucket versioning"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age" {
  description = "Number of days after which to delete bucket objects (0 to disable)"
  type        = number
  default     = 365
  validation {
    condition     = var.bucket_lifecycle_age >= 0
    error_message = "Bucket lifecycle age must be 0 or greater (0 disables lifecycle management)."
  }
}

# Video Intelligence API Configuration
variable "explicit_content_threshold" {
  description = "Threshold for explicit content detection (VERY_UNLIKELY=1, UNLIKELY=2, POSSIBLE=3, LIKELY=4, VERY_LIKELY=5)"
  type        = number
  default     = 3
  validation {
    condition     = var.explicit_content_threshold >= 1 && var.explicit_content_threshold <= 5
    error_message = "Explicit content threshold must be between 1 (VERY_UNLIKELY) and 5 (VERY_LIKELY)."
  }
}

variable "explicit_content_ratio_threshold" {
  description = "Ratio threshold for flagging content based on explicit frames (0.0 to 1.0)"
  type        = number
  default     = 0.1
  validation {
    condition     = var.explicit_content_ratio_threshold >= 0.0 && var.explicit_content_ratio_threshold <= 1.0
    error_message = "Explicit content ratio threshold must be between 0.0 and 1.0."
  }
}

# IAM and Security Configuration
variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_public_access_prevention" {
  description = "Prevent public access to Cloud Storage bucket"
  type        = bool
  default     = true
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "demo"
    project     = "video-moderation"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}