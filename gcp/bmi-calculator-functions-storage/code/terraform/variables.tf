# Variable definitions for BMI Calculator API Infrastructure
# This file defines all configurable parameters for the Terraform deployment

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 6 && length(var.project_id) <= 30
    error_message = "Project ID must be between 6 and 30 characters long."
  }
}

variable "region" {
  description = "The GCP region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for deploying zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "function_name" {
  description = "Name of the Cloud Function for BMI calculation"
  type        = string
  default     = "bmi-calculator"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.function_name))
    error_message = "Function name must start with a lowercase letter, followed by lowercase letters, numbers, or hyphens, and cannot end with a hyphen."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (will be suffixed with random string)"
  type        = string
  default     = "bmi-history"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_runtime" {
  description = "Runtime environment for the Cloud Function"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python37", "python38", "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "allow_unauthenticated" {
  description = "Whether to allow unauthenticated access to the Cloud Function"
  type        = bool
  default     = true
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    application = "bmi-calculator"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z]([a-z0-9_-]*[a-z0-9])?$", k))
    ])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "bucket_lifecycle_rules" {
  description = "Lifecycle rules for the storage bucket"
  type = list(object({
    action = object({
      type          = string
      storage_class = optional(string)
    })
    condition = object({
      age                   = optional(number)
      created_before        = optional(string)
      with_state           = optional(string)
      matches_storage_class = optional(list(string))
    })
  }))
  default = [
    {
      action = {
        type = "Delete"
      }
      condition = {
        age = 90 # Delete objects older than 90 days
      }
    }
  ]
}

variable "cors_origins" {
  description = "List of allowed CORS origins for the storage bucket"
  type        = list(string)
  default     = ["*"]
}

variable "function_source_archive_object" {
  description = "The source archive object name in the bucket (optional, for pre-uploaded source)"
  type        = string
  default     = null
}