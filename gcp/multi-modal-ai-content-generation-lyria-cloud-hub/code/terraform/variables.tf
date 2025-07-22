# Variables for Multi-Modal AI Content Generation Platform with Lyria and Vertex AI
# This file defines all configurable parameters for the infrastructure deployment

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
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region with Vertex AI support."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
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

variable "content_bucket_name" {
  description = "Name for the content storage bucket (will be suffixed with random string)"
  type        = string
  default     = "content-generation"
  validation {
    condition     = length(var.content_bucket_name) >= 3 && length(var.content_bucket_name) <= 60
    error_message = "Bucket name must be between 3 and 60 characters."
  }
}

variable "content_bucket_location" {
  description = "Location for content storage bucket"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", 
      "europe-west1", "asia-east1", "asia-northeast1"
    ], var.content_bucket_location)
    error_message = "Bucket location must be a valid Google Cloud Storage location."
  }
}

variable "content_bucket_storage_class" {
  description = "Storage class for content bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.content_bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for content bucket"
  type        = bool
  default     = true
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for content bucket"
  type        = bool
  default     = true
}

variable "service_account_name" {
  description = "Name for the content AI service account (will be suffixed with random string)"
  type        = string
  default     = "content-ai-sa"
  validation {
    condition     = length(var.service_account_name) >= 6 && length(var.service_account_name) <= 30
    error_message = "Service account name must be between 6 and 30 characters."
  }
}

variable "cloud_function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "1Gi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.cloud_function_memory)
    error_message = "Memory must be one of the supported Cloud Functions memory allocations."
  }
}

variable "cloud_function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.cloud_function_timeout >= 1 && var.cloud_function_timeout <= 540
    error_message = "Cloud Function timeout must be between 1 and 540 seconds."
  }
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run services"
  type        = string
  default     = "2Gi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi", "16Gi", "32Gi"
    ], var.cloud_run_memory)
    error_message = "Memory must be one of the supported Cloud Run memory allocations."
  }
}

variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run services"
  type        = string
  default     = "2"
  validation {
    condition = contains([
      "0.25", "0.5", "1", "2", "4", "6", "8"
    ], var.cloud_run_cpu)
    error_message = "CPU must be one of the supported Cloud Run CPU allocations."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of instances for Cloud Run services"
  type        = number
  default     = 10
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "cloud_run_min_instances" {
  description = "Minimum number of instances for Cloud Run services"
  type        = number
  default     = 0
  validation {
    condition     = var.cloud_run_min_instances >= 0 && var.cloud_run_min_instances <= 100
    error_message = "Min instances must be between 0 and 100."
  }
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and Logging features"
  type        = bool
  default     = true
}

variable "enable_apis" {
  description = "Enable required Google Cloud APIs automatically"
  type        = bool
  default     = true
}

variable "apis_to_enable" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "aiplatform.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "speech.googleapis.com",
    "texttospeech.googleapis.com"
  ]
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment   = "dev"
    project      = "content-generation"
    managed-by   = "terraform"
    purpose      = "multi-modal-ai"
  }
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

variable "notification_channels" {
  description = "List of notification channels for monitoring alerts"
  type        = list(string)
  default     = []
}