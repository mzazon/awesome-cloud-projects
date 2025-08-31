# Input Variables for Weather API Infrastructure
# This file defines all configurable parameters for the deployment

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must be a valid GCP project identifier."
  }
}

variable "region" {
  description = "The GCP region for deploying resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "function_name" {
  description = "Name of the Cloud Function for the weather API"
  type        = string
  default     = "weather-api"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "weather_api_key" {
  description = "OpenWeatherMap API key for fetching weather data"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.weather_api_key) > 0
    error_message = "Weather API key must not be empty. Get your key from openweathermap.org"
  }
}

variable "firestore_location" {
  description = "Location for Firestore database (must be a multi-region or region)"
  type        = string
  default     = "nam5"
  
  validation {
    condition = contains([
      "nam5", "eur3", "asia-northeast1", "us-central1", "us-east1",
      "us-west1", "europe-west1", "asia-east1"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or regional location."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 MB and 8192 MB."
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

variable "cache_ttl_minutes" {
  description = "Cache TTL in minutes for weather data in Firestore"
  type        = number
  default     = 10
  
  validation {
    condition     = var.cache_ttl_minutes >= 1 && var.cache_ttl_minutes <= 1440
    error_message = "Cache TTL must be between 1 and 1440 minutes (24 hours)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "enable_cors" {
  description = "Enable CORS headers for web application access"
  type        = bool
  default     = true
}

variable "allowed_origins" {
  description = "List of allowed origins for CORS (use ['*'] for all origins)"
  type        = list(string)
  default     = ["*"]
}

variable "function_labels" {
  description = "Labels to apply to the Cloud Function"
  type        = map(string)
  default = {
    component = "weather-api"
    managed-by = "terraform"
  }
}

variable "enable_public_access" {
  description = "Allow unauthenticated access to the Cloud Function"
  type        = bool
  default     = true
}