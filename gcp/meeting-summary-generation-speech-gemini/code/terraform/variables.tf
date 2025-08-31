# Input Variables for Meeting Summary Generation Infrastructure
# These variables allow customization of the deployment

variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]){4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-central2", "europe-north1", "europe-southwest1", "europe-west1", "europe-west2",
      "europe-west3", "europe-west4", "europe-west6", "europe-west8", "europe-west9",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Cloud Functions Gen2."
  }
}

variable "bucket_location" {
  description = "Location for Cloud Storage bucket (region or multi-region)"
  type        = string
  default     = null # Will use var.region if not specified
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

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "Environment must start with letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 1024
  validation {
    condition     = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 MB and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Function execution timeout in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

variable "lifecycle_age_days" {
  description = "Number of days after which objects are deleted from storage bucket"
  type        = number
  default     = 30
  validation {
    condition     = var.lifecycle_age_days > 0 && var.lifecycle_age_days <= 3650
    error_message = "Lifecycle age must be between 1 and 3650 days (10 years)."
  }
}

variable "speech_language_code" {
  description = "Language code for speech recognition (e.g., en-US, es-ES, fr-FR)"
  type        = string
  default     = "en-US"
  validation {
    condition     = can(regex("^[a-z]{2}-[A-Z]{2}$", var.speech_language_code))
    error_message = "Language code must be in format 'xx-XX' (e.g., en-US, es-ES)."
  }
}

variable "speaker_count_min" {
  description = "Minimum number of speakers for diarization"
  type        = number
  default     = 2
  validation {
    condition     = var.speaker_count_min >= 1 && var.speaker_count_min <= 6
    error_message = "Minimum speaker count must be between 1 and 6."
  }
}

variable "speaker_count_max" {
  description = "Maximum number of speakers for diarization"
  type        = number
  default     = 6
  validation {
    condition     = var.speaker_count_max >= 2 && var.speaker_count_max <= 6
    error_message = "Maximum speaker count must be between 2 and 6."
  }
}

variable "vertex_ai_location" {
  description = "Location for Vertex AI resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west4",
      "europe-west1", "europe-west4", "asia-east1", "asia-northeast1",
      "asia-southeast1", "australia-southeast1"
    ], var.vertex_ai_location)
    error_message = "Vertex AI location must be a supported region for Vertex AI services."
  }
}

variable "gemini_model" {
  description = "Gemini model to use for content generation"
  type        = string
  default     = "gemini-1.5-pro"
  validation {
    condition = contains([
      "gemini-1.0-pro", "gemini-1.5-pro", "gemini-1.5-flash"
    ], var.gemini_model)
    error_message = "Gemini model must be one of the supported models."
  }
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage security"
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Enable object versioning on the storage bucket"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    project     = "meeting-summary"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for key, value in var.labels :
      can(regex("^[a-z][a-z0-9_-]*$", key)) && can(regex("^[a-z0-9_-]*$", value))
    ])
    error_message = "Label keys must start with lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain the same plus start with numbers."
  }
}