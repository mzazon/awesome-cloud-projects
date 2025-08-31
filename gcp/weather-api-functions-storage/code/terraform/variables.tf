# Variable definitions for the Weather API infrastructure
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "function_name" {
  description = "Name of the Cloud Function for the weather API"
  type        = string
  default     = "weather-api"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-])*[a-z0-9]$", var.function_name))
    error_message = "Function name must contain only lowercase letters, numbers, and hyphens, and must start and end with a letter or number."
  }
}

variable "bucket_name" {
  description = "Name of the Cloud Storage bucket for caching weather data. If not provided, a random name will be generated."
  type        = string
  default     = ""
  validation {
    condition = var.bucket_name == "" || can(regex("^[a-z0-9._-]+$", var.bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, dots, hyphens, and underscores."
  }
}

variable "weather_api_key" {
  description = "API key for the external weather service (OpenWeatherMap). Use 'demo_key' for testing."
  type        = string
  default     = "demo_key"
  sensitive   = true
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, or 8192 MB."
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

variable "function_max_instances" {
  description = "Maximum number of concurrent function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Maximum instances must be between 1 and 3000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Minimum instances must be between 0 and 1000."
  }
}

variable "bucket_location" {
  description = "Location for the Cloud Storage bucket (region or multi-region)"
  type        = string
  default     = "US"
  validation {
    condition = contains(["US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", "europe-west1", "asia-east1"], var.bucket_location)
    error_message = "Bucket location must be a valid Google Cloud Storage location."
  }
}

variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs automatically"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    application = "weather-api"
    managed-by  = "terraform"
  }
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Maximum of 64 labels allowed per resource."
  }
}

variable "cache_duration_minutes" {
  description = "Duration in minutes to cache weather data in Cloud Storage"
  type        = number
  default     = 10
  validation {
    condition     = var.cache_duration_minutes >= 1 && var.cache_duration_minutes <= 1440
    error_message = "Cache duration must be between 1 and 1440 minutes (24 hours)."
  }
}