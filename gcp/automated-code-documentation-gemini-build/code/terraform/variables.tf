# Input variables for the automated code documentation infrastructure
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 6 && can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters long, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
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
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "name_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "doc-automation"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name_prefix))
    error_message = "Name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bucket_location" {
  description = "Location for the Cloud Storage bucket (can be different from compute region)"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.bucket_location)
    error_message = "Bucket location must be a valid Google Cloud Storage location."
  }
}

variable "storage_class" {
  description = "Storage class for the documentation bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for the documentation storage bucket"
  type        = bool
  default     = true
}

variable "gemini_model" {
  description = "Vertex AI Gemini model to use for documentation generation"
  type        = string
  default     = "gemini-1.5-flash"
  
  validation {
    condition = contains([
      "gemini-1.5-flash", "gemini-1.5-pro", "gemini-1.0-pro"
    ], var.gemini_model)
    error_message = "Gemini model must be one of the supported models: gemini-1.5-flash, gemini-1.5-pro, or gemini-1.0-pro."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = number
  default     = 512
  
  validation {
    condition     = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 MB and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (in seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "notification_function_memory" {
  description = "Memory allocation for notification Cloud Function (in MB)"
  type        = number
  default     = 256
  
  validation {
    condition     = var.notification_function_memory >= 128 && var.notification_function_memory <= 8192
    error_message = "Notification function memory must be between 128 MB and 8192 MB."
  }
}

variable "enable_public_access" {
  description = "Enable public access for Cloud Functions (disable for production)"
  type        = bool
  default     = false
}

variable "create_build_trigger" {
  description = "Create manual Cloud Build trigger for documentation generation"
  type        = bool
  default     = true
}

variable "enable_notifications" {
  description = "Enable notification system with Eventarc triggers"
  type        = bool
  default     = true
}

variable "enable_website" {
  description = "Enable static documentation website hosted on Cloud Storage"
  type        = bool
  default     = true
}

variable "lifecycle_rules" {
  description = "Lifecycle rules for the documentation storage bucket"
  type = list(object({
    action = object({
      type          = string
      storage_class = optional(string)
    })
    condition = object({
      age                   = optional(number)
      created_before        = optional(string)
      with_state           = optional(string)
      matches_storage_class = optional(list(string))
      num_newer_versions   = optional(number)
    })
  }))
  default = [
    {
      action = {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
      condition = {
        age = 30
      }
    },
    {
      action = {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
      condition = {
        age = 365
      }
    }
  ]
}

variable "service_account_roles" {
  description = "Additional IAM roles to assign to the service account"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    purpose     = "documentation-automation"
    managed-by  = "terraform"
  }
}

variable "apis_to_enable" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "aiplatform.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com",
    "pubsub.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

variable "build_trigger_description" {
  description = "Description for the Cloud Build trigger"
  type        = string
  default     = "Manual trigger for automated documentation generation"
}

variable "build_config_filename" {
  description = "Filename for the Cloud Build configuration"
  type        = string
  default     = "cloudbuild.yaml"
}