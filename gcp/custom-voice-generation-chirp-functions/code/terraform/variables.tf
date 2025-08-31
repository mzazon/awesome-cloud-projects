# Variables for Custom Voice Generation with Chirp 3 and Functions
# This file contains all configurable variables for the voice synthesis infrastructure

variable "project_id" {
  description = "The GCP project ID for deploying resources"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for deploying regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition     = contains(["us-central1", "us-east1", "us-west1", "europe-west1", "asia-southeast1"], var.region)
    error_message = "Region must be a valid GCP region with Text-to-Speech API support."
  }
}

variable "zone" {
  description = "The GCP zone for deploying zonal resources"
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

variable "bucket_name_suffix" {
  description = "Suffix for the Cloud Storage bucket name to ensure uniqueness"
  type        = string
  default     = ""
}

variable "db_instance_name_suffix" {
  description = "Suffix for the Cloud SQL instance name to ensure uniqueness"
  type        = string
  default     = ""
}

variable "db_tier" {
  description = "The machine type for the Cloud SQL instance"
  type        = string
  default     = "db-f1-micro"
  
  validation {
    condition     = contains(["db-f1-micro", "db-g1-small", "db-n1-standard-1", "db-n1-standard-2"], var.db_tier)
    error_message = "Database tier must be a valid Cloud SQL machine type."
  }
}

variable "db_storage_size" {
  description = "Storage size for the Cloud SQL instance in GB"
  type        = number
  default     = 10
  
  validation {
    condition     = var.db_storage_size >= 10 && var.db_storage_size <= 30720
    error_message = "Database storage size must be between 10 and 30720 GB."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Whether to enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection on the Cloud SQL instance"
  type        = bool
  default     = true
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 120
  
  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "voice-generation"
    technology  = "chirp3"
    managed-by  = "terraform"
  }
  
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Cannot have more than 64 labels."
  }
}

variable "enable_backup" {
  description = "Whether to enable automated backups for Cloud SQL"
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "Start time for automated backups in HH:MM format"
  type        = string
  default     = "03:00"
  
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Backup start time must be in HH:MM format (24-hour)."
  }
}

variable "database_flags" {
  description = "Database flags for Cloud SQL PostgreSQL instance"
  type = list(object({
    name  = string
    value = string
  }))
  default = [
    {
      name  = "log_connections"
      value = "on"
    },
    {
      name  = "log_disconnections"
      value = "on"
    }
  ]
}

variable "authorized_networks" {
  description = "List of authorized networks for Cloud SQL access"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "lifecycle_rules" {
  description = "Lifecycle rules for the Cloud Storage bucket"
  type = list(object({
    action = object({
      type          = string
      storage_class = optional(string)
    })
    condition = object({
      age                        = optional(number)
      created_before             = optional(string)
      with_state                 = optional(string)
      matches_storage_class      = optional(list(string))
      num_newer_versions         = optional(number)
      custom_time_before         = optional(string)
      days_since_custom_time     = optional(number)
      days_since_noncurrent_time = optional(number)
      noncurrent_time_before     = optional(string)
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
        age = 90
      }
    }
  ]
}