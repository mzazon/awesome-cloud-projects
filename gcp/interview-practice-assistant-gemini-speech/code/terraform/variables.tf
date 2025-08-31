# Variables for Interview Practice Assistant Infrastructure
# Define all configurable parameters for the GCP deployment

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
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
      "asia-east1", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports all required services."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "interview-assistant"
  validation {
    condition     = length(var.prefix) <= 20 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.prefix))
    error_message = "Prefix must be 1-20 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bucket_name_suffix" {
  description = "Suffix for the Cloud Storage bucket name (auto-generated if empty)"
  type        = string
  default     = ""
}

variable "force_destroy_bucket" {
  description = "Whether to force destroy the bucket even if it contains objects"
  type        = bool
  default     = false
}

variable "bucket_lifecycle_age_days" {
  description = "Number of days after which objects in the bucket are deleted"
  type        = number
  default     = 30
  validation {
    condition     = var.bucket_lifecycle_age_days > 0 && var.bucket_lifecycle_age_days <= 365
    error_message = "Bucket lifecycle age must be between 1 and 365 days."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions in MB"
  type = object({
    speech        = number
    analysis      = number
    orchestration = number
  })
  default = {
    speech        = 512
    analysis      = 1024
    orchestration = 256
  }
  validation {
    condition = (
      var.function_memory_mb.speech >= 128 && var.function_memory_mb.speech <= 8192 &&
      var.function_memory_mb.analysis >= 128 && var.function_memory_mb.analysis <= 8192 &&
      var.function_memory_mb.orchestration >= 128 && var.function_memory_mb.orchestration <= 8192
    )
    error_message = "Function memory must be between 128 MB and 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Functions in seconds"
  type = object({
    speech        = number
    analysis      = number
    orchestration = number
  })
  default = {
    speech        = 120
    analysis      = 120
    orchestration = 300
  }
  validation {
    condition = (
      var.function_timeout_seconds.speech >= 1 && var.function_timeout_seconds.speech <= 540 &&
      var.function_timeout_seconds.analysis >= 1 && var.function_timeout_seconds.analysis <= 540 &&
      var.function_timeout_seconds.orchestration >= 1 && var.function_timeout_seconds.orchestration <= 540
    )
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "gemini_model" {
  description = "Vertex AI Gemini model to use for analysis"
  type        = string
  default     = "gemini-1.5-pro"
  validation {
    condition = contains([
      "gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"
    ], var.gemini_model)
    error_message = "Gemini model must be one of: gemini-1.5-pro, gemini-1.5-flash, gemini-1.0-pro."
  }
}

variable "speech_model" {
  description = "Speech-to-Text model to use for transcription"
  type        = string
  default     = "latest_long"
  validation {
    condition = contains([
      "latest_long", "latest_short", "command_and_search", "phone_call", "video"
    ], var.speech_model)
    error_message = "Speech model must be a valid Speech-to-Text model."
  }
}

variable "speech_language_code" {
  description = "Language code for Speech-to-Text API"
  type        = string
  default     = "en-US"
  validation {
    condition     = can(regex("^[a-z]{2}-[A-Z]{2}$", var.speech_language_code))
    error_message = "Language code must be in format 'xx-XX' (e.g., 'en-US')."
  }
}

variable "enable_enhanced_speech" {
  description = "Whether to use enhanced Speech-to-Text models"
  type        = bool
  default     = true
}

variable "allow_unauthenticated_functions" {
  description = "Whether to allow unauthenticated access to Cloud Functions"
  type        = bool
  default     = false
}

variable "service_account_name" {
  description = "Name of the service account for Cloud Functions"
  type        = string
  default     = "interview-assistant"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.service_account_name))
    error_message = "Service account name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "interview-practice"
    environment = "dev"
    managed-by  = "terraform"
  }
}

variable "create_sample_data" {
  description = "Whether to create sample interview questions dataset"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring notifications (optional)"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}