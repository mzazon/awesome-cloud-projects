# Input variables for basic application logging with Cloud Functions infrastructure

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region where resources will be deployed"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Cloud Functions."
  }
}

variable "function_name" {
  description = "Name of the Cloud Function for logging demonstration"
  type        = string
  default     = "logging-demo-function"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.function_name))
    error_message = "Function name must start with a lowercase letter, followed by lowercase letters, numbers, or hyphens, and must end with a lowercase letter or number."
  }
}

variable "function_memory" {
  description = "Memory allocated to the Cloud Function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "runtime" {
  description = "Runtime environment for the Cloud Function"
  type        = string
  default     = "python312"
  
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312",
      "nodejs18", "nodejs20", "go119", "go120", "go121",
      "java11", "java17", "dotnet6", "ruby30", "ruby32"
    ], var.runtime)
    error_message = "Runtime must be a supported Cloud Functions runtime version."
  }
}

variable "allow_unauthenticated" {
  description = "Whether to allow unauthenticated access to the Cloud Function"
  type        = bool
  default     = true
}

variable "environment_variables" {
  description = "Environment variables to set for the Cloud Function"
  type        = map(string)
  default = {
    LOG_LEVEL = "INFO"
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "demo"
    recipe      = "basic-application-logging"
    managed-by  = "terraform"
  }
}

variable "enable_logging" {
  description = "Whether to enable Cloud Logging API (should be true for this recipe)"
  type        = bool
  default     = true
}

variable "enable_functions" {
  description = "Whether to enable Cloud Functions API (should be true for this recipe)"
  type        = bool
  default     = true
}

variable "enable_cloudbuild" {
  description = "Whether to enable Cloud Build API (required for function deployment)"
  type        = bool
  default     = true
}