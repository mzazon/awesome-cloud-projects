# Variable definitions for the Timezone Converter API Cloud Function
# These variables allow customization of the deployment without modifying the main configuration

variable "project_id" {
  description = "The GCP project ID where resources will be created"
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
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports Cloud Functions Gen2."
  }
}

variable "function_name" {
  description = "Name of the Cloud Function (must be unique within the project)"
  type        = string
  default     = "timezone-converter"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.function_name))
    error_message = "Function name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function (in MB)"
  type        = string
  default     = "256M"
  validation {
    condition = contains([
      "128M", "256M", "512M", "1024M", "2048M", "4096M", "8192M"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128M, 256M, 512M, 1024M, 2048M, 4096M, 8192M."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function (in seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "python312"
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312"
    ], var.runtime)
    error_message = "Runtime must be a supported Python version: python39, python310, python311, or python312."
  }
}

variable "entry_point" {
  description = "The name of the function (as defined in source code) that will be executed"
  type        = string
  default     = "convert_timezone"
}

variable "allow_unauthenticated" {
  description = "Whether to allow unauthenticated HTTP invocations of the function"
  type        = bool
  default     = true
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
    application = "timezone-converter"
    environment = "production"
    managed-by  = "terraform"
  }
}

variable "service_config" {
  description = "Advanced service configuration settings"
  type = object({
    max_instance_count               = optional(number, 100)
    min_instance_count               = optional(number, 0)
    available_memory                 = optional(string, null)
    timeout_seconds                  = optional(number, null)
    max_instance_request_concurrency = optional(number, 80)
    available_cpu                    = optional(string, "1")
    ingress_settings                 = optional(string, "ALLOW_ALL")
    all_traffic_on_latest_revision   = optional(bool, true)
  })
  default = {}
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}