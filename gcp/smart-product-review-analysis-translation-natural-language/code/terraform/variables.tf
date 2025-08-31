# Variables for smart product review analysis infrastructure
# This file defines all configurable parameters for the Terraform deployment

# Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

# Regional Configuration
variable "region" {
  description = "The GCP region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone within the region"
  type        = string
  default     = "us-central1-a"
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

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "review-analysis"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

# BigQuery Configuration
variable "dataset_location" {
  description = "Location for BigQuery dataset (should match region for optimal performance)"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "asia-east1", "asia-northeast1", "asia-southeast1",
      "australia-southeast1", "europe-north1", "europe-west1", "europe-west2",
      "europe-west3", "europe-west4", "europe-west6", "us-central1", "us-east1",
      "us-east4", "us-west1", "us-west2", "us-west3", "us-west4"
    ], var.dataset_location)
    error_message = "Dataset location must be a valid BigQuery location."
  }
}

variable "table_expiration_days" {
  description = "Number of days after which BigQuery tables will be automatically deleted (0 = never expire)"
  type        = number
  default     = 90
  validation {
    condition     = var.table_expiration_days >= 0 && var.table_expiration_days <= 365
    error_message = "Table expiration must be between 0 and 365 days."
  }
}

# Cloud Function Configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 512
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768 MB."
  }
}

variable "function_timeout" {
  description = "Maximum execution time for Cloud Function in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime for Cloud Function"
  type        = string
  default     = "python312"
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "max_function_instances" {
  description = "Maximum number of function instances that can run simultaneously"
  type        = number
  default     = 100
  validation {
    condition     = var.max_function_instances >= 1 && var.max_function_instances <= 3000
    error_message = "Max function instances must be between 1 and 3000."
  }
}

# API Configuration
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
    "translate.googleapis.com",
    "language.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com"
  ]
}

# Security Configuration
variable "function_ingress_settings" {
  description = "Ingress settings for Cloud Function"
  type        = string
  default     = "ALLOW_ALL"
  validation {
    condition = contains([
      "ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"
    ], var.function_ingress_settings)
    error_message = "Ingress settings must be one of: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  }
}

variable "require_authentication" {
  description = "Whether to require authentication for Cloud Function invocation"
  type        = bool
  default     = false
}

# Storage Configuration
variable "bucket_location" {
  description = "Location for Cloud Storage bucket (should match region)"
  type        = string
  default     = "US"
}

variable "bucket_storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# Monitoring and Logging
variable "enable_monitoring" {
  description = "Whether to enable enhanced monitoring and alerting"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Resource Tags
variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : can(regex("^[a-z][a-z0-9_-]*$", k))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Cost Management
variable "budget_amount" {
  description = "Monthly budget amount in USD for cost monitoring (0 to disable)"
  type        = number
  default     = 50
  validation {
    condition     = var.budget_amount >= 0
    error_message = "Budget amount must be non-negative."
  }
}

variable "budget_alert_thresholds" {
  description = "Budget alert thresholds as percentages (0.5 = 50%)"
  type        = list(number)
  default     = [0.5, 0.8, 0.9, 1.0]
  validation {
    condition = alltrue([
      for threshold in var.budget_alert_thresholds : threshold > 0 && threshold <= 2.0
    ])
    error_message = "Budget thresholds must be between 0 and 2.0 (200%)."
  }
}