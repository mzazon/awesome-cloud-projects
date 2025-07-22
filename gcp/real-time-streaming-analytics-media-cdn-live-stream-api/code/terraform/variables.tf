# Variables for GCP Real-Time Streaming Analytics Infrastructure
# This file defines all configurable parameters for the streaming analytics solution

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports Live Stream API."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
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

variable "random_suffix" {
  description = "Random suffix for resource names to ensure uniqueness"
  type        = string
  default     = ""
}

# Storage Configuration
variable "storage_class" {
  description = "Default storage class for the video content bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_lifecycle_age_nearline" {
  description = "Number of days after which objects move to NEARLINE storage"
  type        = number
  default     = 30
  validation {
    condition     = var.bucket_lifecycle_age_nearline >= 0
    error_message = "Lifecycle age for NEARLINE must be >= 0."
  }
}

variable "bucket_lifecycle_age_delete" {
  description = "Number of days after which objects are deleted"
  type        = number
  default     = 90
  validation {
    condition     = var.bucket_lifecycle_age_delete > var.bucket_lifecycle_age_nearline
    error_message = "Delete age must be greater than NEARLINE age."
  }
}

# BigQuery Configuration
variable "bigquery_location" {
  description = "Location for BigQuery dataset (multi-region or region)"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "us-central1", "europe-west1", "asia-northeast1"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid multi-region or region."
  }
}

variable "bigquery_table_expiration_days" {
  description = "Default table expiration in days for BigQuery tables"
  type        = number
  default     = 365
  validation {
    condition     = var.bigquery_table_expiration_days > 0
    error_message = "Table expiration must be greater than 0 days."
  }
}

# Cloud Functions Configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python39", "python310", "python311", "nodejs16", "nodejs18", "nodejs20"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "512Mi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout in seconds for Cloud Functions"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 100
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

# Pub/Sub Configuration
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topics (in seconds)"
  type        = string
  default     = "86400s" # 24 hours
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_message_retention_duration))
    error_message = "Message retention duration must be in format like '86400s'."
  }
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscriptions"
  type        = number
  default     = 60
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Ack deadline must be between 10 and 600 seconds."
  }
}

variable "dead_letter_max_delivery_attempts" {
  description = "Maximum delivery attempts before sending to dead letter topic"
  type        = number
  default     = 5
  validation {
    condition     = var.dead_letter_max_delivery_attempts >= 5 && var.dead_letter_max_delivery_attempts <= 100
    error_message = "Max delivery attempts must be between 5 and 100."
  }
}

# CDN Configuration
variable "cdn_cache_mode" {
  description = "Cache mode for CDN (CACHE_ALL_STATIC, USE_ORIGIN_HEADERS, FORCE_CACHE_ALL)"
  type        = string
  default     = "CACHE_ALL_STATIC"
  validation {
    condition = contains([
      "CACHE_ALL_STATIC", "USE_ORIGIN_HEADERS", "FORCE_CACHE_ALL"
    ], var.cdn_cache_mode)
    error_message = "CDN cache mode must be a valid cache mode."
  }
}

variable "cdn_default_ttl" {
  description = "Default TTL for CDN cache (in seconds)"
  type        = number
  default     = 30
  validation {
    condition     = var.cdn_default_ttl >= 0
    error_message = "CDN default TTL must be >= 0."
  }
}

variable "cdn_max_ttl" {
  description = "Maximum TTL for CDN cache (in seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.cdn_max_ttl >= var.cdn_default_ttl
    error_message = "CDN max TTL must be >= default TTL."
  }
}

# Live Streaming Configuration (for reference, as Terraform doesn't support these yet)
variable "livestream_input_type" {
  description = "Type of live stream input (RTMP_PUSH, SRT_PUSH)"
  type        = string
  default     = "RTMP_PUSH"
  validation {
    condition = contains([
      "RTMP_PUSH", "SRT_PUSH"
    ], var.livestream_input_type)
    error_message = "Live stream input type must be RTMP_PUSH or SRT_PUSH."
  }
}

variable "livestream_tier" {
  description = "Live stream processing tier (HD, UHD)"
  type        = string
  default     = "HD"
  validation {
    condition = contains([
      "HD", "UHD"
    ], var.livestream_tier)
    error_message = "Live stream tier must be HD or UHD."
  }
}

# Security Configuration
variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_public_access_prevention" {
  description = "Enable public access prevention for Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_bucket_versioning" {
  description = "Enable versioning for Cloud Storage bucket"
  type        = bool
  default     = true
}

# Monitoring and Logging Configuration
variable "enable_function_vpc_connector" {
  description = "Enable VPC connector for Cloud Functions"
  type        = bool
  default     = false
}

variable "log_level" {
  description = "Log level for application components"
  type        = string
  default     = "INFO"
  validation {
    condition = contains([
      "DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"
    ], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

# Labels and Tags
variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "streaming-analytics"
    terraform   = "true"
    environment = "dev"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z]([a-z0-9_-]{0,61}[a-z0-9])?$", k))
    ])
    error_message = "Label keys must be valid GCP label keys (lowercase, alphanumeric, hyphens, underscores)."
  }
}