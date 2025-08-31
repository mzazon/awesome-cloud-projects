# Input variables for the Email Signature Generator solution
# These variables allow customization of the deployment while maintaining security and flexibility

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters long, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"

  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "function_name" {
  description = "Name of the Cloud Function for signature generation"
  type        = string
  default     = "generate-signature"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.function_name))
    error_message = "Function name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be 63 characters or less."
  }
}

variable "bucket_name_suffix" {
  description = "Optional suffix for the storage bucket name (will be combined with random string)"
  type        = string
  default     = "email-signatures"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_suffix))
    error_message = "Bucket name suffix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function (e.g., 256M, 512M, 1Gi)"
  type        = string
  default     = "256M"

  validation {
    condition = contains([
      "128M", "256M", "512M", "1Gi", "2Gi", "4Gi", "8Gi", "16Gi", "32Gi"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128M, 256M, 512M, 1Gi, 2Gi, 4Gi, 8Gi, 16Gi, 32Gi."
  }
}

variable "function_timeout" {
  description = "Function execution timeout in seconds (1-540)"
  type        = number
  default     = 60

  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "max_instance_count" {
  description = "Maximum number of Cloud Function instances (1-3000)"
  type        = number
  default     = 10

  validation {
    condition     = var.max_instance_count >= 1 && var.max_instance_count <= 3000
    error_message = "Maximum instance count must be between 1 and 3000."
  }
}

variable "min_instance_count" {
  description = "Minimum number of Cloud Function instances (0-1000)"
  type        = number
  default     = 0

  validation {
    condition     = var.min_instance_count >= 0 && var.min_instance_count <= 1000
    error_message = "Minimum instance count must be between 0 and 1000."
  }
}

variable "bucket_location" {
  description = "Location for the Cloud Storage bucket (region, dual-region, or multi-region)"
  type        = string
  default     = "US"

  validation {
    condition = contains([
      "US", "EU", "ASIA",  # Multi-regional
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.bucket_location)
    error_message = "Bucket location must be a valid Google Cloud Storage location."
  }
}

variable "storage_class" {
  description = "Default storage class for the bucket objects"
  type        = string
  default     = "STANDARD"

  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable object versioning on the storage bucket"
  type        = bool
  default     = false
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the Cloud Function"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    project     = "email-signature-generator"
    managed-by  = "terraform"
  }

  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens (max 63 chars)."
  }

  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label values must contain only lowercase letters, numbers, underscores, and hyphens (max 63 chars)."
  }
}

variable "lifecycle_delete_age_days" {
  description = "Age in days after which signature files will be automatically deleted (0 to disable)"
  type        = number
  default     = 90

  validation {
    condition     = var.lifecycle_delete_age_days >= 0 && var.lifecycle_delete_age_days <= 3650
    error_message = "Lifecycle delete age must be between 0 and 3650 days."
  }
}