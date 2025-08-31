# Input variables for GCP image resizing infrastructure

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
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources (optional)"
  type        = string
  default     = "us-central1-a"
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

variable "function_name" {
  description = "Name of the Cloud Function for image resizing"
  type        = string
  default     = "resize-image-function"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "bucket_names" {
  description = "Custom names for the storage buckets (optional). If not provided, names will be auto-generated."
  type = object({
    original = optional(string)
    resized  = optional(string)
  })
  default = {}
}

variable "function_config" {
  description = "Configuration for the Cloud Function"
  type = object({
    memory_mb           = optional(number, 512)
    timeout_seconds     = optional(number, 120)
    max_instances      = optional(number, 10)
    min_instances      = optional(number, 0)
    runtime            = optional(string, "python311")
    entry_point        = optional(string, "resize_image")
  })
  default = {}
  
  validation {
    condition     = var.function_config.memory_mb >= 128 && var.function_config.memory_mb <= 8192
    error_message = "Function memory must be between 128 MB and 8192 MB."
  }
  
  validation {
    condition     = var.function_config.timeout_seconds >= 1 && var.function_config.timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "thumbnail_sizes" {
  description = "List of thumbnail sizes to generate (width x height in pixels)"
  type = list(object({
    width  = number
    height = number
  }))
  default = [
    { width = 150, height = 150 },
    { width = 300, height = 300 },
    { width = 600, height = 600 }
  ]
  
  validation {
    condition     = length(var.thumbnail_sizes) > 0
    error_message = "At least one thumbnail size must be specified."
  }
}

variable "supported_image_formats" {
  description = "List of supported image file extensions (lowercase)"
  type        = list(string)
  default     = ["jpg", "jpeg", "png", "bmp", "tiff"]
  
  validation {
    condition     = length(var.supported_image_formats) > 0
    error_message = "At least one image format must be supported."
  }
}

variable "storage_class" {
  description = "Storage class for the buckets"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "image-processing"
    solution    = "serverless-resize"
    managed_by  = "terraform"
  }
}

variable "enable_apis" {
  description = "Whether to enable required GCP APIs (set to false if APIs are already enabled)"
  type        = bool
  default     = true
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for enhanced security"
  type        = bool
  default     = true
}