# Project and region configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 4 && can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region where resources will be created"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports Cloud Functions and Vertex AI."
  }
}

variable "zone" {
  description = "The GCP zone for resources that require zone specification"
  type        = string
  default     = "us-central1-a"
}

# Voice agent configuration
variable "voice_agent_name" {
  description = "Name for the voice support agent resources"
  type        = string
  default     = "voice-support-agent"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.voice_agent_name))
    error_message = "Voice agent name must be 3-63 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 1024
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Maximum execution time for the Cloud Function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "min_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "max_instances" {
  description = "Maximum number of function instances for scaling"
  type        = number
  default     = 100
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

# AI and model configuration
variable "vertex_ai_location" {
  description = "Location for Vertex AI resources (must support Gemini models)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east4", "us-west1", "us-west4",
      "europe-west1", "europe-west4", "asia-northeast1"
    ], var.vertex_ai_location)
    error_message = "Vertex AI location must support Gemini models."
  }
}

variable "gemini_model" {
  description = "Gemini model version to use for the voice agent"
  type        = string
  default     = "gemini-2.0-flash-exp"
  
  validation {
    condition = contains([
      "gemini-1.5-pro", "gemini-1.5-flash", "gemini-2.0-flash-exp"
    ], var.gemini_model)
    error_message = "Gemini model must be a supported version."
  }
}

variable "voice_name" {
  description = "Voice name for text-to-speech synthesis"
  type        = string
  default     = "Puck"
  
  validation {
    condition = contains([
      "Puck", "Charon", "Kore", "Fenrir", "Aoede", "Aria"
    ], var.voice_name)
    error_message = "Voice name must be a valid Gemini Live API voice."
  }
}

variable "language_code" {
  description = "Language code for speech processing"
  type        = string
  default     = "en-US"
  
  validation {
    condition = contains([
      "en-US", "en-GB", "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR", "ja-JP", "ko-KR", "zh-CN"
    ], var.language_code)
    error_message = "Language code must be supported by Google Speech APIs."
  }
}

# Security and access configuration
variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the Cloud Function"
  type        = bool
  default     = true
}

variable "cors_origins" {
  description = "List of allowed CORS origins for the voice agent API"
  type        = list(string)
  default     = ["*"]
}

# Monitoring and logging configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for the voice agent"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Logging level for the voice agent"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

variable "enable_tracing" {
  description = "Enable Cloud Trace for performance monitoring"
  type        = bool
  default     = true
}

# Resource tagging
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    application = "voice-support-agent"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label keys and values must follow GCP labeling requirements."
  }
}

# Customer service integration
variable "customer_database_enabled" {
  description = "Enable customer database simulation for demo purposes"
  type        = bool
  default     = true
}

variable "knowledge_base_enabled" {
  description = "Enable knowledge base search functionality"
  type        = bool
  default     = true
}

variable "ticket_system_enabled" {
  description = "Enable support ticket creation functionality"
  type        = bool
  default     = true
}