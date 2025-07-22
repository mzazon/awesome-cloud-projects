# Project Configuration
variable "project_id" {
  description = "Google Cloud Project ID for the translation platform"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 6 && length(var.project_id) <= 30
    error_message = "Project ID must be between 6 and 30 characters."
  }
}

variable "region" {
  description = "Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

# Service Configuration
variable "service_name" {
  description = "Name for the Cloud Run translation service"
  type        = string
  default     = "translation-service"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service_name))
    error_message = "Service name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "service_account_name" {
  description = "Name for the service account used by translation services"
  type        = string
  default     = "translation-service"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service_account_name))
    error_message = "Service account name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Cloud Run Configuration
variable "cpu_limit" {
  description = "CPU limit for Cloud Run service"
  type        = string
  default     = "2"
  
  validation {
    condition     = contains(["1", "2", "4", "6", "8"], var.cpu_limit)
    error_message = "CPU limit must be one of: 1, 2, 4, 6, 8."
  }
}

variable "memory_limit" {
  description = "Memory limit for Cloud Run service"
  type        = string
  default     = "2Gi"
  
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.memory_limit))
    error_message = "Memory limit must be in format like '2Gi' or '512Mi'."
  }
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "concurrency_limit" {
  description = "Maximum concurrent requests per Cloud Run instance"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.concurrency_limit >= 1 && var.concurrency_limit <= 1000
    error_message = "Concurrency limit must be between 1 and 1000."
  }
}

variable "timeout_seconds" {
  description = "Request timeout for Cloud Run service in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

# Firestore Configuration
variable "firestore_location" {
  description = "Location for Firestore database"
  type        = string
  default     = "nam5"
  
  validation {
    condition = contains([
      "nam5", "eur3", "asia-northeast1", "us-central1", "us-east1", "us-west2",
      "europe-west1", "europe-west3", "asia-east1", "asia-south1"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or region identifier."
  }
}

# Storage Configuration
variable "storage_class" {
  description = "Storage class for audio files bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "audio_retention_days" {
  description = "Number of days to retain audio files before automatic deletion"
  type        = number
  default     = 30
  
  validation {
    condition     = var.audio_retention_days >= 1 && var.audio_retention_days <= 365
    error_message = "Audio retention days must be between 1 and 365."
  }
}

# Pub/Sub Configuration
variable "message_retention_duration" {
  description = "Message retention duration for Pub/Sub subscription"
  type        = string
  default     = "604800s" # 7 days
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.message_retention_duration))
    error_message = "Message retention duration must be in seconds format like '604800s'."
  }
}

# Security Configuration
variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to Cloud Run service"
  type        = bool
  default     = true
}

variable "enable_audit_logs" {
  description = "Enable audit logs for translation services"
  type        = bool
  default     = true
}

# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Source Language Configuration
variable "default_source_language" {
  description = "Default source language for translation"
  type        = string
  default     = "en-US"
}

variable "default_target_languages" {
  description = "Default target languages for translation"
  type        = list(string)
  default     = ["es", "fr", "de", "ja"]
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable detailed monitoring and alerting"
  type        = bool
  default     = true
}

# Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "real-time-translation"
    managed-by  = "terraform"
    environment = "dev"
  }
}