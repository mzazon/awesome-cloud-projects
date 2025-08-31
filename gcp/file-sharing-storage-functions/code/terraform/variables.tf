# Input variables for GCP file sharing infrastructure
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition = can(regex("^[a-z][a-z0-9-]{5,29}$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
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

variable "zone" {
  description = "The GCP zone for resource deployment"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "file_storage_class" {
  description = "Storage class for the file sharing bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.file_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (e.g., 256M, 512M, 1Gi)"
  type        = string
  default     = "256M"
  validation {
    condition = can(regex("^(256M|512M|1Gi|2Gi|4Gi|8Gi|16Gi|32Gi)$", var.function_memory))
    error_message = "Function memory must be one of: 256M, 512M, 1Gi, 2Gi, 4Gi, 8Gi, 16Gi, 32Gi."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 60
  validation {
    condition = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "max_instance_count" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition = var.max_instance_count >= 1 && var.max_instance_count <= 1000
    error_message = "Max instance count must be between 1 and 1000."
  }
}

variable "signed_url_expiration_hours" {
  description = "Expiration time for signed URLs in hours"
  type        = number
  default     = 1
  validation {
    condition = var.signed_url_expiration_hours >= 1 && var.signed_url_expiration_hours <= 168
    error_message = "Signed URL expiration must be between 1 and 168 hours (7 days)."
  }
}

variable "allowed_file_extensions" {
  description = "List of allowed file extensions for uploads"
  type        = list(string)
  default     = ["jpg", "jpeg", "png", "gif", "pdf", "doc", "docx", "txt", "zip"]
}

variable "max_file_size_mb" {
  description = "Maximum file size in MB for uploads"
  type        = number
  default     = 10
  validation {
    condition = var.max_file_size_mb >= 1 && var.max_file_size_mb <= 5120
    error_message = "Max file size must be between 1 and 5120 MB (5 GB)."
  }
}

variable "cors_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "cors_methods" {
  description = "List of allowed methods for CORS"
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS"]
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the file storage bucket"
  type        = bool
  default     = false
}

variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access control"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    terraform   = "true"
    application = "file-sharing"
  }
}