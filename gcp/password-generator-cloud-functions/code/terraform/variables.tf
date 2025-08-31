# Variables for password generator Cloud Function deployment
# This file defines all configurable parameters for the infrastructure

# Required Variables
variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string

  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

# Regional Configuration
variable "region" {
  description = "The Google Cloud region for deploying resources"
  type        = string
  default     = "us-central1"

  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone within the region"
  type        = string
  default     = null # Will be set automatically based on region if not specified
}

# Function Configuration
variable "function_name" {
  description = "Name of the Cloud Function"
  type        = string
  default     = "password-generator"

  validation {
    condition     = can(regex("^[a-z][-a-z0-9]*[a-z0-9]$", var.function_name)) && length(var.function_name) <= 63
    error_message = "Function name must be 1-63 characters, start with a letter, end with letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_description" {
  description = "Description of the Cloud Function"
  type        = string
  default     = "Serverless password generator API with customizable security options"
}

variable "function_runtime" {
  description = "Runtime environment for the Cloud Function"
  type        = string
  default     = "python311"

  validation {
    condition = contains([
      "python37", "python38", "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Runtime must be a supported Python version."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = string
  default     = "256Mi"

  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi", "16Gi", "32Gi"
    ], var.function_memory)
    error_message = "Memory must be a valid Cloud Functions memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function execution in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
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

# Security and Access Configuration
variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the Cloud Function"
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
    error_message = "Ingress settings must be ALLOW_ALL, ALLOW_INTERNAL_ONLY, or ALLOW_INTERNAL_AND_GCLB."
  }
}

# Storage Configuration
variable "bucket_name" {
  description = "Name of the Google Cloud Storage bucket for function source code (auto-generated if not specified)"
  type        = string
  default     = null
}

variable "bucket_location" {
  description = "Location for the Google Cloud Storage bucket"
  type        = string
  default     = "US"

  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "asia-east1", "asia-southeast1"
    ], var.bucket_location)
    error_message = "Bucket location must be a valid Google Cloud Storage location."
  }
}

variable "bucket_storage_class" {
  description = "Storage class for the Google Cloud Storage bucket"
  type        = string
  default     = "STANDARD"

  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

# Environment and Tagging
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][-_a-z0-9]*$", k)) && can(regex("^[-_a-z0-9]*$", v))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, hyphens, and underscores. Values can contain lowercase letters, numbers, hyphens, and underscores."
  }
}

# Source Code Configuration
variable "source_code_path" {
  description = "Path to the directory containing the Cloud Function source code"
  type        = string
  default     = "../function-source"
}

variable "source_archive_bucket_prefix" {
  description = "Prefix for the source code archive in the bucket"
  type        = string
  default     = "functions/password-generator"
}

# API Services Configuration
variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "apis_to_enable" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

# Monitoring and Logging Configuration
variable "enable_logging" {
  description = "Enable Cloud Logging for the function"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Logging level for the function"
  type        = string
  default     = "INFO"

  validation {
    condition = contains([
      "DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"
    ], var.log_level)
    error_message = "Log level must be DEBUG, INFO, WARNING, ERROR, or CRITICAL."
  }
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix to add to all resource names for uniqueness"
  type        = string
  default     = ""

  validation {
    condition     = var.resource_prefix == "" || can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_suffix" {
  description = "Suffix to add to all resource names for uniqueness"
  type        = string
  default     = ""

  validation {
    condition     = var.resource_suffix == "" || can(regex("^[a-z0-9-]+$", var.resource_suffix))
    error_message = "Resource suffix must contain only lowercase letters, numbers, and hyphens."
  }
}