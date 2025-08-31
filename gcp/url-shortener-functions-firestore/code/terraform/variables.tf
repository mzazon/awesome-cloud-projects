# Variables for GCP URL Shortener Infrastructure
# Defines input variables for the URL Shortener using Cloud Functions and Firestore

# Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region where resources will be deployed"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

# Cloud Function Configuration
variable "function_name" {
  description = "Name of the Cloud Function for URL shortening"
  type        = string
  default     = "url-shortener"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.function_name))
    error_message = "Function name must start with a lowercase letter, followed by lowercase letters, numbers, or hyphens, and cannot end with a hyphen."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function"
  type        = string
  default     = "256M"
  
  validation {
    condition = contains([
      "128M", "256M", "512M", "1024M", "2048M", "4096M", "8192M"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128M, 256M, 512M, 1024M, 2048M, 4096M, 8192M."
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
  description = "Minimum number of function instances (set to 0 for serverless)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

# Firestore Configuration
variable "firestore_database_id" {
  description = "Firestore database ID"
  type        = string
  default     = "(default)"
  
  validation {
    condition = var.firestore_database_id == "(default)" || can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.firestore_database_id))
    error_message = "Database ID must be '(default)' or start with a lowercase letter, followed by lowercase letters, numbers, or hyphens."
  }
}

variable "firestore_location" {
  description = "Firestore database location (multi-region or region)"
  type        = string
  default     = "nam5"
  
  validation {
    condition = contains([
      "nam5", "eur3", "us-central1", "us-east1", "us-west1", "europe-west1", 
      "asia-northeast1", "asia-south1", "australia-southeast1"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid location ID."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable Point-in-Time Recovery for Firestore"
  type        = bool
  default     = false
}

variable "enable_delete_protection" {
  description = "Enable delete protection for Firestore database"
  type        = bool
  default     = false
}

# Storage Configuration
variable "source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code (will be prefixed with project ID)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.source_bucket_name == "" || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.source_bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "source_bucket_location" {
  description = "Location for the source code storage bucket"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", 
      "europe-west1", "asia-northeast1"
    ], var.source_bucket_location)
    error_message = "Storage location must be a valid Cloud Storage location."
  }
}

# Security and Access Configuration
variable "allow_unauthenticated_access" {
  description = "Allow unauthenticated access to the Cloud Function"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS (empty means allow all)"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allowed_methods" {
  description = "List of allowed HTTP methods for CORS"
  type        = list(string)
  default     = ["GET", "POST", "OPTIONS"]
}

# Resource Labeling
variable "resource_labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "url-shortener"
    environment = "production"
    managed-by  = "terraform"
  }
  
  validation {
    condition     = alltrue([for k, v in var.resource_labels : can(regex("^[a-z]([a-z0-9_-]*[a-z0-9])?$", k))])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Deployment Configuration
variable "source_archive_name" {
  description = "Name of the source code archive file"
  type        = string
  default     = "function-source.zip"
}

variable "function_entry_point" {
  description = "Entry point for the Cloud Function"
  type        = string
  default     = "urlShortener"
}

variable "runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "nodejs20"
  
  validation {
    condition = contains([
      "nodejs18", "nodejs20", "python39", "python310", "python311", "python312",
      "go119", "go120", "go121", "java11", "java17", "java21",
      "dotnet3", "dotnet6", "ruby30", "ruby32"
    ], var.runtime)
    error_message = "Runtime must be a supported Cloud Functions runtime."
  }
}