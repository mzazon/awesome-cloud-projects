# Core project and location variables
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-east4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Vertex AI."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Storage configuration variables
variable "input_bucket_name" {
  description = "Name for the input bucket storing creative briefs (will be suffixed with random string)"
  type        = string
  default     = "video-briefs"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_]*[a-z0-9]$", var.input_bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

variable "output_bucket_name" {
  description = "Name for the output bucket storing generated videos (will be suffixed with random string)"
  type        = string
  default     = "generated-videos"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_]*[a-z0-9]$", var.output_bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

variable "storage_class" {
  description = "Storage class for Cloud Storage buckets"
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
  description = "Enable versioning on storage buckets for content protection"
  type        = bool
  default     = true
}

# Cloud Functions configuration variables
variable "functions_runtime" {
  description = "Runtime version for Cloud Functions"
  type        = string
  default     = "python312"
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312"
    ], var.functions_runtime)
    error_message = "Runtime must be a supported Python version."
  }
}

variable "video_generation_memory" {
  description = "Memory allocation for video generation function in MB"
  type        = number
  default     = 1024
  validation {
    condition     = var.video_generation_memory >= 128 && var.video_generation_memory <= 8192
    error_message = "Memory must be between 128 MB and 8192 MB."
  }
}

variable "video_generation_timeout" {
  description = "Timeout for video generation function in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.video_generation_timeout >= 60 && var.video_generation_timeout <= 3600
    error_message = "Timeout must be between 60 and 3600 seconds."
  }
}

variable "orchestrator_memory" {
  description = "Memory allocation for orchestrator function in MB"
  type        = number
  default     = 512
  validation {
    condition     = var.orchestrator_memory >= 128 && var.orchestrator_memory <= 8192
    error_message = "Memory must be between 128 MB and 8192 MB."
  }
}

variable "orchestrator_timeout" {
  description = "Timeout for orchestrator function in seconds"
  type        = number
  default     = 900
  validation {
    condition     = var.orchestrator_timeout >= 60 && var.orchestrator_timeout <= 3600
    error_message = "Timeout must be between 60 and 3600 seconds."
  }
}

# Cloud Scheduler configuration variables
variable "automated_schedule" {
  description = "Cron expression for automated video generation schedule"
  type        = string
  default     = "0 9 * * MON,WED,FRI"
  validation {
    condition     = can(regex("^[0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9A-Z*,/-]+$", var.automated_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "schedule_timezone" {
  description = "Timezone for scheduled jobs"
  type        = string
  default     = "America/New_York"
}

variable "automated_batch_size" {
  description = "Number of briefs to process in automated batches"
  type        = number
  default     = 10
  validation {
    condition     = var.automated_batch_size >= 1 && var.automated_batch_size <= 50
    error_message = "Batch size must be between 1 and 50."
  }
}

variable "manual_batch_size" {
  description = "Number of briefs to process in manual batches"
  type        = number
  default     = 5
  validation {
    condition     = var.manual_batch_size >= 1 && var.manual_batch_size <= 20
    error_message = "Manual batch size must be between 1 and 20."
  }
}

# Service account and IAM configuration
variable "service_account_name" {
  description = "Name for the video generation service account (will be suffixed with random string)"
  type        = string
  default     = "video-gen-sa"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.service_account_name))
    error_message = "Service account name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "service_account_display_name" {
  description = "Display name for the video generation service account"
  type        = string
  default     = "Video Generation Service Account"
}

# Veo 3 model configuration
variable "veo_model_name" {
  description = "Name of the Veo 3 model to use for video generation"
  type        = string
  default     = "veo-3.0-generate-preview"
}

variable "default_video_resolution" {
  description = "Default resolution for generated videos"
  type        = string
  default     = "1080p"
  validation {
    condition = contains([
      "720p", "1080p"
    ], var.default_video_resolution)
    error_message = "Resolution must be either 720p or 1080p."
  }
}

variable "default_video_duration" {
  description = "Default duration for generated videos in seconds"
  type        = number
  default     = 8
  validation {
    condition     = var.default_video_duration >= 4 && var.default_video_duration <= 8
    error_message = "Video duration must be between 4 and 8 seconds for Veo 3."
  }
}

# Monitoring and alerting configuration
variable "enable_monitoring" {
  description = "Enable monitoring and alerting for the video generation pipeline"
  type        = bool
  default     = true
}

variable "alert_notification_email" {
  description = "Email address for receiving alerts and notifications"
  type        = string
  default     = ""
  validation {
    condition     = var.alert_notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

variable "function_error_threshold" {
  description = "Number of function errors before triggering an alert"
  type        = number
  default     = 5
  validation {
    condition     = var.function_error_threshold >= 1 && var.function_error_threshold <= 50
    error_message = "Error threshold must be between 1 and 50."
  }
}

# Resource naming and tagging
variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "video-gen"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition = contains([
      "dev", "staging", "prod", "test"
    ], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    application = "video-generation"
    managed-by  = "terraform"
    component   = "ai-content-creation"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens, with keys starting with a letter."
  }
}

# Cost optimization variables
variable "enable_spot_instances" {
  description = "Use spot instances where applicable for cost optimization"
  type        = bool
  default     = false
}

variable "lifecycle_delete_age_days" {
  description = "Number of days after which to delete old video files for cost optimization"
  type        = number
  default     = 90
  validation {
    condition     = var.lifecycle_delete_age_days >= 30 && var.lifecycle_delete_age_days <= 365
    error_message = "Lifecycle delete age must be between 30 and 365 days."
  }
}