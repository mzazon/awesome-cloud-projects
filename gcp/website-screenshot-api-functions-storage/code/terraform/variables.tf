# Variables for Website Screenshot API with Cloud Functions and Storage
# These variables allow customization of the infrastructure deployment

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
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
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "function_name" {
  description = "Name for the Cloud Function that generates screenshots"
  type        = string
  default     = "screenshot-generator"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.function_name))
    error_message = "Function name must start with a letter and contain only lowercase letters, numbers, and hyphens (max 63 characters)."
  }
}

variable "bucket_prefix" {
  description = "Prefix for the Cloud Storage bucket name (random suffix will be added)"
  type        = string
  default     = "screenshots"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_prefix))
    error_message = "Bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function (in MB)"
  type        = number
  default     = 1024
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function (in seconds)"
  type        = number
  default     = 540
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_public_access" {
  description = "Whether to enable public read access to the storage bucket"
  type        = bool
  default     = true
}

variable "cors_origins" {
  description = "List of origins allowed for CORS requests to the Cloud Function"
  type        = list(string)
  default     = ["*"]
}

variable "environment_variables" {
  description = "Additional environment variables for the Cloud Function"
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "screenshot-api"
    environment = "development"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection on critical resources"
  type        = bool
  default     = false
}