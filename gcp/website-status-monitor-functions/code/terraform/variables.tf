# Variables for the Website Status Monitor Cloud Function

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region where the Cloud Function will be deployed"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "function_name" {
  description = "Name of the Cloud Function"
  type        = string
  default     = "website-status-monitor"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.function_name))
    error_message = "Function name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "function_description" {
  description = "Description of the Cloud Function"
  type        = string
  default     = "Serverless website status monitoring API that checks website availability, response times, and health metrics"
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function (in MB)"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function (in seconds)"
  type        = number
  default     = 30
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
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

variable "max_instances" {
  description = "Maximum number of function instances that can be created"
  type        = number
  default     = 100
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

variable "min_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "environment_variables" {
  description = "Environment variables for the Cloud Function"
  type        = map(string)
  default = {
    LOG_LEVEL = "INFO"
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    application = "website-monitor"
    managed-by  = "terraform"
  }
}

variable "enable_logging" {
  description = "Enable detailed logging for the Cloud Function"
  type        = bool
  default     = true
}

variable "ingress_settings" {
  description = "Ingress settings for the Cloud Function"
  type        = string
  default     = "ALLOW_ALL"
  validation {
    condition = contains([
      "ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"
    ], var.ingress_settings)
    error_message = "Ingress settings must be one of: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  }
}

variable "enable_unauthenticated_access" {
  description = "Allow unauthenticated access to the Cloud Function"
  type        = bool
  default     = true
}

variable "source_code_path" {
  description = "Path to the source code directory (relative to this terraform configuration)"
  type        = string
  default     = "../function-source"
}