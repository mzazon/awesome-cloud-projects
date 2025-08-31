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
  description = "The Google Cloud region for the Cloud Run service"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Cloud Run."
  }
}

# Function configuration variables
variable "function_name" {
  description = "Name of the Cloud Run service (replacing Cloud Functions Gen 1)"
  type        = string
  default     = "weather-forecast"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.function_name))
    error_message = "Function name must start with a lowercase letter, followed by lowercase letters, numbers, or hyphens, and end with a lowercase letter or number."
  }
}

variable "function_description" {
  description = "Description of the weather forecast function"
  type        = string
  default     = "Serverless weather forecast API built with Cloud Functions"
}

# Runtime configuration variables
variable "memory_limit" {
  description = "Memory allocation for the Cloud Run service (e.g., 512Mi, 1Gi)"
  type        = string
  default     = "512Mi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.memory_limit)
    error_message = "Memory limit must be a valid Cloud Run memory allocation (128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, or 8Gi)."
  }
}

variable "cpu_limit" {
  description = "CPU allocation for the Cloud Run service"
  type        = string
  default     = "1"
  validation {
    condition = contains([
      "0.08", "0.17", "0.25", "0.33", "0.5", "0.58", "0.67", "0.75", "0.83", "1", "2", "4", "6", "8"
    ], var.cpu_limit)
    error_message = "CPU limit must be a valid Cloud Run CPU allocation."
  }
}

variable "timeout_seconds" {
  description = "Request timeout in seconds for the Cloud Run service"
  type        = number
  default     = 60
  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

variable "max_instances" {
  description = "Maximum number of instances for the Cloud Run service"
  type        = number
  default     = 100
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "min_instances" {
  description = "Minimum number of instances for the Cloud Run service (0 for serverless)"
  type        = number
  default     = 0
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "concurrency" {
  description = "Maximum number of concurrent requests per instance"
  type        = number
  default     = 80
  validation {
    condition     = var.concurrency >= 1 && var.concurrency <= 1000
    error_message = "Concurrency must be between 1 and 1000."
  }
}

# API configuration variables
variable "openweather_api_key" {
  description = "OpenWeatherMap API key for weather data (use 'demo_key' for testing)"
  type        = string
  default     = "demo_key"
  sensitive   = true
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the Cloud Run service"
  type        = bool
  default     = true
}

# Monitoring and logging variables
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for the function"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Cloud Logging for the function"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Log level for the function (DEBUG, INFO, WARNING, ERROR, CRITICAL)"
  type        = string
  default     = "INFO"
  validation {
    condition = contains([
      "DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"
    ], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

# Tagging and organization variables
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "demo"
    project     = "weather-forecast-api"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z]([a-z0-9_-]*[a-z0-9])?$", k))
    ])
    error_message = "Label keys must start with a lowercase letter, followed by lowercase letters, numbers, underscores, or hyphens, and end with a lowercase letter or number."
  }
}

# Source code variables
variable "source_archive_bucket" {
  description = "Google Cloud Storage bucket for storing function source code"
  type        = string
  default     = ""
}

variable "source_archive_object" {
  description = "Google Cloud Storage object name for function source code archive"
  type        = string
  default     = ""
}

# Networking variables
variable "ingress" {
  description = "Ingress settings for the Cloud Run service"
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"
  validation {
    condition = contains([
      "INGRESS_TRAFFIC_ALL",
      "INGRESS_TRAFFIC_INTERNAL_ONLY",
      "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    ], var.ingress)
    error_message = "Ingress must be one of: INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY, INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }
}