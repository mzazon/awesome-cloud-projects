# Variables for Age Calculator API with Cloud Run and Storage
# This file defines all configurable variables for the infrastructure

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for deploying resources"
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

variable "service_name" {
  description = "Name for the Cloud Run service"
  type        = string
  default     = "age-calculator-api"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service_name))
    error_message = "Service name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (random suffix will be added)"
  type        = string
  default     = "age-calc-logs"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "container_image" {
  description = "Container image URL for the Cloud Run service. If not provided, will be built from source"
  type        = string
  default     = ""
}

variable "service_account_name" {
  description = "Name for the service account used by Cloud Run"
  type        = string
  default     = "age-calculator-sa"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service_account_name))
    error_message = "Service account name must contain only lowercase letters, numbers, and hyphens."
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

variable "memory" {
  description = "Memory allocation for each Cloud Run instance"
  type        = string
  default     = "512Mi"
  
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.memory)
    error_message = "Memory must be one of: 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
  }
}

variable "cpu" {
  description = "CPU allocation for each Cloud Run instance"
  type        = string
  default     = "1000m"
  
  validation {
    condition = contains([
      "1000m", "2000m", "4000m", "8000m"
    ], var.cpu)
    error_message = "CPU must be one of: 1000m, 2000m, 4000m, 8000m."
  }
}

variable "timeout_seconds" {
  description = "Request timeout in seconds for Cloud Run service"
  type        = number
  default     = 300
  
  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

variable "concurrency" {
  description = "Maximum concurrent requests per Cloud Run instance"
  type        = number
  default     = 80
  
  validation {
    condition     = var.concurrency >= 1 && var.concurrency <= 1000
    error_message = "Concurrency must be between 1 and 1000."
  }
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the Cloud Run service"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "Default storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "lifecycle_rules" {
  description = "Enable lifecycle rules for automatic storage class transitions"
  type        = bool
  default     = true
}

variable "enable_apis" {
  description = "Enable required Google Cloud APIs automatically"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    environment = "development"
    application = "age-calculator"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}