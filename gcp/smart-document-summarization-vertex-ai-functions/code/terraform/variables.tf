# Variables for GCP smart document summarization infrastructure
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "bucket_name" {
  description = "Name for the Cloud Storage bucket (will be suffixed with random value for uniqueness)"
  type        = string
  default     = "doc-summarizer"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must be 3-63 characters, start and end with alphanumeric, and contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

variable "function_name" {
  description = "Name for the Cloud Function"
  type        = string
  default     = "summarize-document"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.function_name))
    error_message = "Function name must start with letter, be 1-63 characters, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 1024
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

variable "max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

variable "enable_vertex_ai_api" {
  description = "Whether to enable the Vertex AI API"
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

variable "enable_versioning" {
  description = "Enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "smart-document-summarization"
    environment = "demo"
    created-by  = "terraform"
  }
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Cannot have more than 64 labels."
  }
}

variable "python_runtime" {
  description = "Python runtime version for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition     = contains(["python39", "python310", "python311", "python312"], var.python_runtime)
    error_message = "Python runtime must be one of: python39, python310, python311, python312."
  }
}

variable "vertex_ai_location" {
  description = "Location for Vertex AI services (usually same as region or global)"
  type        = string
  default     = "us-central1"
}