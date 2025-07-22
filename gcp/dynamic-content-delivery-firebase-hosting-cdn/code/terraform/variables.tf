# ==========================================
# Input Variables for Dynamic Content Delivery
# ==========================================
# This file defines all input variables for the Firebase Hosting and Cloud CDN
# infrastructure deployment with proper validation and descriptions

# ==========================================
# Project and Location Variables
# ==========================================

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
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
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "location" {
  description = "The Google Cloud location for deploying multi-regional resources"
  type        = string
  default     = "us-central"
  
  validation {
    condition = contains([
      "us-central", "us-east", "us-west",
      "europe-north", "europe-west", "europe-central",
      "asia-east", "asia-northeast", "asia-southeast"
    ], var.location)
    error_message = "Location must be a valid Google Cloud location."
  }
}

# ==========================================
# Resource Naming Variables
# ==========================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = length(var.environment) <= 10 && can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must be lowercase alphanumeric with hyphens, max 10 characters."
  }
}

variable "application_name" {
  description = "Name of the application for resource naming"
  type        = string
  default     = "dynamic-content"
  
  validation {
    condition     = length(var.application_name) <= 20 && can(regex("^[a-z0-9-]+$", var.application_name))
    error_message = "Application name must be lowercase alphanumeric with hyphens, max 20 characters."
  }
}

variable "random_suffix" {
  description = "Random suffix for globally unique resource names (leave empty to auto-generate)"
  type        = string
  default     = ""
  
  validation {
    condition     = length(var.random_suffix) <= 8
    error_message = "Random suffix must be 8 characters or less."
  }
}

# ==========================================
# Firebase Configuration Variables
# ==========================================

variable "site_id" {
  description = "Firebase hosting site ID (leave empty to auto-generate based on project)"
  type        = string
  default     = ""
  
  validation {
    condition     = length(var.site_id) <= 30
    error_message = "Site ID must be 30 characters or less."
  }
}

variable "enable_firebase_web_app" {
  description = "Whether to create a Firebase web app associated with the hosting site"
  type        = bool
  default     = true
}

variable "web_app_display_name" {
  description = "Display name for the Firebase web app"
  type        = string
  default     = "Dynamic Content Demo"
}

# ==========================================
# Cloud Functions Configuration
# ==========================================

variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "nodejs20"
  
  validation {
    condition = contains([
      "nodejs18", "nodejs20", "python39", "python310", "python311",
      "go119", "go120", "java11", "java17", "dotnet6"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Google Cloud Functions runtime."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "256M"
  
  validation {
    condition = contains([
      "128M", "256M", "512M", "1G", "2G", "4G", "8G"
    ], var.function_memory)
    error_message = "Function memory must be a valid memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
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
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function max instances must be between 1 and 1000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 100
    error_message = "Function min instances must be between 0 and 100."
  }
}

# ==========================================
# Cloud Storage Configuration
# ==========================================

variable "storage_class" {
  description = "Storage class for the media assets bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "storage_location" {
  description = "Location for the Cloud Storage bucket"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-west1",
      "europe-west1", "europe-west4", "asia-east1", "asia-southeast1"
    ], var.storage_location)
    error_message = "Storage location must be a valid Cloud Storage location."
  }
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Enable object versioning for the storage bucket"
  type        = bool
  default     = false
}

variable "lifecycle_age" {
  description = "Age in days after which objects are deleted (0 to disable)"
  type        = number
  default     = 365
  
  validation {
    condition     = var.lifecycle_age >= 0
    error_message = "Lifecycle age must be non-negative."
  }
}

# ==========================================
# CDN Configuration Variables
# ==========================================

variable "enable_cdn" {
  description = "Enable Cloud CDN for the backend bucket"
  type        = bool
  default     = true
}

variable "cdn_cache_mode" {
  description = "Cache mode for Cloud CDN"
  type        = string
  default     = "CACHE_ALL_STATIC"
  
  validation {
    condition = contains([
      "USE_ORIGIN_HEADERS", "FORCE_CACHE_ALL", "CACHE_ALL_STATIC"
    ], var.cdn_cache_mode)
    error_message = "CDN cache mode must be one of: USE_ORIGIN_HEADERS, FORCE_CACHE_ALL, CACHE_ALL_STATIC."
  }
}

variable "cdn_default_ttl" {
  description = "Default TTL for CDN cached content in seconds"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.cdn_default_ttl >= 0 && var.cdn_default_ttl <= 31536000
    error_message = "CDN default TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "cdn_max_ttl" {
  description = "Maximum TTL for CDN cached content in seconds"
  type        = number
  default     = 86400
  
  validation {
    condition     = var.cdn_max_ttl >= 0 && var.cdn_max_ttl <= 31536000
    error_message = "CDN max TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "enable_compression" {
  description = "Enable automatic compression for responses"
  type        = bool
  default     = true
}

# ==========================================
# Security and Access Control
# ==========================================

variable "enable_iap" {
  description = "Enable Identity-Aware Proxy (IAP) for additional security"
  type        = bool
  default     = false
}

variable "cors_origins" {
  description = "List of allowed CORS origins for the storage bucket"
  type        = list(string)
  default     = ["*"]
}

variable "cors_methods" {
  description = "List of allowed CORS methods for the storage bucket"
  type        = list(string)
  default     = ["GET", "HEAD", "PUT", "POST", "DELETE"]
}

variable "cors_max_age_seconds" {
  description = "Maximum age for CORS preflight responses in seconds"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.cors_max_age_seconds >= 0 && var.cors_max_age_seconds <= 86400
    error_message = "CORS max age must be between 0 and 86400 seconds."
  }
}

# ==========================================
# Monitoring and Logging
# ==========================================

variable "enable_logging" {
  description = "Enable access logging for the storage bucket"
  type        = bool
  default     = true
}

variable "log_bucket" {
  description = "Name of the bucket to store access logs (leave empty to auto-create)"
  type        = string
  default     = ""
}

variable "enable_monitoring" {
  description = "Enable advanced monitoring for Cloud Functions"
  type        = bool
  default     = true
}

# ==========================================
# Resource Labels and Tags
# ==========================================

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "dynamic-content-delivery"
    environment = "demo"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}