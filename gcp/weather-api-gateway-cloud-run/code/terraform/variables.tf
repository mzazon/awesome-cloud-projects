# Variable definitions for Weather API Gateway infrastructure
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region where resources will be deployed"
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

variable "zone" {
  description = "The GCP zone for zonal resources (derived from region)"
  type        = string
  default     = "us-central1-a"
}

variable "service_name" {
  description = "Name of the Cloud Run service"
  type        = string
  default     = "weather-api-gateway"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.service_name))
    error_message = "Service name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (will be made unique)"
  type        = string
  default     = "weather-cache"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "container_image" {
  description = "Container image for the Cloud Run service (will be built from source if not provided)"
  type        = string
  default     = ""
}

variable "service_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "512Mi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.service_memory)
    error_message = "Memory must be one of: 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
  }
}

variable "service_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "1"
  validation {
    condition = contains([
      "0.08", "0.17", "0.25", "0.33", "0.5", "0.58", "0.83", "1", "2", "4", "6", "8"
    ], var.service_cpu)
    error_message = "CPU must be one of the supported Cloud Run CPU values."
  }
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 0
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "timeout_seconds" {
  description = "Request timeout for Cloud Run service in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

variable "cache_lifecycle_days" {
  description = "Number of days to keep cached weather data in Cloud Storage"
  type        = number
  default     = 1
  validation {
    condition     = var.cache_lifecycle_days >= 1 && var.cache_lifecycle_days <= 365
    error_message = "Cache lifecycle must be between 1 and 365 days."
  }
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the Cloud Run service"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "weather-api-gateway"
    environment = "development"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k))
    ])
    error_message = "Label keys must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}