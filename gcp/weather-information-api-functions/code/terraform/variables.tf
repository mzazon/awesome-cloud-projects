# Project Configuration Variables
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for Cloud Functions deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports Cloud Functions."
  }
}

# Function Configuration Variables
variable "function_name" {
  description = "Name of the Cloud Function for the weather API"
  type        = string
  default     = "weather-api"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.function_name))
    error_message = "Function name must be lowercase, 1-63 characters, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "function_runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "python312"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312",
      "nodejs16", "nodejs18", "nodejs20",
      "go116", "go118", "go119", "go120", "go121",
      "java11", "java17", "java21"
    ], var.function_runtime)
    error_message = "Runtime must be a supported Cloud Functions runtime version."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function (in MB)"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, or 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function (in seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 1000
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

# Environment and Configuration Variables
variable "weather_api_key" {
  description = "API key for OpenWeatherMap service (optional - uses demo data if not provided)"
  type        = string
  default     = "demo_key_please_replace"
  sensitive   = true
}

variable "enable_public_access" {
  description = "Whether to allow unauthenticated access to the function"
  type        = bool
  default     = true
}

variable "cors_origins" {
  description = "List of allowed CORS origins for the function"
  type        = list(string)
  default     = ["*"]
}

# Storage Configuration Variables
variable "source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code (will be created if not exists)"
  type        = string
  default     = ""
}

variable "source_archive_object" {
  description = "Name of the source archive object in the bucket"
  type        = string
  default     = "weather-function-source.zip"
}

# Monitoring and Logging Variables
variable "enable_logging" {
  description = "Enable Cloud Logging for the function"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Logging level for the function"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

# Security Variables
variable "vpc_connector" {
  description = "VPC connector for the function (optional)"
  type        = string
  default     = null
}

variable "ingress_settings" {
  description = "Ingress settings for the function"
  type        = string
  default     = "ALLOW_ALL"
  validation {
    condition     = contains(["ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"], var.ingress_settings)
    error_message = "Ingress settings must be one of: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  }
}

# Resource Labeling Variables
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    project     = "weather-api"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must be lowercase, 1-63 characters, start with a letter, and contain only letters, numbers, underscores, and hyphens."
  }
}

# Service Account Variables
variable "create_service_account" {
  description = "Whether to create a dedicated service account for the function"
  type        = bool
  default     = true
}

variable "service_account_name" {
  description = "Name of the service account (created if create_service_account is true)"
  type        = string
  default     = "weather-api-sa"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_account_name))
    error_message = "Service account name must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}