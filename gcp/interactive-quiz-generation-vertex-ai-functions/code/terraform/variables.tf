# Variable definitions for the Interactive Quiz Generation system
# These variables allow customization of the deployment

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports Vertex AI."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "quiz-gen"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,10}$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens, max 11 characters."
  }
}

variable "bucket_location" {
  description = "Location for Cloud Storage bucket (can be region or multi-region)"
  type        = string
  default     = "US"
}

variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = number
  default     = 512
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "delivery_function_memory" {
  description = "Memory allocation for quiz delivery function (in MB)"
  type        = number
  default     = 256
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.delivery_function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "scoring_function_memory" {
  description = "Memory allocation for quiz scoring function (in MB)"
  type        = number
  default     = 256
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.scoring_function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "enable_lifecycle_policy" {
  description = "Enable lifecycle policy on the Cloud Storage bucket for cost optimization"
  type        = bool
  default     = true
}

variable "nearline_days" {
  description = "Number of days before transitioning to Nearline storage"
  type        = number
  default     = 30
}

variable "coldline_days" {
  description = "Number of days before transitioning to Coldline storage"
  type        = number
  default     = 90
}

variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access (recommended for security)"
  type        = bool
  default     = true
}

variable "allowed_cors_origins" {
  description = "List of allowed CORS origins for the functions"
  type        = list(string)
  default     = ["*"]
}

variable "vertex_ai_location" {
  description = "Location for Vertex AI resources (should match region)"
  type        = string
  default     = "us-central1"
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
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "quiz-generation"
    managed-by  = "terraform"
  }
}

variable "enable_cloud_build" {
  description = "Enable Cloud Build API (required for function deployment)"
  type        = bool
  default     = true
}

variable "enable_artifact_registry" {
  description = "Enable Artifact Registry API (required for function deployment)"
  type        = bool
  default     = true
}