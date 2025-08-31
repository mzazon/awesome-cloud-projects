# Core project configuration variables
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_id))
    error_message = "Project ID must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for resources that require it"
  type        = string
  default     = "us-central1-a"
}

# Resource naming and tagging variables
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "adk-code-docs"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Cloud Function configuration variables
variable "function_name" {
  description = "Name of the Cloud Function for ADK code documentation"
  type        = string
  default     = "adk-code-documentation"
}

variable "function_runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a valid Python runtime version."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 1024
  validation {
    condition     = var.function_memory >= 256 && var.function_memory <= 8192
    error_message = "Function memory must be between 256 MB and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 60 and 3600 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

# Cloud Storage configuration variables
variable "storage_location" {
  description = "Location for Cloud Storage buckets"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.storage_location)
    error_message = "Storage location must be a valid Cloud Storage location."
  }
}

variable "storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_lifecycle_age" {
  description = "Age in days after which to delete objects in temporary storage bucket"
  type        = number
  default     = 30
  validation {
    condition     = var.bucket_lifecycle_age >= 1 && var.bucket_lifecycle_age <= 365
    error_message = "Bucket lifecycle age must be between 1 and 365 days."
  }
}

# Vertex AI configuration variables
variable "vertex_ai_location" {
  description = "Location for Vertex AI resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west4",
      "europe-west1", "europe-west2", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.vertex_ai_location)
    error_message = "Vertex AI location must be a valid region that supports Vertex AI."
  }
}

variable "gemini_model" {
  description = "Gemini model version to use for ADK agents"
  type        = string
  default     = "gemini-1.5-pro"
  validation {
    condition = contains([
      "gemini-1.5-pro", "gemini-1.5-flash", "gemini-pro"
    ], var.gemini_model)
    error_message = "Gemini model must be one of the supported versions."
  }
}

# Security and IAM configuration variables
variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Enable versioning for Cloud Storage buckets"
  type        = bool
  default     = false
}

variable "enable_encryption" {
  description = "Enable customer-managed encryption for resources"
  type        = bool
  default     = false
}

# Monitoring and logging configuration variables
variable "enable_function_logging" {
  description = "Enable detailed logging for Cloud Functions"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Log level for Cloud Function"
  type        = string
  default     = "INFO"
  validation {
    condition = contains([
      "DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"
    ], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

# Resource labeling
variable "labels" {
  description = "Additional labels to apply to resources"
  type        = map(string)
  default = {
    recipe      = "smart-code-documentation-adk-functions"
    managed-by  = "terraform"
    component   = "adk-documentation"
  }
  validation {
    condition = alltrue([
      for key, value in var.labels : can(regex("^[a-z0-9_-]+$", key)) && can(regex("^[a-z0-9_-]+$", value))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Development and testing variables
variable "create_sample_repository" {
  description = "Create a sample code repository for testing the documentation system"
  type        = bool
  default     = true
}

variable "enable_debug_mode" {
  description = "Enable debug mode for enhanced logging and monitoring"
  type        = bool
  default     = false
}