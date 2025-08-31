# Core project configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 6 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6+ characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., us-central1-a)."
  }
}

# Application configuration
variable "app_name" {
  description = "Base name for the application resources"
  type        = string
  default     = "product-catalog"
  validation {
    condition     = length(var.app_name) >= 3 && length(var.app_name) <= 30 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.app_name))
    error_message = "App name must be 3-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
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

# Firestore configuration
variable "firestore_location_id" {
  description = "Location for Firestore database"
  type        = string
  default     = "us-central"
  validation {
    condition = contains([
      "us-central", "us-east1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "asia-northeast1",
      "asia-south1", "australia-southeast1"
    ], var.firestore_location_id)
    error_message = "Firestore location must be a valid multi-region or region location."
  }
}

variable "firestore_type" {
  description = "Type of Firestore database (FIRESTORE_NATIVE or DATASTORE_MODE)"
  type        = string
  default     = "FIRESTORE_NATIVE"
  validation {
    condition     = contains(["FIRESTORE_NATIVE", "DATASTORE_MODE"], var.firestore_type)
    error_message = "Firestore type must be either FIRESTORE_NATIVE or DATASTORE_MODE."
  }
}

# Cloud Storage configuration
variable "storage_class" {
  description = "Storage class for the product data bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "lifecycle_age_days" {
  description = "Number of days after which to delete old versions"
  type        = number
  default     = 30
  validation {
    condition     = var.lifecycle_age_days > 0 && var.lifecycle_age_days <= 365
    error_message = "Lifecycle age must be between 1 and 365 days."
  }
}

# Vertex AI Search configuration
variable "search_industry_vertical" {
  description = "Industry vertical for Vertex AI Search"
  type        = string
  default     = "GENERIC"
  validation {
    condition = contains([
      "GENERIC", "MEDIA", "HEALTHCARE_FHIR"
    ], var.search_industry_vertical)
    error_message = "Industry vertical must be one of: GENERIC, MEDIA, HEALTHCARE_FHIR."
  }
}

variable "search_content_config" {
  description = "Content configuration for the search data store"
  type        = string
  default     = "CONTENT_REQUIRED"
  validation {
    condition = contains([
      "CONTENT_REQUIRED", "CONTENT_NOT_REQUIRED"
    ], var.search_content_config)
    error_message = "Content config must be CONTENT_REQUIRED or CONTENT_NOT_REQUIRED."
  }
}

# Cloud Run configuration
variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "1"
  validation {
    condition     = contains(["0.08", "0.17", "0.25", "0.5", "1", "2", "4", "6", "8"], var.cloud_run_cpu)
    error_message = "CPU must be one of the supported Cloud Run CPU values."
  }
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "1Gi"
  validation {
    condition     = can(regex("^[0-9]+[GM]i$", var.cloud_run_memory))
    error_message = "Memory must be in format like '1Gi' or '512Mi'."
  }
}

variable "cloud_run_timeout" {
  description = "Request timeout for Cloud Run service in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.cloud_run_timeout >= 1 && var.cloud_run_timeout <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of instances for Cloud Run service"
  type        = number
  default     = 100
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to Cloud Run service"
  type        = bool
  default     = true
}

# Container image configuration
variable "container_image" {
  description = "Container image for the Cloud Run service (if not building from source)"
  type        = string
  default     = ""
}

variable "source_archive_bucket" {
  description = "Cloud Storage bucket for source code archive (leave empty to create new bucket)"
  type        = string
  default     = ""
}

# Sample data configuration
variable "create_sample_data" {
  description = "Whether to create and upload sample product data"
  type        = bool
  default     = true
}

variable "sample_data_file" {
  description = "Local path to sample data file (JSONL format)"
  type        = string
  default     = ""
}

# Monitoring and logging
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for the application"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Log level for the application"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

# Network configuration
variable "vpc_connector_name" {
  description = "Name of VPC connector for Cloud Run (optional)"
  type        = string
  default     = ""
}

# Labels and tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    component = "product-catalog"
    managed-by = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain the same characters."
  }
}

# API services to enable
variable "enable_apis" {
  description = "List of APIs to enable"
  type        = list(string)
  default = [
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "firestore.googleapis.com",
    "discoveryengine.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com"
  ]
}