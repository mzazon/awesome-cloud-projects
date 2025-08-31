# Input variables for Educational Content Generation Infrastructure
# These variables allow customization of the deployment for different environments and requirements

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Cloud Functions and Vertex AI."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and organization"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "function_name_prefix" {
  description = "Prefix for the Cloud Function name (random suffix will be added)"
  type        = string
  default     = "content-generator"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name_prefix))
    error_message = "Function name prefix must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a lowercase letter or number."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (random suffix will be added)"
  type        = string
  default     = "edu-audio-content"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must start and end with a lowercase letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "max_function_instances" {
  description = "Maximum number of Cloud Function instances for auto-scaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_function_instances >= 1 && var.max_function_instances <= 1000
    error_message = "Maximum function instances must be between 1 and 1000."
  }
}

variable "enable_public_access" {
  description = "Whether to enable public access to the Cloud Function and storage bucket"
  type        = bool
  default     = true
}

variable "firestore_deletion_policy" {
  description = "Deletion policy for Firestore database"
  type        = string
  default     = "DELETE"
  
  validation {
    condition     = contains(["ABANDON", "DELETE"], var.firestore_deletion_policy)
    error_message = "Firestore deletion policy must be either 'ABANDON' or 'DELETE'."
  }
}

variable "storage_lifecycle_age_days" {
  description = "Number of days after which audio files will be moved to Nearline storage class"
  type        = number
  default     = 365
  
  validation {
    condition     = var.storage_lifecycle_age_days >= 30
    error_message = "Storage lifecycle age must be at least 30 days."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Function execution in seconds"
  type        = number
  default     = 540
  
  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 3600
    error_message = "Function timeout must be between 60 and 3600 seconds."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function"
  type        = string
  default     = "1Gi"
  
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi", "16Gi", "32Gi"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi, 16Gi, 32Gi."
  }
}

variable "default_voice_name" {
  description = "Default Text-to-Speech voice for audio generation"
  type        = string
  default     = "en-US-Studio-M"
  
  validation {
    condition     = can(regex("^[a-zA-Z]{2}-[a-zA-Z]{2}-", var.default_voice_name))
    error_message = "Voice name must follow the pattern language-region-voicename (e.g., en-US-Studio-M)."
  }
}

variable "cors_max_age_seconds" {
  description = "CORS max age in seconds for storage bucket"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.cors_max_age_seconds >= 0 && var.cors_max_age_seconds <= 86400
    error_message = "CORS max age must be between 0 and 86400 seconds (24 hours)."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "resource_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.resource_labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "gemini_model_name" {
  description = "Vertex AI Gemini model name for content generation"
  type        = string
  default     = "gemini-2.5-flash"
  
  validation {
    condition = contains([
      "gemini-2.5-flash", "gemini-1.5-pro", "gemini-1.5-flash"
    ], var.gemini_model_name)
    error_message = "Gemini model must be one of: gemini-2.5-flash, gemini-1.5-pro, gemini-1.5-flash."
  }
}

variable "tts_speaking_rate" {
  description = "Default speaking rate for Text-to-Speech (0.25 to 4.0)"
  type        = number
  default     = 0.9
  
  validation {
    condition     = var.tts_speaking_rate >= 0.25 && var.tts_speaking_rate <= 4.0
    error_message = "TTS speaking rate must be between 0.25 and 4.0."
  }
}

variable "tts_pitch" {
  description = "Default pitch for Text-to-Speech (-20.0 to 20.0)"
  type        = number
  default     = 0.0
  
  validation {
    condition     = var.tts_pitch >= -20.0 && var.tts_pitch <= 20.0
    error_message = "TTS pitch must be between -20.0 and 20.0."
  }
}