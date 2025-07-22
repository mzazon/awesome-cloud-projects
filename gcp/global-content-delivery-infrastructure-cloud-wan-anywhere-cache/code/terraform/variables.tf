# Variable Definitions for Global Content Delivery Infrastructure
# This file defines all configurable parameters for the recipe deployment

# Project and Authentication Configuration
variable "project_id" {
  description = "Google Cloud Project ID for deployment"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

# Regional Configuration
variable "primary_region" {
  description = "Primary region for deployment (Americas)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "us-east4", "us-south1"
    ], var.primary_region)
    error_message = "Primary region must be a valid US region."
  }
}

variable "secondary_region" {
  description = "Secondary region for deployment (EMEA)"
  type        = string
  default     = "europe-west1"
  validation {
    condition = contains([
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "europe-north1", "europe-central2", "europe-west8", "europe-west9"
    ], var.secondary_region)
    error_message = "Secondary region must be a valid Europe region."
  }
}

variable "tertiary_region" {
  description = "Tertiary region for deployment (APAC)"
  type        = string
  default     = "asia-east1"
  validation {
    condition = contains([
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-south2", "asia-southeast1", "asia-southeast2"
    ], var.tertiary_region)
    error_message = "Tertiary region must be a valid Asia region."
  }
}

# Storage Configuration
variable "bucket_storage_class" {
  description = "Storage class for the global content bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "bucket_location" {
  description = "Location for the multi-region storage bucket"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA"
    ], var.bucket_location)
    error_message = "Bucket location must be US, EU, or ASIA for multi-region buckets."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the storage bucket"
  type        = bool
  default     = true
}

variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access"
  type        = bool
  default     = true
}

# Anywhere Cache Configuration
variable "cache_ttl_seconds" {
  description = "Time-to-live for Anywhere Cache instances (seconds)"
  type        = number
  default     = 3600
  validation {
    condition     = var.cache_ttl_seconds >= 300 && var.cache_ttl_seconds <= 86400
    error_message = "Cache TTL must be between 300 (5 minutes) and 86400 (24 hours) seconds."
  }
}

variable "cache_admission_policy" {
  description = "Admission policy for Anywhere Cache instances"
  type        = string
  default     = "admit-on-first-miss"
  validation {
    condition = contains([
      "admit-on-first-miss", "admit-on-second-miss"
    ], var.cache_admission_policy)
    error_message = "Cache admission policy must be 'admit-on-first-miss' or 'admit-on-second-miss'."
  }
}

# Compute Configuration
variable "compute_machine_type" {
  description = "Machine type for content server instances"
  type        = string
  default     = "e2-standard-4"
  validation {
    condition = contains([
      "e2-standard-2", "e2-standard-4", "e2-standard-8", "e2-standard-16",
      "n2-standard-2", "n2-standard-4", "n2-standard-8", "n2-standard-16"
    ], var.compute_machine_type)
    error_message = "Machine type must be a valid e2-standard or n2-standard type."
  }
}

variable "compute_disk_size" {
  description = "Boot disk size for compute instances (GB)"
  type        = number
  default     = 50
  validation {
    condition     = var.compute_disk_size >= 20 && var.compute_disk_size <= 200
    error_message = "Compute disk size must be between 20 and 200 GB."
  }
}

variable "compute_disk_type" {
  description = "Boot disk type for compute instances"
  type        = string
  default     = "pd-standard"
  validation {
    condition = contains([
      "pd-standard", "pd-ssd", "pd-balanced"
    ], var.compute_disk_type)
    error_message = "Disk type must be pd-standard, pd-ssd, or pd-balanced."
  }
}

# Network Configuration
variable "network_name" {
  description = "Name for the VPC network (will be appended with random suffix)"
  type        = string
  default     = "content-delivery-network"
}

variable "auto_create_subnetworks" {
  description = "Automatically create subnetworks in the VPC"
  type        = bool
  default     = true
}

# Load Balancer and CDN Configuration
variable "enable_cdn" {
  description = "Enable Cloud CDN for the backend service"
  type        = bool
  default     = true
}

variable "cdn_cache_mode" {
  description = "CDN cache mode for backend service"
  type        = string
  default     = "CACHE_ALL_STATIC"
  validation {
    condition = contains([
      "USE_ORIGIN_HEADERS", "FORCE_CACHE_ALL", "CACHE_ALL_STATIC"
    ], var.cdn_cache_mode)
    error_message = "CDN cache mode must be USE_ORIGIN_HEADERS, FORCE_CACHE_ALL, or CACHE_ALL_STATIC."
  }
}

variable "cdn_default_ttl" {
  description = "Default TTL for CDN cached content (seconds)"
  type        = number
  default     = 3600
  validation {
    condition     = var.cdn_default_ttl >= 0 && var.cdn_default_ttl <= 86400
    error_message = "CDN default TTL must be between 0 and 86400 seconds."
  }
}

variable "cdn_max_ttl" {
  description = "Maximum TTL for CDN cached content (seconds)"
  type        = number
  default     = 86400
  validation {
    condition     = var.cdn_max_ttl >= 0 && var.cdn_max_ttl <= 2592000
    error_message = "CDN max TTL must be between 0 and 2592000 seconds."
  }
}

variable "cdn_client_ttl" {
  description = "Client TTL for CDN cached content (seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.cdn_client_ttl >= 0 && var.cdn_client_ttl <= 86400
    error_message = "CDN client TTL must be between 0 and 86400 seconds."
  }
}

# Health Check Configuration
variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
  validation {
    condition     = var.health_check_timeout >= 1 && var.health_check_timeout <= 300
    error_message = "Health check timeout must be between 1 and 300 seconds."
  }
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 10
  validation {
    condition     = var.health_check_interval >= 1 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 1 and 300 seconds."
  }
}

# Monitoring and Observability
variable "enable_monitoring" {
  description = "Enable comprehensive monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable access logging for the load balancer"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_public_access" {
  description = "Enable public read access to storage bucket (use carefully)"
  type        = bool
  default     = false
}

variable "allowed_source_ranges" {
  description = "CIDR ranges allowed to access the load balancer"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition = alltrue([
      for range in var.allowed_source_ranges : can(cidrhost(range, 0))
    ])
    error_message = "All source ranges must be valid CIDR blocks."
  }
}

# Labeling and Tagging
variable "environment" {
  description = "Environment label for resources (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  validation {
    condition = contains([
      "dev", "test", "staging", "prod", "demo"
    ], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "owner" {
  description = "Owner label for resources"
  type        = string
  default     = "platform-team"
}

variable "cost_center" {
  description = "Cost center label for billing allocation"
  type        = string
  default     = "engineering"
}

# Advanced Configuration
variable "enable_deletion_protection" {
  description = "Enable deletion protection on critical resources"
  type        = bool
  default     = false
}

variable "force_destroy_bucket" {
  description = "Allow Terraform to destroy bucket even if it contains objects"
  type        = bool
  default     = true
}

variable "create_sample_content" {
  description = "Create sample content files in the storage bucket"
  type        = bool
  default     = true
}