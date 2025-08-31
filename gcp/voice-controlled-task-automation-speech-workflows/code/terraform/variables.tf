# Input variables for voice-controlled task automation infrastructure

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "The project_id must not be empty."
  }
}

variable "region" {
  description = "The GCP region for resources deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-central2", "europe-north1", "europe-southwest1", "europe-west1", "europe-west2", 
      "europe-west3", "europe-west4", "europe-west6", "europe-west8", "europe-west9",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-south2", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "The region must be a valid GCP region that supports Cloud Functions and Workflows."
  }
}

variable "zone" {
  description = "The GCP zone within the region"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "name_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "voice-automation"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# Storage Configuration
variable "bucket_location" {
  description = "Location for the Cloud Storage bucket (multi-region, region, or zone)"
  type        = string
  default     = "US"
}

variable "bucket_storage_class" {
  description = "Storage class for the audio files bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "audio_file_retention_days" {
  description = "Number of days to retain audio files before automatic deletion"
  type        = number
  default     = 7
  
  validation {
    condition     = var.audio_file_retention_days > 0 && var.audio_file_retention_days <= 365
    error_message = "Retention days must be between 1 and 365."
  }
}

# Cloud Function Configuration
variable "voice_processor_memory" {
  description = "Memory allocation for voice processing function in MB"
  type        = number
  default     = 512
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.voice_processor_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "voice_processor_timeout" {
  description = "Timeout for voice processing function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.voice_processor_timeout >= 1 && var.voice_processor_timeout <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

variable "task_processor_memory" {
  description = "Memory allocation for task processing function in MB"
  type        = number
  default     = 256
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.task_processor_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "task_processor_timeout" {
  description = "Timeout for task processing function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.task_processor_timeout >= 1 && var.task_processor_timeout <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

# Cloud Tasks Configuration
variable "task_queue_max_dispatches_per_second" {
  description = "Maximum task dispatches per second for the queue"
  type        = number
  default     = 10
  
  validation {
    condition     = var.task_queue_max_dispatches_per_second > 0 && var.task_queue_max_dispatches_per_second <= 1000
    error_message = "Max dispatches per second must be between 1 and 1000."
  }
}

variable "task_queue_max_concurrent_dispatches" {
  description = "Maximum concurrent dispatches for the queue"
  type        = number
  default     = 5
  
  validation {
    condition     = var.task_queue_max_concurrent_dispatches > 0 && var.task_queue_max_concurrent_dispatches <= 1000
    error_message = "Max concurrent dispatches must be between 1 and 1000."
  }
}

# Speech-to-Text Configuration
variable "speech_language_code" {
  description = "Default language code for speech recognition"
  type        = string
  default     = "en-US"
  
  validation {
    condition = contains([
      "en-US", "en-GB", "en-AU", "en-CA", "en-IN", "en-NZ", "en-ZA",
      "es-ES", "es-MX", "es-US", "fr-FR", "fr-CA", "de-DE", "it-IT",
      "pt-BR", "pt-PT", "ja-JP", "ko-KR", "zh-CN", "zh-TW", "hi-IN"
    ], var.speech_language_code)
    error_message = "Language code must be a supported Speech-to-Text language."
  }
}

variable "speech_model" {
  description = "Speech recognition model to use"
  type        = string
  default     = "latest_long"
  
  validation {
    condition = contains([
      "latest_long", "latest_short", "command_and_search", "phone_call", "video"
    ], var.speech_model)
    error_message = "Speech model must be one of the supported models."
  }
}

# Security and Access Configuration
variable "allow_unauthenticated_functions" {
  description = "Whether to allow unauthenticated access to Cloud Functions (for testing only)"
  type        = bool
  default     = false
}

variable "enable_api_gateway" {
  description = "Whether to create an API Gateway for secure access"
  type        = bool
  default     = false
}

# Monitoring and Logging
variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring and alerting"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653 (10 years)."
  }
}

# Resource Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    "application" = "voice-automation"
    "component"   = "serverless"
    "managed-by"  = "terraform"
  }
}