# Variables for Smart Document Review Workflow with ADK and Storage
# This file defines all configurable parameters for the infrastructure deployment

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
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
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for resources that require zone specification"
  type        = string
  default     = "us-central1-a"
}

variable "resource_prefix" {
  description = "Prefix for naming resources to ensure uniqueness"
  type        = string
  default     = "doc-review"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
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

# Storage Configuration
variable "storage_class" {
  description = "Storage class for the buckets"
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
  description = "Enable versioning on storage buckets"
  type        = bool
  default     = true
}

variable "lifecycle_age" {
  description = "Age in days for lifecycle management of storage objects"
  type        = number
  default     = 30
  validation {
    condition     = var.lifecycle_age > 0 && var.lifecycle_age <= 365
    error_message = "Lifecycle age must be between 1 and 365 days."
  }
}

# Cloud Function Configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = string
  default     = "512M"
  validation {
    condition = contains([
      "128M", "256M", "512M", "1G", "2G", "4G", "8G"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128M, 256M, 512M, 1G, 2G, 4G, 8G."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function execution in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 100
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

variable "python_runtime" {
  description = "Python runtime version for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312"
    ], var.python_runtime)
    error_message = "Python runtime must be one of: python39, python310, python311, python312."
  }
}

# AI/ML Configuration
variable "enable_vertex_ai" {
  description = "Enable Vertex AI API for agent processing"
  type        = bool
  default     = true
}

variable "gemini_model" {
  description = "Gemini model to use for agent processing"
  type        = string
  default     = "gemini-2.0-flash"
  validation {
    condition = contains([
      "gemini-1.5-pro", "gemini-1.5-flash", "gemini-2.0-flash"
    ], var.gemini_model)
    error_message = "Gemini model must be one of: gemini-1.5-pro, gemini-1.5-flash, gemini-2.0-flash."
  }
}

# Monitoring and Logging
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for resources"
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

# Security Configuration
variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for enhanced security"
  type        = bool
  default     = true
}

variable "cors_origins" {
  description = "CORS origins for bucket access"
  type        = list(string)
  default     = ["*"]
}

# Tagging
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "document-review"
    managed-by  = "terraform"
    component   = "smart-document-review"
  }
}

# Budget and Cost Control
variable "budget_amount" {
  description = "Monthly budget amount in USD for cost monitoring"
  type        = number
  default     = 100
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "enable_budget_alerts" {
  description = "Enable budget alerts for cost monitoring"
  type        = bool
  default     = true
}