# Input variables for GCP Text Case Converter API infrastructure

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region where the Cloud Function will be deployed"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-northeast2", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "function_name" {
  description = "Name of the Cloud Function for text case conversion"
  type        = string
  default     = "text-case-converter"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a lowercase letter or number."
  }
}

variable "function_description" {
  description = "Description of the Cloud Function"
  type        = string
  default     = "HTTP API for converting text between different case formats (uppercase, lowercase, camelCase, snake_case, etc.)"
}

variable "function_source_path" {
  description = "Local path to the function source code directory"
  type        = string
  default     = "../function-source"
}

variable "memory_mb" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.memory_mb)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, or 8192 MB."
  }
}

variable "timeout_seconds" {
  description = "Maximum execution time for the function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

variable "max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "min_instances" {
  description = "Minimum number of function instances (0 for scale-to-zero)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= var.max_instances
    error_message = "Min instances must be >= 0 and <= max_instances."
  }
}

variable "allow_unauthenticated" {
  description = "Whether to allow unauthenticated access to the function"
  type        = bool
  default     = true
}

variable "runtime" {
  description = "Runtime environment for the Cloud Function"
  type        = string
  default     = "python311"
  
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312",
      "nodejs16", "nodejs18", "nodejs20"
    ], var.runtime)
    error_message = "Runtime must be a supported Cloud Functions runtime version."
  }
}

variable "entry_point" {
  description = "Name of the function to execute"
  type        = string
  default     = "text_case_converter"
}

variable "environment_variables" {
  description = "Environment variables for the Cloud Function"
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Labels to apply to Cloud Function resources"
  type        = map(string)
  default = {
    environment = "development"
    purpose     = "text-processing"
    managed-by  = "terraform"
  }
}