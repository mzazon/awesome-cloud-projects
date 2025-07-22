# Input variables for the Immersive XR Content Delivery platform
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for regional resources (e.g., us-central1)"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources (e.g., us-central1-a)"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., us-central1-a)."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "xr-delivery"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Cloud Storage Configuration
variable "storage_class" {
  description = "Storage class for the XR assets bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD",
      "NEARLINE", 
      "COLDLINE",
      "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "bucket_public_access" {
  description = "Enable public read access for static assets"
  type        = bool
  default     = true
}

# Cloud CDN Configuration
variable "cdn_cache_mode" {
  description = "Cache mode for Cloud CDN"
  type        = string
  default     = "CACHE_ALL_STATIC"
  validation {
    condition = contains([
      "CACHE_ALL_STATIC",
      "USE_ORIGIN_HEADERS",
      "FORCE_CACHE_ALL"
    ], var.cdn_cache_mode)
    error_message = "CDN cache mode must be one of: CACHE_ALL_STATIC, USE_ORIGIN_HEADERS, FORCE_CACHE_ALL."
  }
}

variable "cdn_default_ttl" {
  description = "Default TTL for CDN cache in seconds"
  type        = number
  default     = 3600
  validation {
    condition     = var.cdn_default_ttl >= 0 && var.cdn_default_ttl <= 86400
    error_message = "CDN default TTL must be between 0 and 86400 seconds."
  }
}

variable "cdn_max_ttl" {
  description = "Maximum TTL for CDN cache in seconds"
  type        = number
  default     = 86400
  validation {
    condition     = var.cdn_max_ttl >= 0 && var.cdn_max_ttl <= 31536000
    error_message = "CDN max TTL must be between 0 and 31536000 seconds."
  }
}

# Immersive Stream for XR Configuration
variable "xr_gpu_class" {
  description = "GPU class for XR streaming instances"
  type        = string
  default     = "T4"
  validation {
    condition = contains([
      "T4",
      "V100",
      "A100",
      "K80"
    ], var.xr_gpu_class)
    error_message = "GPU class must be one of: T4, V100, A100, K80."
  }
}

variable "xr_gpu_count" {
  description = "Number of GPUs per XR streaming instance"
  type        = number
  default     = 1
  validation {
    condition     = var.xr_gpu_count >= 1 && var.xr_gpu_count <= 8
    error_message = "GPU count must be between 1 and 8."
  }
}

variable "xr_session_timeout" {
  description = "Session timeout for XR streaming in seconds"
  type        = number
  default     = 1800
  validation {
    condition     = var.xr_session_timeout >= 300 && var.xr_session_timeout <= 7200
    error_message = "Session timeout must be between 300 and 7200 seconds."
  }
}

variable "xr_max_concurrent_sessions" {
  description = "Maximum concurrent XR streaming sessions"
  type        = number
  default     = 10
  validation {
    condition     = var.xr_max_concurrent_sessions >= 1 && var.xr_max_concurrent_sessions <= 100
    error_message = "Max concurrent sessions must be between 1 and 100."
  }
}

# Autoscaling Configuration
variable "enable_autoscaling" {
  description = "Enable autoscaling for XR streaming service"
  type        = bool
  default     = true
}

variable "autoscaling_min_capacity" {
  description = "Minimum capacity for XR autoscaling"
  type        = number
  default     = 1
  validation {
    condition     = var.autoscaling_min_capacity >= 0 && var.autoscaling_min_capacity <= 10
    error_message = "Autoscaling min capacity must be between 0 and 10."
  }
}

variable "autoscaling_max_capacity" {
  description = "Maximum capacity for XR autoscaling"
  type        = number
  default     = 5
  validation {
    condition     = var.autoscaling_max_capacity >= 1 && var.autoscaling_max_capacity <= 50
    error_message = "Autoscaling max capacity must be between 1 and 50."
  }
}

variable "autoscaling_target_utilization" {
  description = "Target utilization percentage for autoscaling"
  type        = number
  default     = 70
  validation {
    condition     = var.autoscaling_target_utilization >= 10 && var.autoscaling_target_utilization <= 90
    error_message = "Target utilization must be between 10 and 90 percent."
  }
}

# Monitoring and Logging Configuration
variable "enable_monitoring" {
  description = "Enable comprehensive monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_access_logs" {
  description = "Enable access logging for load balancer"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention must be between 1 and 365 days."
  }
}

# Security Configuration
variable "enable_ssl" {
  description = "Enable SSL/TLS termination at load balancer"
  type        = bool
  default     = false
}

variable "ssl_certificate_domains" {
  description = "List of domains for SSL certificate"
  type        = list(string)
  default     = []
}

# Resource Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "xr-content-delivery"
    managed-by  = "terraform"
    service     = "immersive-xr"
  }
}

# API Services to Enable
variable "enable_apis" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "storage.googleapis.com",
    "stream.googleapis.com",
    "networkservices.googleapis.com",
    "certificatemanager.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com"
  ]
}