# Variables for Weather API Service with Cloud Functions
# This file defines all input variables used in the Terraform configuration

# Project Configuration Variables
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

# Function Configuration Variables
variable "function_name" {
  description = "Name of the Cloud Function for the weather API"
  type        = string
  default     = "weather-api"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.function_name))
    error_message = "Function name must start with a letter, contain only lowercase letters, numbers, and hyphens, and be up to 63 characters."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime environment for the Cloud Function"
  type        = string
  default     = "python312"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312",
      "nodejs16", "nodejs18", "nodejs20", "go119", "go120", "go121"
    ], var.function_runtime)
    error_message = "Runtime must be a supported Cloud Functions runtime."
  }
}

# Storage Configuration Variables
variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (will be suffixed with random string)"
  type        = string
  default     = "weather-cache"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", "${var.bucket_name_prefix}-suffix"))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
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

variable "cache_lifecycle_days" {
  description = "Number of days after which cached weather data will be automatically deleted"
  type        = number
  default     = 1
  validation {
    condition     = var.cache_lifecycle_days >= 1 && var.cache_lifecycle_days <= 365
    error_message = "Cache lifecycle must be between 1 and 365 days."
  }
}

# API Configuration Variables
variable "openweather_api_key" {
  description = "OpenWeatherMap API key for fetching weather data (leave empty to use demo mode)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_cors" {
  description = "Enable CORS support for the weather API"
  type        = bool
  default     = true
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the Cloud Function"
  type        = bool
  default     = true
}

# Resource Tagging Variables
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    application = "weather-api"
    managed-by  = "terraform"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]{1,63}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens, with keys 1-63 chars and values 0-63 chars."
  }
}

# Monitoring and Logging Variables
variable "enable_function_logs" {
  description = "Enable detailed logging for the Cloud Function"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Log level for the Cloud Function"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR."
  }
}