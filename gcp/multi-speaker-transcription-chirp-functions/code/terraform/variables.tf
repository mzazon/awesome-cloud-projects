# Input variables for the multi-speaker transcription infrastructure
# These variables allow customization of the deployment

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region where resources will be deployed"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_name_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "speech-transcription"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_name_prefix))
    error_message = "Resource name prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "input_bucket_name" {
  description = "Name for the input audio files bucket (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "output_bucket_name" {
  description = "Name for the output transcripts bucket (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "function_name" {
  description = "Name for the Cloud Function"
  type        = string
  default     = "process-audio-transcription"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-_]*[a-zA-Z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, contain only letters, numbers, hyphens, and underscores, and end with a letter or number."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function (MB)"
  type        = number
  default     = 2048
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function (seconds)"
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
  default     = 5
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Maximum instances must be between 1 and 1000."
  }
}

variable "speech_model" {
  description = "Speech-to-Text model to use"
  type        = string
  default     = "chirp_3"
  validation {
    condition     = contains(["chirp", "chirp_2", "chirp_3", "latest_long", "latest_short"], var.speech_model)
    error_message = "Speech model must be one of the supported models."
  }
}

variable "speaker_diarization_config" {
  description = "Configuration for speaker diarization"
  type = object({
    enable_speaker_diarization = bool
    min_speaker_count         = number
    max_speaker_count         = number
  })
  default = {
    enable_speaker_diarization = true
    min_speaker_count         = 2
    max_speaker_count         = 6
  }
  validation {
    condition = (
      var.speaker_diarization_config.min_speaker_count >= 1 &&
      var.speaker_diarization_config.max_speaker_count <= 20 &&
      var.speaker_diarization_config.min_speaker_count <= var.speaker_diarization_config.max_speaker_count
    )
    error_message = "Speaker count must be between 1 and 20, with min <= max."
  }
}

variable "language_codes" {
  description = "List of language codes for transcription"
  type        = list(string)
  default     = ["en-US"]
  validation {
    condition     = length(var.language_codes) > 0
    error_message = "At least one language code must be specified."
  }
}

variable "bucket_storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.bucket_storage_class)
    error_message = "Bucket storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_lifecycle_age_days" {
  description = "Number of days before objects are deleted (0 to disable)"
  type        = number
  default     = 30
  validation {
    condition     = var.bucket_lifecycle_age_days >= 0
    error_message = "Lifecycle age must be non-negative."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    component = "speech-transcription"
    terraform = "true"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Labels must use lowercase letters, numbers, underscores, and hyphens only."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning for Cloud Storage buckets"
  type        = bool
  default     = false
}

variable "enable_bucket_encryption" {
  description = "Enable default encryption for Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "notification_topic_name" {
  description = "Name for the Pub/Sub topic for notifications (leave empty to disable)"
  type        = string
  default     = ""
}