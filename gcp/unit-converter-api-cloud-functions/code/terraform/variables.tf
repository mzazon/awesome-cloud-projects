# Project configuration variables
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
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
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Cloud Functions."
  }
}

# Cloud Function configuration variables
variable "function_name" {
  description = "Name of the Cloud Function"
  type        = string
  default     = "unit-converter-api"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name)) && length(var.function_name) <= 63
    error_message = "Function name must start with a letter, contain only lowercase letters, numbers, and hyphens, and be at most 63 characters long."
  }
}

variable "function_description" {
  description = "Description of the Cloud Function"
  type        = string
  default     = "Serverless REST API for unit conversions supporting temperature, distance, and weight conversions"
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 256
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

variable "python_runtime" {
  description = "Python runtime version for the Cloud Function"
  type        = string
  default     = "python312"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312"
    ], var.python_runtime)
    error_message = "Python runtime must be one of: python38, python39, python310, python311, python312."
  }
}

# Security and access configuration
variable "allow_unauthenticated" {
  description = "Whether to allow unauthenticated access to the function"
  type        = bool
  default     = true
}

variable "max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 100
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

variable "min_instances" {
  description = "Minimum number of function instances (0 for serverless)"
  type        = number
  default     = 0
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

# Source code configuration
variable "source_directory" {
  description = "Local directory containing the function source code"
  type        = string
  default     = "../function-source"
}

# Labels and tagging
variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    environment = "demo"
    purpose     = "unit-converter-api"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Service configuration
variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "required_apis" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}