# Variables for Global Web Application Performance with Firebase App Hosting and Cloud CDN
#
# This file defines all configurable parameters for the infrastructure deployment.
# Customize these values to match your specific requirements and environment.

# Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The primary region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The primary zone for resource deployment"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (dev, staging, prod) for resource labeling"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Firebase App Hosting Configuration
variable "app_hosting_backend_id" {
  description = "Unique identifier for the Firebase App Hosting backend"
  type        = string
  default     = "web-app-backend"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.app_hosting_backend_id))
    error_message = "Backend ID must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "github_repository_owner" {
  description = "GitHub repository owner/organization name (required for CI/CD integration)"
  type        = string
  default     = ""
}

variable "github_repository_name" {
  description = "GitHub repository name containing the web application source code"
  type        = string
  default     = ""
}

variable "github_branch" {
  description = "GitHub branch to deploy from"
  type        = string
  default     = "main"
}

variable "app_root_directory" {
  description = "Root directory in the repository containing the web application"
  type        = string
  default     = "/"
}

# Cloud CDN Configuration
variable "enable_cdn" {
  description = "Enable Cloud CDN for global content distribution"
  type        = bool
  default     = true
}

variable "cdn_cache_mode" {
  description = "Cache mode for Cloud CDN (CACHE_ALL_STATIC, USE_ORIGIN_HEADERS, FORCE_CACHE_ALL)"
  type        = string
  default     = "CACHE_ALL_STATIC"
  validation {
    condition     = contains(["CACHE_ALL_STATIC", "USE_ORIGIN_HEADERS", "FORCE_CACHE_ALL"], var.cdn_cache_mode)
    error_message = "CDN cache mode must be one of: CACHE_ALL_STATIC, USE_ORIGIN_HEADERS, FORCE_CACHE_ALL."
  }
}

variable "cdn_default_ttl" {
  description = "Default Time-To-Live for CDN cache in seconds"
  type        = number
  default     = 3600
  validation {
    condition     = var.cdn_default_ttl >= 0 && var.cdn_default_ttl <= 86400
    error_message = "CDN default TTL must be between 0 and 86400 seconds (24 hours)."
  }
}

variable "cdn_max_ttl" {
  description = "Maximum Time-To-Live for CDN cache in seconds"
  type        = number
  default     = 86400
  validation {
    condition     = var.cdn_max_ttl >= 0 && var.cdn_max_ttl <= 31536000
    error_message = "CDN max TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "cdn_client_ttl" {
  description = "Client-side Time-To-Live for CDN cache in seconds"
  type        = number
  default     = 3600
  validation {
    condition     = var.cdn_client_ttl >= 0 && var.cdn_client_ttl <= 86400
    error_message = "CDN client TTL must be between 0 and 86400 seconds (24 hours)."
  }
}

# SSL Certificate Configuration
variable "domain_name" {
  description = "Primary domain name for the web application (leave empty for self-managed SSL)"
  type        = string
  default     = ""
}

variable "additional_domains" {
  description = "Additional domain names for the SSL certificate"
  type        = list(string)
  default     = []
}

variable "ssl_certificate_name" {
  description = "Name for the managed SSL certificate"
  type        = string
  default     = "web-app-ssl-cert"
}

# Cloud Storage Configuration
variable "storage_bucket_name" {
  description = "Name for the Cloud Storage bucket (auto-generated if empty)"
  type        = string
  default     = ""
}

variable "storage_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA",
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.storage_location)
    error_message = "Storage location must be a valid Google Cloud storage location."
  }
}

variable "storage_class" {
  description = "Storage class for the bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# Cloud Functions Configuration
variable "function_memory" {
  description = "Memory allocation for the performance optimization Cloud Function"
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
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "python312"
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312",
      "nodejs18", "nodejs20", "go121", "java17", "java21"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Google Cloud Functions runtime."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "uptime_check_path" {
  description = "URL path for uptime monitoring checks"
  type        = string
  default     = "/"
}

variable "alert_threshold_latency_ms" {
  description = "Latency threshold in milliseconds for triggering alerts"
  type        = number
  default     = 1000
  validation {
    condition     = var.alert_threshold_latency_ms > 0 && var.alert_threshold_latency_ms <= 30000
    error_message = "Alert threshold latency must be between 1 and 30000 milliseconds."
  }
}

variable "alert_threshold_error_rate" {
  description = "Error rate threshold (0.0-1.0) for triggering alerts"
  type        = number
  default     = 0.05
  validation {
    condition     = var.alert_threshold_error_rate >= 0.0 && var.alert_threshold_error_rate <= 1.0
    error_message = "Alert threshold error rate must be between 0.0 and 1.0."
  }
}

# Network Configuration
variable "network_tier" {
  description = "Network tier for global load balancer (PREMIUM or STANDARD)"
  type        = string
  default     = "PREMIUM"
  validation {
    condition     = contains(["PREMIUM", "STANDARD"], var.network_tier)
    error_message = "Network tier must be either PREMIUM or STANDARD."
  }
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "web-app"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "resource_suffix" {
  description = "Suffix for resource names (auto-generated if empty)"
  type        = string
  default     = ""
}

# Service Configuration
variable "enable_apis" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "monitoring.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com"
  ]
}

# Tags and Labels
variable "labels" {
  description = "Additional labels to apply to resources"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Network tags to apply to applicable resources"
  type        = list(string)
  default     = ["web-app", "firebase", "cdn"]
}