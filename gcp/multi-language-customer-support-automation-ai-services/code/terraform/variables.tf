# Variables for Multi-Language Customer Support Automation Infrastructure
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
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports AI services."
  }
}

variable "zone" {
  description = "The Google Cloud zone for resource deployment"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "firestore_region" {
  description = "The region for Firestore database (must be a multi-region or region)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central", "us-east1", "us-west1", "europe-west1", "asia-northeast1",
      "nam5", "eur3", "asia-southeast1", "australia-southeast1"
    ], var.firestore_region)
    error_message = "Firestore region must be a valid Firestore location."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and naming"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "cost_center" {
  description = "Cost center for billing and resource tracking"
  type        = string
  default     = "customer-support"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}[a-z0-9]$", var.cost_center))
    error_message = "Cost center must be 3-64 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "force_destroy_bucket" {
  description = "Whether to force destroy Cloud Storage buckets when running terraform destroy"
  type        = bool
  default     = true
  
  validation {
    condition     = can(tobool(var.force_destroy_bucket))
    error_message = "Force destroy bucket must be a boolean value."
  }
}

variable "supported_languages" {
  description = "List of supported language codes for speech recognition and translation"
  type        = list(string)
  default = [
    "en-US",   # English (United States)
    "es-ES",   # Spanish (Spain)
    "fr-FR",   # French (France)
    "de-DE",   # German (Germany)
    "it-IT",   # Italian (Italy)
    "pt-BR",   # Portuguese (Brazil)
    "ja-JP",   # Japanese (Japan)
    "ko-KR",   # Korean (South Korea)
    "zh-CN"    # Chinese (Simplified, China)
  ]
  
  validation {
    condition     = length(var.supported_languages) > 0 && length(var.supported_languages) <= 20
    error_message = "Must specify between 1 and 20 supported languages."
  }
  
  validation {
    condition = alltrue([
      for lang in var.supported_languages : can(regex("^[a-z]{2}-[A-Z]{2}$", lang))
    ])
    error_message = "Language codes must be in format 'xx-XX' (e.g., 'en-US', 'es-ES')."
  }
}

variable "language_names" {
  description = "Mapping of language codes to human-readable names"
  type        = map(string)
  default = {
    "en-US" = "English (United States)"
    "es-ES" = "Spanish (Spain)"
    "fr-FR" = "French (France)"
    "de-DE" = "German (Germany)"
    "it-IT" = "Italian (Italy)"
    "pt-BR" = "Portuguese (Brazil)"
    "ja-JP" = "Japanese (Japan)"
    "ko-KR" = "Korean (South Korea)"
    "zh-CN" = "Chinese (Simplified)"
  }
  
  validation {
    condition     = length(var.language_names) > 0
    error_message = "Language names mapping cannot be empty."
  }
}

variable "tts_voice_config" {
  description = "Text-to-Speech voice configuration for different languages"
  type = map(object({
    name         = string
    ssmlGender   = string
    languageCode = string
  }))
  default = {
    "en-US" = {
      name         = "en-US-Neural2-J"
      ssmlGender   = "FEMALE"
      languageCode = "en-US"
    }
    "es-ES" = {
      name         = "es-ES-Neural2-F"
      ssmlGender   = "FEMALE"
      languageCode = "es-ES"
    }
    "fr-FR" = {
      name         = "fr-FR-Neural2-C"
      ssmlGender   = "FEMALE"
      languageCode = "fr-FR"
    }
    "de-DE" = {
      name         = "de-DE-Neural2-F"
      ssmlGender   = "FEMALE"
      languageCode = "de-DE"
    }
    "it-IT" = {
      name         = "it-IT-Neural2-A"
      ssmlGender   = "FEMALE"
      languageCode = "it-IT"
    }
    "pt-BR" = {
      name         = "pt-BR-Neural2-C"
      ssmlGender   = "FEMALE"
      languageCode = "pt-BR"
    }
    "ja-JP" = {
      name         = "ja-JP-Neural2-B"
      ssmlGender   = "FEMALE"
      languageCode = "ja-JP"
    }
    "ko-KR" = {
      name         = "ko-KR-Neural2-A"
      ssmlGender   = "FEMALE"
      languageCode = "ko-KR"
    }
    "zh-CN" = {
      name         = "cmn-CN-Standard-A"
      ssmlGender   = "FEMALE"
      languageCode = "cmn-CN"
    }
  }
  
  validation {
    condition     = length(var.tts_voice_config) > 0
    error_message = "TTS voice configuration cannot be empty."
  }
}

variable "cors_origins" {
  description = "CORS origins for Cloud Storage bucket (for web uploads)"
  type        = list(string)
  default     = ["*"]
  
  validation {
    condition     = length(var.cors_origins) > 0
    error_message = "CORS origins cannot be empty."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 100
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Function max instances must be between 1 and 3000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances (0 for scale-to-zero)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Function min instances must be between 0 and 1000."
  }
}

variable "error_rate_threshold" {
  description = "Error rate threshold for alerting (as a decimal, e.g., 0.05 for 5%)"
  type        = number
  default     = 0.05
  
  validation {
    condition     = var.error_rate_threshold >= 0.001 && var.error_rate_threshold <= 1.0
    error_message = "Error rate threshold must be between 0.001 (0.1%) and 1.0 (100%)."
  }
}

variable "notification_channels" {
  description = "List of notification channel IDs for alerting"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for channel in var.notification_channels : can(regex("^projects/.+/notificationChannels/.+$", channel))
    ])
    error_message = "Notification channels must be in format 'projects/{project}/notificationChannels/{channel_id}'."
  }
}

variable "speech_model" {
  description = "Speech-to-Text model to use for transcription"
  type        = string
  default     = "latest_long"
  
  validation {
    condition = contains([
      "latest_long", "latest_short", "command_and_search", "phone_call", "video", "default"
    ], var.speech_model)
    error_message = "Speech model must be one of: latest_long, latest_short, command_and_search, phone_call, video, default."
  }
}

variable "enable_speaker_diarization" {
  description = "Whether to enable speaker diarization in speech recognition"
  type        = bool
  default     = true
}

variable "max_speaker_count" {
  description = "Maximum number of speakers for diarization"
  type        = number
  default     = 2
  
  validation {
    condition     = var.max_speaker_count >= 1 && var.max_speaker_count <= 6
    error_message = "Max speaker count must be between 1 and 6."
  }
}

variable "sentiment_thresholds" {
  description = "Sentiment analysis thresholds for different categories"
  type = object({
    negative = number
    positive = number
    urgency  = number
  })
  default = {
    negative = -0.2
    positive = 0.2
    urgency  = -0.5
  }
  
  validation {
    condition = (
      var.sentiment_thresholds.negative >= -1.0 && var.sentiment_thresholds.negative <= 1.0 &&
      var.sentiment_thresholds.positive >= -1.0 && var.sentiment_thresholds.positive <= 1.0 &&
      var.sentiment_thresholds.urgency >= -1.0 && var.sentiment_thresholds.urgency <= 1.0
    )
    error_message = "Sentiment thresholds must be between -1.0 and 1.0."
  }
  
  validation {
    condition     = var.sentiment_thresholds.urgency <= var.sentiment_thresholds.negative
    error_message = "Urgency threshold must be less than or equal to negative threshold."
  }
}

variable "enable_monitoring" {
  description = "Whether to enable monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_firestore_backups" {
  description = "Whether to enable automatic Firestore backups"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain Firestore backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

variable "storage_class" {
  description = "Default storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Whether to enable versioning on Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "lifecycle_age_days" {
  description = "Number of days after which to delete old versions of objects"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_age_days >= 1 && var.lifecycle_age_days <= 3650
    error_message = "Lifecycle age days must be between 1 and 3650."
  }
}

variable "enable_audit_logs" {
  description = "Whether to enable audit logging for the project"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Cloud Logging"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653."
  }
}

variable "enable_vpc_connector" {
  description = "Whether to create a VPC connector for Cloud Functions"
  type        = bool
  default     = false
}

variable "vpc_connector_cidr" {
  description = "CIDR range for the VPC connector"
  type        = string
  default     = "10.8.0.0/28"
  
  validation {
    condition     = can(cidrhost(var.vpc_connector_cidr, 0))
    error_message = "VPC connector CIDR must be a valid CIDR block."
  }
}

variable "enable_private_google_access" {
  description = "Whether to enable Private Google Access for VPC"
  type        = bool
  default     = false
}

variable "function_timeout_seconds" {
  description = "Timeout in seconds for Cloud Functions"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "1Gi"
  
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
  }
}

variable "function_cpu" {
  description = "CPU allocation for Cloud Functions"
  type        = string
  default     = "1"
  
  validation {
    condition = contains([
      "0.083", "0.167", "0.333", "0.583", "1", "2", "4", "6", "8"
    ], var.function_cpu)
    error_message = "Function CPU must be one of: 0.083, 0.167, 0.333, 0.583, 1, 2, 4, 6, 8."
  }
}

variable "workflow_timeout_seconds" {
  description = "Timeout in seconds for Cloud Workflows"
  type        = number
  default     = 300
  
  validation {
    condition     = var.workflow_timeout_seconds >= 1 && var.workflow_timeout_seconds <= 31536000
    error_message = "Workflow timeout must be between 1 second and 1 year (31536000 seconds)."
  }
}