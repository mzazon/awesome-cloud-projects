# Input variables for the Text-to-Speech converter infrastructure
# These variables allow customization of the deployment

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
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

variable "bucket_name" {
  description = "Name for the Cloud Storage bucket to store audio files. Must be globally unique."
  type        = string
  default     = null
  validation {
    condition = var.bucket_name == null || can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must be 3-63 characters, start and end with alphanumeric characters, and contain only lowercase letters, numbers, dots, hyphens, and underscores."
  }
}

variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE", "REGIONAL", "MULTI_REGIONAL"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE, REGIONAL, MULTI_REGIONAL."
  }
}

variable "enable_public_access" {
  description = "Whether to enable public read access to the storage bucket"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_enabled" {
  description = "Whether to enable lifecycle management for the storage bucket"
  type        = bool
  default     = true
}

variable "lifecycle_delete_age" {
  description = "Number of days after which objects are automatically deleted (0 to disable)"
  type        = number
  default     = 30
  validation {
    condition     = var.lifecycle_delete_age >= 0 && var.lifecycle_delete_age <= 3650
    error_message = "Lifecycle delete age must be between 0 and 3650 days."
  }
}

variable "enable_cors" {
  description = "Whether to enable CORS for the storage bucket"
  type        = bool
  default     = true
}

variable "cors_max_age_seconds" {
  description = "Maximum age in seconds for CORS preflight requests"
  type        = number
  default     = 3600
}

variable "enable_versioning" {
  description = "Whether to enable versioning for the storage bucket"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "text-to-speech-converter"
    environment = "demo"
    managed-by  = "terraform"
  }
}

variable "enable_uniform_bucket_level_access" {
  description = "Whether to enable uniform bucket-level access"
  type        = bool
  default     = true
}

variable "prevent_destroy" {
  description = "Whether to prevent destruction of the storage bucket"
  type        = bool
  default     = false
}