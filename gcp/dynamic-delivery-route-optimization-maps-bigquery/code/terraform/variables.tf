# variables.tf
# Input variables for GCP Dynamic Delivery Route Optimization infrastructure

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "resource_name_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "route-opt"
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.resource_name_prefix))
    error_message = "Resource name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bigquery_dataset_location" {
  description = "Location for BigQuery dataset (should match region for optimal performance)"
  type        = string
  default     = "US"
}

variable "bigquery_deletion_protection" {
  description = "Whether to enable deletion protection for BigQuery dataset"
  type        = bool
  default     = true
}

variable "storage_bucket_force_destroy" {
  description = "Whether to allow Terraform to destroy the storage bucket with objects"
  type        = bool
  default     = false
}

variable "cloud_function_timeout" {
  description = "Timeout for Cloud Function execution in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.cloud_function_timeout >= 60 && var.cloud_function_timeout <= 540
    error_message = "Cloud Function timeout must be between 60 and 540 seconds."
  }
}

variable "cloud_function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 1024
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.cloud_function_memory)
    error_message = "Cloud Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "scheduler_frequency" {
  description = "Cron expression for Cloud Scheduler frequency"
  type        = string
  default     = "0 */2 * * *"
  validation {
    condition     = can(regex("^[0-9/*,-]+ [0-9/*,-]+ [0-9/*,-]+ [0-9/*,-]+ [0-9/*,-]+$", var.scheduler_frequency))
    error_message = "Scheduler frequency must be a valid cron expression."
  }
}

variable "storage_lifecycle_nearline_age" {
  description = "Age in days to transition objects to Nearline storage"
  type        = number
  default     = 30
  validation {
    condition     = var.storage_lifecycle_nearline_age > 0
    error_message = "Nearline age must be greater than 0."
  }
}

variable "storage_lifecycle_coldline_age" {
  description = "Age in days to transition objects to Coldline storage"
  type        = number
  default     = 90
  validation {
    condition     = var.storage_lifecycle_coldline_age > var.storage_lifecycle_nearline_age
    error_message = "Coldline age must be greater than Nearline age."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring for functions"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "route-optimization"
    managed_by  = "terraform"
    component   = "logistics"
  }
}

variable "sample_data_load" {
  description = "Whether to load sample delivery data into BigQuery"
  type        = bool
  default     = true
}

variable "function_source_bucket" {
  description = "Bucket to store Cloud Function source code (will be created if not provided)"
  type        = string
  default     = ""
}

variable "depot_latitude" {
  description = "Default depot latitude for route optimization"
  type        = number
  default     = 37.7749
}

variable "depot_longitude" {
  description = "Default depot longitude for route optimization"
  type        = number
  default     = -122.4194
}

variable "max_optimization_requests_per_day" {
  description = "Maximum number of route optimization requests per day"
  type        = number
  default     = 1000
  validation {
    condition     = var.max_optimization_requests_per_day > 0
    error_message = "Max optimization requests must be greater than 0."
  }
}