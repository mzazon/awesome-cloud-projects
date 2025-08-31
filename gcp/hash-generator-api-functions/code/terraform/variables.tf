# variables.tf - Input variables for the hash generator API infrastructure

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
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
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Cloud Functions."
  }
}

variable "function_name" {
  description = "The name of the Cloud Function"
  type        = string
  default     = "hash-generator"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "runtime" {
  description = "The runtime environment for the Cloud Function"
  type        = string
  default     = "python312"
  
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312"
    ], var.runtime)
    error_message = "Runtime must be a supported Python version."
  }
}

variable "memory_mb" {
  description = "The amount of memory in MB allocated to the Cloud Function"
  type        = number
  default     = 256
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.memory_mb)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "timeout_seconds" {
  description = "The timeout duration in seconds for the Cloud Function"
  type        = number
  default     = 60
  
  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

variable "allow_unauthenticated" {
  description = "Whether to allow unauthenticated invocations of the function"
  type        = bool
  default     = true
}

variable "max_instances" {
  description = "The maximum number of function instances that can run simultaneously"
  type        = number
  default     = 100
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

variable "min_instances" {
  description = "The minimum number of function instances to keep warm"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "source_dir" {
  description = "Local directory containing the Cloud Function source code"
  type        = string
  default     = "../function-source"
}

variable "environment_variables" {
  description = "Environment variables to set for the Cloud Function"
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "demo"
    application = "hash-generator"
    managed-by  = "terraform"
  }
}

variable "enable_logging" {
  description = "Whether to enable Cloud Logging for the function"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring for the function"
  type        = bool
  default     = true
}

variable "ingress_settings" {
  description = "The ingress settings for the function"
  type        = string
  default     = "ALLOW_ALL"
  
  validation {
    condition = contains([
      "ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"
    ], var.ingress_settings)
    error_message = "Ingress settings must be one of: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  }
}