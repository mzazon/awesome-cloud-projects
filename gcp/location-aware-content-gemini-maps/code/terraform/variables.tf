# Variables for Location-Aware Content Generation with Gemini and Maps Infrastructure
# This file defines all configurable parameters for the Terraform deployment

variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for regional resources (Cloud Functions, Storage)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.region))
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (will be made globally unique)"
  type        = string
  default     = "location-content"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "function_name" {
  description = "Name of the Cloud Function for content generation"
  type        = string
  default     = "generate-location-content"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{1,63}$", var.function_name))
    error_message = "Function name must be 1-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = string
  default     = "512Mi"
  
  validation {
    condition = contains(["128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"], var.function_memory)
    error_message = "Function memory must be one of: 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
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

variable "function_max_instances" {
  description = "Maximum number of Cloud Function instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function max instances must be between 1 and 1000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of Cloud Function instances (0 for scale-to-zero)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Function min instances must be between 0 and 1000."
  }
}

variable "service_account_name" {
  description = "Name of the service account for the Cloud Function"
  type        = string
  default     = "location-content-sa"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{6,30}$", var.service_account_name))
    error_message = "Service account name must be 6-30 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access on the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age_days" {
  description = "Delete objects older than this many days (0 to disable)"
  type        = number
  default     = 365
  
  validation {
    condition     = var.bucket_lifecycle_age_days >= 0
    error_message = "Bucket lifecycle age must be 0 or positive."
  }
}

variable "function_source_dir" {
  description = "Directory containing the Cloud Function source code"
  type        = string
  default     = "../function-source"
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the Cloud Function (for demo purposes)"
  type        = bool
  default     = true
}

variable "cors_origins" {
  description = "CORS allowed origins for the Cloud Function"
  type        = list(string)
  default     = ["*"]
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "location-content-generation"
    component   = "content-api"
    environment = "demo"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for key, value in var.labels : can(regex("^[a-z0-9_-]{1,63}$", key))
    ])
    error_message = "Label keys must be 1-63 characters, lowercase letters, numbers, underscores, and hyphens only."
  }
}