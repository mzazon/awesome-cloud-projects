# Variable Definitions for AI Content Validation Infrastructure
# This file defines all configurable parameters for the content validation system

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region for regional resources (functions, storage)"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources (if needed)"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., us-central1-a)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for unique resource naming"
  type        = number
  default     = 6
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 8
    error_message = "Random suffix length must be between 4 and 8 characters."
  }
}

# Storage Configuration Variables
variable "content_bucket_location" {
  description = "Location for the content input bucket (STANDARD, NEARLINE, COLDLINE, ARCHIVE)"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.content_bucket_location)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "results_bucket_location" {
  description = "Location for the validation results bucket storage class"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.results_bucket_location)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_versioning_enabled" {
  description = "Enable versioning on storage buckets for data protection"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_enabled" {
  description = "Enable lifecycle management on storage buckets"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age_days" {
  description = "Number of days after which objects are moved to cheaper storage class"
  type        = number
  default     = 30
  validation {
    condition     = var.bucket_lifecycle_age_days > 0 && var.bucket_lifecycle_age_days <= 365
    error_message = "Lifecycle age must be between 1 and 365 days."
  }
}

# Cloud Function Configuration Variables
variable "function_runtime" {
  description = "Runtime environment for the Cloud Function"
  type        = string
  default     = "python312"
  validation {
    condition = contains(["python39", "python310", "python311", "python312"], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = string
  default     = "512Mi"
  validation {
    condition = contains(["128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions memory allocation."
  }
}

variable "function_timeout" {
  description = "Maximum execution time for Cloud Function in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 10
    error_message = "Minimum instances must be between 0 and 10."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances for scaling"
  type        = number
  default     = 10
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 100
    error_message = "Maximum instances must be between 1 and 100."
  }
}

variable "function_concurrency" {
  description = "Maximum number of concurrent requests per function instance"
  type        = number
  default     = 1
  validation {
    condition     = var.function_concurrency >= 1 && var.function_concurrency <= 1000
    error_message = "Concurrency must be between 1 and 1000."
  }
}

# Vertex AI Configuration Variables
variable "vertex_ai_location" {
  description = "Location for Vertex AI resources (must support Gemini models)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.vertex_ai_location)
    error_message = "Vertex AI location must support Gemini models."
  }
}

variable "gemini_model_name" {
  description = "Gemini model name for content validation"
  type        = string
  default     = "gemini-1.5-flash"
  validation {
    condition = contains([
      "gemini-1.5-flash",
      "gemini-1.5-pro",
      "gemini-1.0-pro"
    ], var.gemini_model_name)
    error_message = "Model must be a supported Gemini model version."
  }
}

variable "safety_threshold" {
  description = "Safety threshold for content validation (BLOCK_NONE, BLOCK_LOW_AND_ABOVE, BLOCK_MEDIUM_AND_ABOVE, BLOCK_ONLY_HIGH)"
  type        = string
  default     = "BLOCK_MEDIUM_AND_ABOVE"
  validation {
    condition = contains([
      "BLOCK_NONE",
      "BLOCK_LOW_AND_ABOVE", 
      "BLOCK_MEDIUM_AND_ABOVE",
      "BLOCK_ONLY_HIGH"
    ], var.safety_threshold)
    error_message = "Safety threshold must be a valid safety setting."
  }
}

# Monitoring and Logging Configuration
variable "enable_cloud_logging" {
  description = "Enable detailed Cloud Logging for function execution"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Logging level for the function (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "INFO"
  validation {
    condition = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR."
  }
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for performance metrics"
  type        = bool
  default     = true
}

variable "monitoring_notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

# Security and Access Control
variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for enhanced security"
  type        = bool
  default     = true
}

variable "enable_public_access_prevention" {
  description = "Prevent public access to storage buckets"
  type        = bool
  default     = true
}

variable "allowed_principals" {
  description = "List of principals allowed to invoke the function (emails, service accounts)"
  type        = list(string)
  default     = []
}

variable "enable_vpc_connector" {
  description = "Enable VPC connector for function networking"
  type        = bool
  default     = false
}

variable "vpc_connector_name" {
  description = "Name of existing VPC connector (if enable_vpc_connector is true)"
  type        = string
  default     = ""
}

# Performance and Cost Optimization
variable "enable_function_cpu_boost" {
  description = "Enable CPU boost for improved cold start performance"
  type        = bool
  default     = false
}

variable "enable_bucket_request_payer" {
  description = "Enable request payer for storage bucket cost optimization"
  type        = bool
  default     = false
}

variable "bucket_retention_days" {
  description = "Number of days to retain validation results before deletion"
  type        = number
  default     = 90
  validation {
    condition     = var.bucket_retention_days >= 1 && var.bucket_retention_days <= 3650
    error_message = "Retention days must be between 1 and 3650 (10 years)."
  }
}

# API Configuration
variable "enable_apis" {
  description = "List of additional APIs to enable beyond the required ones"
  type        = list(string)
  default     = []
}

variable "disable_dependent_services" {
  description = "Whether to disable dependent services when destroying resources"
  type        = bool
  default     = false
}

# Resource Labels and Tags
variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "ai-content-validation"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}