# Input variables for the Lorem Ipsum Generator Cloud Functions recipe
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Cloud Functions 2nd generation."
  }
}

variable "function_name" {
  description = "Name of the Cloud Function for lorem ipsum generation"
  type        = string
  default     = "lorem-generator"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.function_name))
    error_message = "Function name must start with lowercase letter, contain only lowercase letters, numbers, and hyphens, and be up to 63 characters."
  }
}

variable "bucket_name_suffix" {
  description = "Suffix for the storage bucket name (will be prefixed with lorem-cache-)"
  type        = string
  default     = ""
  validation {
    condition     = var.bucket_name_suffix == "" || can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$", var.bucket_name_suffix))
    error_message = "Bucket name suffix must contain only lowercase letters, numbers, and hyphens, start and end with alphanumeric characters."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function (in MB)"
  type        = string
  default     = "256M"
  validation {
    condition = contains([
      "128M", "256M", "512M", "1G", "2G", "4G", "8G", "16G", "32G"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128M, 256M, 512M, 1G, 2G, 4G, 8G, 16G, 32G."
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

variable "max_instance_count" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.max_instance_count >= 1 && var.max_instance_count <= 1000
    error_message = "Max instance count must be between 1 and 1000."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "Storage class for the cache bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "environment" {
  description = "Environment label for resource organization"
  type        = string
  default     = "development"
  validation {
    condition = contains([
      "development", "staging", "production", "test"
    ], var.environment)
    error_message = "Environment must be one of: development, staging, production, test."
  }
}

variable "enable_cors" {
  description = "Enable CORS support for cross-origin web requests"
  type        = bool
  default     = true
}

variable "cors_origins" {
  description = "List of allowed origins for CORS requests"
  type        = list(string)
  default     = ["*"]
}

variable "labels" {
  description = "Additional labels to apply to resources"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}