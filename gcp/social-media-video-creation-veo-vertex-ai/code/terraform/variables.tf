# Variables for Social Media Video Creation with Veo 3 and Vertex AI

# Project and Location Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "us-east4", "us-south1", "northamerica-northeast1", "northamerica-northeast2",
      "southamerica-east1", "southamerica-west1", "europe-central2", "europe-north1",
      "europe-southwest1", "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "europe-west6", "europe-west8", "europe-west9", "europe-west10", "europe-west12",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-south2", "asia-southeast1", "asia-southeast2", "australia-southeast1",
      "australia-southeast2", "me-central1", "me-central2", "me-west1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Cloud Functions and Vertex AI."
  }
}

# Storage Configuration
variable "bucket_prefix" {
  description = "Prefix for the Cloud Storage bucket name (will be suffixed with random string)"
  type        = string
  default     = "social-videos"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_prefix))
    error_message = "Bucket prefix must be a valid Cloud Storage bucket name prefix (lowercase letters, numbers, hyphens, 3-63 characters)."
  }
}

variable "force_destroy_bucket" {
  description = "Allow deletion of bucket even if it contains objects (WARNING: enables force destroy)"
  type        = bool
  default     = false
}

# Function Configuration
variable "function_prefix" {
  description = "Prefix for Cloud Function names (will be suffixed with function type and random string)"
  type        = string
  default     = "video-gen"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.function_prefix))
    error_message = "Function prefix must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be 3-63 characters long."
  }
}

variable "function_source_dir" {
  description = "Local directory containing Cloud Function source code"
  type        = string
  default     = "./functions"
}

variable "max_instances" {
  description = "Maximum number of instances for each Cloud Function"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

variable "allow_unauthenticated_invocation" {
  description = "Allow unauthenticated invocation of Cloud Functions (WARNING: enables public access)"
  type        = bool
  default     = false
}

# Video Generation Configuration
variable "default_video_duration" {
  description = "Default duration for generated videos in seconds"
  type        = number
  default     = 8
  
  validation {
    condition     = var.default_video_duration >= 2 && var.default_video_duration <= 30
    error_message = "Video duration must be between 2 and 30 seconds."
  }
}

variable "default_aspect_ratio" {
  description = "Default aspect ratio for generated videos"
  type        = string
  default     = "9:16"
  
  validation {
    condition = contains([
      "16:9", "9:16", "1:1", "4:3", "3:4"
    ], var.default_aspect_ratio)
    error_message = "Aspect ratio must be one of: 16:9, 9:16, 1:1, 4:3, 3:4."
  }
}

variable "video_resolution" {
  description = "Resolution for generated videos"
  type        = string
  default     = "720p"
  
  validation {
    condition = contains([
      "480p", "720p", "1080p"
    ], var.video_resolution)
    error_message = "Video resolution must be one of: 480p, 720p, 1080p."
  }
}

# AI Model Configuration
variable "veo_model_version" {
  description = "Version of the Veo model to use for video generation"
  type        = string
  default     = "veo-3.0-generate-preview"
}

variable "gemini_model_version" {
  description = "Version of the Gemini model to use for content validation"
  type        = string
  default     = "gemini-2.0-flash-exp"
}

# Security and Access Configuration
variable "enable_audit_logs" {
  description = "Enable audit logging for all resources"
  type        = bool
  default     = true
}

variable "encryption_key_name" {
  description = "Cloud KMS key name for encrypting resources (optional, uses Google-managed keys if not specified)"
  type        = string
  default     = ""
}

# Monitoring and Alerting Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting for the pipeline"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Cost Management Configuration
variable "budget_amount" {
  description = "Monthly budget limit in USD for cost monitoring (0 to disable)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.budget_amount >= 0
    error_message = "Budget amount must be non-negative."
  }
}

variable "lifecycle_delete_age_days" {
  description = "Age in days after which to delete objects from storage bucket"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_delete_age_days >= 1 && var.lifecycle_delete_age_days <= 365
    error_message = "Lifecycle delete age must be between 1 and 365 days."
  }
}

variable "lifecycle_nearline_age_days" {
  description = "Age in days after which to move objects to Nearline storage class"
  type        = number
  default     = 7
  
  validation {
    condition     = var.lifecycle_nearline_age_days >= 1 && var.lifecycle_nearline_age_days <= 365
    error_message = "Lifecycle Nearline age must be between 1 and 365 days."
  }
}

# Labeling and Organization
variable "labels" {
  description = "Labels to apply to all resources for organization and cost tracking"
  type        = map(string)
  default = {
    environment = "development"
    project     = "video-generation"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens (max 63 characters)."
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label values must contain only lowercase letters, numbers, underscores, and hyphens (max 63 characters)."
  }
}

# Network Configuration (Optional)
variable "vpc_network" {
  description = "VPC network for Cloud Functions (optional, uses default network if not specified)"
  type        = string
  default     = ""
}

variable "vpc_subnet" {
  description = "VPC subnet for Cloud Functions (required if vpc_network is specified)"
  type        = string
  default     = ""
}

variable "vpc_connector" {
  description = "Serverless VPC Access connector name for Cloud Functions (optional)"
  type        = string
  default     = ""
}

# Development and Testing Configuration
variable "enable_debug_logging" {
  description = "Enable debug logging for Cloud Functions"
  type        = bool
  default     = false
}

variable "function_timeout_seconds" {
  description = "Timeout in seconds for video generation function"
  type        = number
  default     = 540
  
  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 3600
    error_message = "Function timeout must be between 60 and 3600 seconds."
  }
}

variable "validation_timeout_seconds" {
  description = "Timeout in seconds for validation function"
  type        = number
  default     = 300
  
  validation {
    condition     = var.validation_timeout_seconds >= 60 && var.validation_timeout_seconds <= 3600
    error_message = "Validation timeout must be between 60 and 3600 seconds."
  }
}

variable "monitor_timeout_seconds" {
  description = "Timeout in seconds for monitor function"
  type        = number
  default     = 60
  
  validation {
    condition     = var.monitor_timeout_seconds >= 30 && var.monitor_timeout_seconds <= 540
    error_message = "Monitor timeout must be between 30 and 540 seconds."
  }
}