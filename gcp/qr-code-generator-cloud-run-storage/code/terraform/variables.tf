# Input variables for the QR Code Generator infrastructure
# These variables allow customization of the deployment

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "service_name" {
  description = "Name of the Cloud Run service"
  type        = string
  default     = "qr-code-api"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.service_name))
    error_message = "Service name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (random suffix will be added)"
  type        = string
  default     = "qr-codes"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must be lowercase, start and end with alphanumeric characters, and contain only letters, numbers, and hyphens."
  }
}

variable "container_image" {
  description = "Container image for the QR Code API (if deploying pre-built image)"
  type        = string
  default     = ""
}

variable "service_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "512Mi"
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.service_memory))
    error_message = "Memory must be specified in Mi or Gi format (e.g., 512Mi, 1Gi)."
  }
}

variable "service_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "1"
  validation {
    condition     = contains(["1", "2", "4", "8"], var.service_cpu)
    error_message = "CPU must be one of: 1, 2, 4, 8."
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

variable "concurrency" {
  description = "Maximum number of concurrent requests per Cloud Run instance"
  type        = number
  default     = 100
  validation {
    condition     = var.concurrency >= 1 && var.concurrency <= 1000
    error_message = "Concurrency must be between 1 and 1000."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "allow_public_access" {
  description = "Whether to allow public access to the Cloud Run service"
  type        = bool
  default     = true
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

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "qr-code-generator"
    environment = "development"
    managed-by  = "terraform"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}