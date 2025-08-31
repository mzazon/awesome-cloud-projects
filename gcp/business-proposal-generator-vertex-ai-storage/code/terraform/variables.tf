# Core project configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region where resources will be deployed"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports Vertex AI."
  }
}

# Resource naming configuration
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "proposal-gen"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Cloud Storage configuration
variable "storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE", "REGIONAL", "MULTI_REGIONAL"
    ], var.storage_class)
    error_message = "Storage class must be a valid Cloud Storage class."
  }
}

variable "bucket_versioning_enabled" {
  description = "Enable versioning on Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "bucket_uniform_access" {
  description = "Enable uniform bucket-level access for Cloud Storage buckets"
  type        = bool
  default     = true
}

# Cloud Function configuration
variable "function_runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "nodejs20"
  validation {
    condition = contains([
      "nodejs18", "nodejs20", "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 512
  validation {
    condition     = var.function_memory_mb >= 128 && var.function_memory_mb <= 8192
    error_message = "Function memory must be between 128 MB and 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Function execution in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
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

# Vertex AI configuration
variable "vertex_ai_model" {
  description = "Vertex AI model to use for proposal generation"
  type        = string
  default     = "gemini-1.5-flash"
  validation {
    condition = contains([
      "gemini-1.5-flash", "gemini-1.5-pro", "gemini-pro", "text-bison"
    ], var.vertex_ai_model)
    error_message = "Model must be a supported Vertex AI generative model."
  }
}

variable "vertex_ai_max_tokens" {
  description = "Maximum output tokens for Vertex AI model"
  type        = number
  default     = 2048
  validation {
    condition     = var.vertex_ai_max_tokens >= 1 && var.vertex_ai_max_tokens <= 8192
    error_message = "Max tokens must be between 1 and 8192."
  }
}

variable "vertex_ai_temperature" {
  description = "Temperature parameter for Vertex AI model (controls randomness)"
  type        = number
  default     = 0.3
  validation {
    condition     = var.vertex_ai_temperature >= 0.0 && var.vertex_ai_temperature <= 2.0
    error_message = "Temperature must be between 0.0 and 2.0."
  }
}

variable "vertex_ai_top_p" {
  description = "Top-p parameter for Vertex AI model (nucleus sampling)"
  type        = number
  default     = 0.8
  validation {
    condition     = var.vertex_ai_top_p >= 0.0 && var.vertex_ai_top_p <= 1.0
    error_message = "Top-p must be between 0.0 and 1.0."
  }
}

variable "vertex_ai_top_k" {
  description = "Top-k parameter for Vertex AI model (top-k sampling)"
  type        = number
  default     = 40
  validation {
    condition     = var.vertex_ai_top_k >= 1 && var.vertex_ai_top_k <= 40
    error_message = "Top-k must be between 1 and 40."
  }
}

# Security and IAM configuration
variable "enable_cloud_armor" {
  description = "Enable Cloud Armor protection for the function"
  type        = bool
  default     = false
}

variable "allowed_members" {
  description = "List of members allowed to invoke the Cloud Function"
  type        = list(string)
  default     = []
}

# API services configuration
variable "enable_apis" {
  description = "Whether to enable required APIs (disable if APIs are already enabled)"
  type        = bool
  default     = true
}

# Monitoring and logging
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for the function"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Labels and tags
variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    application = "proposal-generator"
    component   = "ai-automation"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain lowercase letters, numbers, underscores, and hyphens."
  }
}