# Project configuration variables
variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region."
  }
}

# Firebase project configuration
variable "firebase_project_display_name" {
  description = "The display name for the Firebase project"
  type        = string
  default     = "Collaborative Document Editor"
}

# Cloud Functions configuration
variable "functions_source_bucket" {
  description = "The name of the GCS bucket to store Cloud Functions source code"
  type        = string
  default     = null
}

variable "nodejs_runtime" {
  description = "The Node.js runtime version for Cloud Functions"
  type        = string
  default     = "nodejs18"
  validation {
    condition     = contains(["nodejs16", "nodejs18", "nodejs20"], var.nodejs_runtime)
    error_message = "Node.js runtime must be one of: nodejs16, nodejs18, nodejs20."
  }
}

# Firebase Realtime Database configuration
variable "database_instance_id" {
  description = "The instance ID for Firebase Realtime Database"
  type        = string
  default     = "default"
}

variable "database_region" {
  description = "The region for Firebase Realtime Database"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "europe-west1", "asia-southeast1"
    ], var.database_region)
    error_message = "Database region must be one of the supported Firebase regions."
  }
}

# Firebase Authentication configuration
variable "auth_providers" {
  description = "List of authentication providers to enable"
  type        = list(string)
  default     = ["email", "google.com"]
  validation {
    condition     = length(var.auth_providers) > 0
    error_message = "At least one authentication provider must be specified."
  }
}

# Firebase Hosting configuration
variable "hosting_site_id" {
  description = "The site ID for Firebase Hosting (defaults to project_id)"
  type        = string
  default     = null
}

# Resource naming and tagging
variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "collab-app"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
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

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "collaborative-editor"
    managed-by  = "terraform"
  }
}

# Security configuration
variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "enable_audit_logs" {
  description = "Enable audit logging for Firebase services"
  type        = bool
  default     = true
}

# Function configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 256
  validation {
    condition     = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

# Storage configuration
variable "storage_class" {
  description = "Storage class for the GCS bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}