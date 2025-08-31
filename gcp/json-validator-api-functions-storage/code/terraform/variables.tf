# Input variables for GCP JSON Validator API infrastructure
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must be a valid GCP project identifier (lowercase letters, numbers, and hyphens only)."
  }
}

variable "region" {
  description = "The GCP region for deploying resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region where Cloud Functions are supported."
  }
}

variable "function_name" {
  description = "Name of the Cloud Function for JSON validation"
  type        = string
  default     = "json-validator"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name)) && length(var.function_name) <= 63
    error_message = "Function name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be 63 characters or less."
  }
}

variable "bucket_name" {
  description = "Name of the Cloud Storage bucket for JSON files (will be suffixed with random string)"
  type        = string
  default     = "json-files"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-._]*[a-z0-9]$", var.bucket_name)) && length(var.bucket_name) <= 50
    error_message = "Bucket name must contain only lowercase letters, numbers, hyphens, dots, and underscores, and be 50 characters or less (will be suffixed)."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function (in MB)"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, or 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function (in seconds)"
  type        = number
  default     = 60
  
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

variable "min_instances" {
  description = "Minimum number of function instances (0 for scaling to zero)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= var.max_instances
    error_message = "Min instances must be 0 or greater and not exceed max instances."
  }
}

variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE", "REGIONAL", "MULTI_REGIONAL"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE, REGIONAL, or MULTI_REGIONAL."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "enable_public_access" {
  description = "Enable public read access to the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    application = "json-validator"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "enable_apis" {
  description = "Enable required Google Cloud APIs automatically"
  type        = bool
  default     = true
}

variable "source_code_path" {
  description = "Path to the Cloud Function source code directory"
  type        = string
  default     = "../function-source"
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