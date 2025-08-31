# Variables for the smart resume screening infrastructure
# These variables allow customization of the deployment

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
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
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "resume-screening"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "bucket_location" {
  description = "Location for the Cloud Storage bucket (region or multi-region)"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA",
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.bucket_location)
    error_message = "Bucket location must be a valid GCP region or multi-region."
  }
}

variable "bucket_storage_class" {
  description = "Storage class for the resume upload bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function (in MB)"
  type        = number
  default     = 512
  validation {
    condition     = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 MB and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function (in seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "firestore_location" {
  description = "Location for the Firestore database"
  type        = string
  default     = "us-central"
  validation {
    condition = contains([
      "us-central", "us-east1", "us-west2", "us-west3", "us-west4",
      "southamerica-east1", "europe-west2", "europe-west3", "europe-west6",
      "asia-south1", "asia-southeast2", "asia-northeast1", "asia-northeast2"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or regional location."
  }
}

variable "enable_audit_logs" {
  description = "Enable audit logs for Cloud Storage and Firestore"
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Enable versioning for the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "lifecycle_rules" {
  description = "Enable lifecycle rules for the Cloud Storage bucket to manage costs"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    application = "resume-screening"
    managed-by  = "terraform"
  }
}

variable "allowed_file_types" {
  description = "List of allowed file extensions for resume uploads"
  type        = list(string)
  default     = ["txt", "pdf", "doc", "docx"]
}

variable "enable_monitoring" {
  description = "Enable monitoring and alerting for the solution"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring notifications (optional)"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}