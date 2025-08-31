# Terraform Variables Configuration
# This file defines all input variables for the Recipe Generation and Meal Planning infrastructure

# Project Configuration Variables
variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The default Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The default Google Cloud zone for resources"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming Variables
variable "project_name" {
  description = "A human-readable name for the project, used in resource naming"
  type        = string
  default     = "recipe-ai-platform"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "The deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Storage Configuration Variables
variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_versioning_enabled" {
  description = "Enable versioning for the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age" {
  description = "Number of days after which to delete old versions of objects"
  type        = number
  default     = 30
  validation {
    condition     = var.bucket_lifecycle_age > 0
    error_message = "Bucket lifecycle age must be greater than 0."
  }
}

# Cloud Functions Configuration Variables
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "generator_function_memory" {
  description = "Memory allocation for the recipe generator function in MB"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.generator_function_memory)
    error_message = "Generator function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "generator_function_timeout" {
  description = "Timeout for the recipe generator function in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.generator_function_timeout >= 1 && var.generator_function_timeout <= 540
    error_message = "Generator function timeout must be between 1 and 540 seconds."
  }
}

variable "retriever_function_memory" {
  description = "Memory allocation for the recipe retriever function in MB"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.retriever_function_memory)
    error_message = "Retriever function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "retriever_function_timeout" {
  description = "Timeout for the recipe retriever function in seconds"
  type        = number
  default     = 30
  validation {
    condition     = var.retriever_function_timeout >= 1 && var.retriever_function_timeout <= 540
    error_message = "Retriever function timeout must be between 1 and 540 seconds."
  }
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to Cloud Functions"
  type        = bool
  default     = true
}

# Vertex AI Configuration Variables
variable "vertex_ai_location" {
  description = "Location for Vertex AI resources (may differ from general region)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west4",
      "europe-west1", "europe-west4", "asia-east1", "asia-northeast1"
    ], var.vertex_ai_location)
    error_message = "Vertex AI location must be a supported region."
  }
}

variable "gemini_model_name" {
  description = "The Gemini model to use for recipe generation"
  type        = string
  default     = "gemini-1.5-flash"
  validation {
    condition = contains([
      "gemini-1.5-flash", "gemini-1.5-pro", "gemini-1.0-pro"
    ], var.gemini_model_name)
    error_message = "Gemini model must be one of the supported models."
  }
}

# Security and Access Control Variables
variable "enable_api_services" {
  description = "Enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "additional_iam_members" {
  description = "Additional IAM members to grant access to the storage bucket"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for member in var.additional_iam_members : can(regex("^(user:|serviceAccount:|group:|domain:)", member))
    ])
    error_message = "IAM members must be in the format: user:email, serviceAccount:email, group:email, or domain:domain.com"
  }
}

# Monitoring and Logging Variables
variable "enable_function_logging" {
  description = "Enable detailed logging for Cloud Functions"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain Cloud Function logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653 (10 years)."
  }
}

# Cost Management Variables
variable "enable_cost_labels" {
  description = "Enable cost tracking labels on all resources"
  type        = bool
  default     = true
}

variable "cost_center" {
  description = "Cost center identifier for billing allocation"
  type        = string
  default     = "ai-platform"
}

variable "owner" {
  description = "Owner or team responsible for the resources"
  type        = string
  default     = "platform-team"
}