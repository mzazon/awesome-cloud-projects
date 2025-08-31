# Variables for GCP Unit Converter API Infrastructure
# This file defines all configurable parameters for the Terraform deployment

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for deploying resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "function_name" {
  description = "Name of the Cloud Function for unit conversion API"
  type        = string
  default     = "unit-converter"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.function_name))
    error_message = "Function name must start with a letter and contain only lowercase letters, numbers, and hyphens (max 63 characters)."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (will be combined with project ID and random suffix)"
  type        = string
  default     = "conversion-history"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must be 3-40 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_runtime" {
  description = "Python runtime version for the Cloud Function"
  type        = string
  default     = "python312"
  
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Python version (python38, python39, python310, python311, or python312)."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 256
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, or 8192 MB."
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
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "enable_cors" {
  description = "Enable CORS headers in the Cloud Function for web browser compatibility"
  type        = bool
  default     = true
}

variable "enable_public_access" {
  description = "Enable public access to the Cloud Function (allows unauthenticated requests)"
  type        = bool
  default     = true
}

variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access for Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_rules" {
  description = "Lifecycle management rules for the Cloud Storage bucket"
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
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
      condition = {
        age = 30
      }
    },
    {
      action = {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
      condition = {
        age = 90
      }
    }
  ]
}

variable "labels" {
  description = "Labels to apply to all resources for organization and cost tracking"
  type        = map(string)
  default = {
    application = "unit-converter"
    environment = "development"
    managed-by  = "terraform"
    recipe-id   = "a7f3e9b2"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens (max 63 characters)."
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label values must contain only lowercase letters, numbers, underscores, and hyphens (max 63 characters)."
  }
}