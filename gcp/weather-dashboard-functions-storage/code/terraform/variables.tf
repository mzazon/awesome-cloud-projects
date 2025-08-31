# variables.tf - Input variables for the Weather Dashboard infrastructure
#
# This file defines all configurable parameters for the serverless weather dashboard
# deployment, allowing customization of project settings, resource configurations,
# and operational parameters.

# Project Configuration Variables
variable "project_id" {
  description = "The Google Cloud project ID where resources will be deployed"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for deploying regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

# Application Configuration Variables
variable "application_name" {
  description = "Base name for the weather dashboard application resources"
  type        = string
  default     = "weather-dashboard"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.application_name))
    error_message = "Application name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with alphanumeric character."
  }
}

variable "environment" {
  description = "Environment identifier (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Weather API Configuration
variable "weather_api_key" {
  description = "OpenWeatherMap API key for fetching weather data"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.weather_api_key) > 10
    error_message = "Weather API key must be provided and be longer than 10 characters."
  }
}

variable "default_city" {
  description = "Default city to display weather information for"
  type        = string
  default     = "San Francisco"
  
  validation {
    condition     = length(var.default_city) > 0
    error_message = "Default city name cannot be empty."
  }
}

# Cloud Function Configuration Variables
variable "function_name" {
  description = "Name of the Cloud Function for weather API"
  type        = string
  default     = "weather-api"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "python311"
  
  validation {
    condition = contains([
      "python37", "python38", "python39", "python310", "python311", "python312",
      "nodejs16", "nodejs18", "nodejs20",
      "go116", "go118", "go119", "go120", "go121",
      "java11", "java17", "java21"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Google Cloud Functions runtime."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function"
  type        = string
  default     = "256Mi"
  
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi", "16Gi", "32Gi"
    ], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions memory allocation."
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
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances (0 for serverless)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

# Cloud Storage Configuration Variables
variable "storage_class" {
  description = "Storage class for the website hosting bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE", "REGIONAL", "MULTI_REGIONAL"
    ], var.storage_class)
    error_message = "Storage class must be a valid Google Cloud Storage class."
  }
}

variable "bucket_location" {
  description = "Location for the Cloud Storage bucket (can be region or multi-region)"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "ASIA",
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3"
    ], var.bucket_location)
    error_message = "Bucket location must be a valid Google Cloud Storage location."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on the storage bucket"
  type        = bool
  default     = false
}

variable "enable_cors" {
  description = "Enable CORS configuration for the storage bucket"
  type        = bool
  default     = true
}

# Security and Access Control Variables
variable "allow_unauthenticated_function_access" {
  description = "Allow unauthenticated access to the Cloud Function"
  type        = bool
  default     = true
}

variable "enable_public_bucket_access" {
  description = "Enable public access to the website bucket"
  type        = bool
  default     = true
}

variable "force_destroy_bucket" {
  description = "Allow Terraform to destroy the bucket with objects inside"
  type        = bool
  default     = false
}

# Monitoring and Logging Variables
variable "enable_function_logging" {
  description = "Enable Cloud Logging for the function"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Logging level for the application"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

# Resource Tagging Variables
variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    terraform   = "true"
    application = "weather-dashboard"
    component   = "serverless-web-app"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain lowercase letters, numbers, underscores, and hyphens."
  }
}

# Cost Management Variables
variable "budget_amount" {
  description = "Monthly budget amount in USD for cost monitoring (optional)"
  type        = number
  default     = null
  
  validation {
    condition     = var.budget_amount == null || var.budget_amount > 0
    error_message = "Budget amount must be greater than 0 if specified."
  }
}

# Development and Testing Variables
variable "enable_debug_mode" {
  description = "Enable debug mode with additional logging and relaxed security"
  type        = bool
  default     = false
}

variable "cors_origins" {
  description = "List of allowed CORS origins for the storage bucket"
  type        = list(string)
  default     = ["*"]
  
  validation {
    condition     = length(var.cors_origins) > 0
    error_message = "At least one CORS origin must be specified."
  }
}

variable "cors_methods" {
  description = "List of allowed CORS methods"
  type        = list(string)
  default     = ["GET", "HEAD", "OPTIONS"]
  
  validation {
    condition = alltrue([
      for method in var.cors_methods : contains(["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "PATCH"], method)
    ])
    error_message = "CORS methods must be valid HTTP methods."
  }
}