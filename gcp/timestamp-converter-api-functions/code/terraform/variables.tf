# Terraform Variables for Timestamp Converter API Infrastructure
# This file defines all configurable parameters for the GCP Cloud Function deployment

# Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region for deploying resources (e.g., us-central1, us-east1)"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

# Cloud Function Configuration
variable "function_name" {
  description = "Name of the Cloud Function for timestamp conversion"
  type        = string
  default     = "timestamp-converter"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "function_description" {
  description = "Description of the Cloud Function"
  type        = string
  default     = "Serverless API for converting Unix timestamps to human-readable dates with timezone support"
}

variable "function_runtime" {
  description = "Runtime environment for the Cloud Function"
  type        = string
  default     = "python312"
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Runtime must be a supported Python version (python39, python310, python311, python312)."
  }
}

variable "function_entry_point" {
  description = "The name of the function to execute (entry point)"
  type        = string
  default     = "timestamp_converter"
}

variable "function_memory" {
  description = "Memory allocated to the Cloud Function in MB"
  type        = number
  default     = 256
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances that can run concurrently"
  type        = number
  default     = 10
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "function_max_instance_request_concurrency" {
  description = "Maximum number of concurrent requests per function instance"
  type        = number
  default     = 1000
  validation {
    condition     = var.function_max_instance_request_concurrency >= 1 && var.function_max_instance_request_concurrency <= 1000
    error_message = "Max instance request concurrency must be between 1 and 1000."
  }
}

# Cloud Storage Configuration
variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (will be suffixed with random string)"
  type        = string
  default     = "timestamp-converter-source"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must start and end with alphanumeric characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bucket_location" {
  description = "Location for the Cloud Storage bucket (should match or be compatible with function region)"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "asia-southeast1", "asia-northeast1"
    ], var.bucket_location)
    error_message = "Bucket location must be a valid GCP location or region."
  }
}

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

variable "enable_bucket_versioning" {
  description = "Enable versioning on the Cloud Storage bucket for source code history"
  type        = bool
  default     = true
}

# Security and Access Configuration
variable "allow_unauthenticated_invocations" {
  description = "Allow unauthenticated invocations of the Cloud Function"
  type        = bool
  default     = true
}

variable "ingress_settings" {
  description = "Ingress settings for the Cloud Function"
  type        = string
  default     = "ALLOW_ALL"
  validation {
    condition = contains([
      "ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"
    ], var.ingress_settings)
    error_message = "Ingress settings must be one of: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  }
}

# API and Service Configuration
variable "enable_required_apis" {
  description = "Enable required GCP APIs automatically"
  type        = bool
  default     = true
}

variable "required_apis" {
  description = "List of required GCP APIs for the timestamp converter function"
  type        = list(string)
  default = [
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com"
  ]
}

# Environment Variables for Function
variable "function_environment_variables" {
  description = "Environment variables to set in the Cloud Function"
  type        = map(string)
  default = {
    LOG_LEVEL = "INFO"
  }
}

# Labels and Tagging
variable "resource_labels" {
  description = "Labels to apply to all resources for organization and billing"
  type        = map(string)
  default = {
    project     = "timestamp-converter"
    environment = "production"
    managed-by  = "terraform"
    recipe      = "timestamp-converter-api-functions"
  }
}

# Source Code Configuration
variable "source_code_path" {
  description = "Local path to the function source code directory"
  type        = string
  default     = "../function-source"
}

variable "source_archive_output_path" {
  description = "Output path for the function source code archive"
  type        = string
  default     = "./function-source.zip"
}