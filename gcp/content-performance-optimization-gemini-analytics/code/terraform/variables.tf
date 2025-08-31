# Input variables for GCP content performance optimization infrastructure
# These variables allow customization of the deployment

variable "project_id" {
  description = "Google Cloud project ID for deploying content optimization resources"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must be specified and cannot be empty."
  }
}

variable "region" {
  description = "Google Cloud region for deploying regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "Google Cloud zone for deploying zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "dataset_name" {
  description = "BigQuery dataset name for content analytics data"
  type        = string
  default     = "content_analytics"
  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.dataset_name))
    error_message = "Dataset name must start with a letter or underscore and contain only letters, numbers, and underscores."
  }
}

variable "table_name" {
  description = "BigQuery table name for content performance data"
  type        = string
  default     = "performance_data"
  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.table_name))
    error_message = "Table name must start with a letter or underscore and contain only letters, numbers, and underscores."
  }
}

variable "function_name" {
  description = "Cloud Function name for content analysis engine"
  type        = string
  default     = "content-analyzer"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bucket_name" {
  description = "Cloud Storage bucket name for content assets and analysis results"
  type        = string
  default     = "content-optimization"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]*[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must start and end with alphanumeric characters and contain only lowercase letters, numbers, dots, and hyphens."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "enable_sample_data" {
  description = "Whether to load sample content performance data into BigQuery"
  type        = bool
  default     = true
}

variable "gemini_model" {
  description = "Vertex AI Gemini model to use for content analysis"
  type        = string
  default     = "gemini-2.5-flash"
  validation {
    condition     = contains(["gemini-1.5-pro", "gemini-1.5-flash", "gemini-2.5-flash"], var.gemini_model)
    error_message = "Gemini model must be one of: gemini-1.5-pro, gemini-1.5-flash, gemini-2.5-flash."
  }
}

variable "labels" {
  description = "Labels to apply to all resources for organization and cost tracking"
  type        = map(string)
  default = {
    environment = "dev"
    purpose     = "content-optimization"
    managed-by  = "terraform"
  }
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Maximum of 64 labels can be applied to a resource."
  }
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of critical resources"
  type        = bool
  default     = false
}