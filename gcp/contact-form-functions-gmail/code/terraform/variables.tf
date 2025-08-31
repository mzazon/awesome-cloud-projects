# Input variables for GCP Contact Form with Cloud Functions and Gmail API
# These variables allow customization of the infrastructure deployment

# Project Configuration
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
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports Cloud Functions."
  }
}

# Cloud Function Configuration
variable "function_name" {
  description = "Name of the Cloud Function for handling contact form submissions"
  type        = string
  default     = "contact-form-handler"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.function_name))
    error_message = "Function name must start with a letter, be lowercase, and contain only letters, numbers, and hyphens (max 63 chars)."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function (MB)"
  type        = number
  default     = 512
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function (seconds)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "python_runtime" {
  description = "Python runtime version for Cloud Functions"
  type        = string
  default     = "python312"
  
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312"
    ], var.python_runtime)
    error_message = "Python runtime must be one of: python39, python310, python311, python312."
  }
}

# Gmail API Configuration
variable "gmail_recipient_email" {
  description = "Email address that will receive contact form submissions"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.gmail_recipient_email))
    error_message = "Must be a valid email address format."
  }
}

variable "gmail_credentials_path" {
  description = "Path to the Gmail API OAuth 2.0 credentials JSON file"
  type        = string
  default     = "./credentials.json"
}

variable "gmail_token_path" {
  description = "Path to the Gmail API token pickle file"
  type        = string
  default     = "./token.pickle"
}

# Security Configuration
variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the Cloud Function (required for public contact forms)"
  type        = bool
  default     = true
}

variable "allowed_origins" {
  description = "List of allowed origins for CORS requests (use ['*'] for all origins)"
  type        = list(string)
  default     = ["*"]
}

# Resource Naming and Tagging
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,15}$", var.environment))
    error_message = "Environment must be lowercase, start with a letter, and be 16 characters or less."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "contact-form"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must be lowercase, start with a letter, and be 63 characters or less."
  }
}

# Storage Configuration
variable "create_storage_bucket" {
  description = "Whether to create a Cloud Storage bucket for function source code"
  type        = bool
  default     = true
}

variable "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket (leave empty for auto-generated name)"
  type        = string
  default     = ""
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

# API Configuration
variable "enable_apis" {
  description = "Whether to enable required GCP APIs automatically"
  type        = bool
  default     = true
}

variable "required_apis" {
  description = "List of GCP APIs required for the contact form solution"
  type        = list(string)
  default = [
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "gmail.googleapis.com",
    "storage.googleapis.com"
  ]
}

# Monitoring and Logging
variable "enable_function_logs" {
  description = "Whether to enable detailed logging for the Cloud Function"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Log level for the Cloud Function"
  type        = string
  default     = "INFO"
  
  validation {
    condition = contains([
      "DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"
    ], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

# Advanced Configuration
variable "max_instances" {
  description = "Maximum number of Cloud Function instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "min_instances" {
  description = "Minimum number of Cloud Function instances"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 100
    error_message = "Min instances must be between 0 and 100."
  }
}