# Variables for scalable audio content distribution infrastructure
# These variables allow customization of the audio generation and distribution platform

variable "project_id" {
  description = "Google Cloud Project ID for deploying the audio distribution platform"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for deploying regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Memorystore."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod) for resource naming and tagging"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness and organization"
  type        = string
  default     = "audio-dist"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

# Networking Configuration
variable "network_cidr" {
  description = "CIDR block for the VPC network"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "Network CIDR must be a valid IPv4 CIDR block."
  }
}

variable "memorystore_subnet_cidr" {
  description = "CIDR block for the Memorystore subnet (minimum /29 required)"
  type        = string
  default     = "10.0.1.0/29"
  validation {
    condition     = can(cidrhost(var.memorystore_subnet_cidr, 0))
    error_message = "Memorystore subnet CIDR must be a valid IPv4 CIDR block."
  }
}

# Memorystore Configuration
variable "valkey_instance_memory_size_gb" {
  description = "Memory size in GB for the Valkey instance (minimum 1GB, maximum 300GB)"
  type        = number
  default     = 2
  validation {
    condition     = var.valkey_instance_memory_size_gb >= 1 && var.valkey_instance_memory_size_gb <= 300
    error_message = "Valkey instance memory size must be between 1 and 300 GB."
  }
}

variable "valkey_shard_count" {
  description = "Number of shards for the Valkey instance"
  type        = number
  default     = 1
  validation {
    condition     = var.valkey_shard_count >= 1 && var.valkey_shard_count <= 15
    error_message = "Valkey shard count must be between 1 and 15."
  }
}

variable "valkey_replica_count" {
  description = "Number of replica nodes per shard"
  type        = number
  default     = 1
  validation {
    condition     = var.valkey_replica_count >= 0 && var.valkey_replica_count <= 5
    error_message = "Valkey replica count must be between 0 and 5."
  }
}

variable "valkey_node_type" {
  description = "Machine type for Valkey instance nodes"
  type        = string
  default     = "SHARED_CORE_NANO"
  validation {
    condition = contains([
      "SHARED_CORE_NANO", "HIGHMEM_MEDIUM", "HIGHMEM_XLARGE", "STANDARD_SMALL"
    ], var.valkey_node_type)
    error_message = "Valkey node type must be one of: SHARED_CORE_NANO, HIGHMEM_MEDIUM, HIGHMEM_XLARGE, STANDARD_SMALL."
  }
}

variable "enable_valkey_auth" {
  description = "Enable authentication for the Valkey instance"
  type        = bool
  default     = true
}

variable "enable_valkey_encryption" {
  description = "Enable transit encryption for the Valkey instance"
  type        = bool
  default     = true
}

# Storage Configuration
variable "storage_class" {
  description = "Storage class for the audio content bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_location" {
  description = "Location for the Cloud Storage bucket (can be region or multi-region)"
  type        = string
  default     = "US"
  validation {
    condition     = length(var.bucket_location) > 0
    error_message = "Bucket location must not be empty."
  }
}

# Cloud Functions Configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 512
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
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
  description = "Maximum number of concurrent function instances"
  type        = number
  default     = 100
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Function max instances must be between 1 and 3000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Function min instances must be between 0 and 1000."
  }
}

# Cloud Run Configuration
variable "cloudrun_memory" {
  description = "Memory allocation for Cloud Run services"
  type        = string
  default     = "512Mi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.cloudrun_memory)
    error_message = "Cloud Run memory must be one of: 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
  }
}

variable "cloudrun_cpu" {
  description = "CPU allocation for Cloud Run services"
  type        = string
  default     = "1"
  validation {
    condition = contains([
      "0.08", "0.17", "0.25", "0.5", "1", "2", "4", "6", "8"
    ], var.cloudrun_cpu)
    error_message = "Cloud Run CPU must be one of: 0.08, 0.17, 0.25, 0.5, 1, 2, 4, 6, 8."
  }
}

variable "cloudrun_min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 0
  validation {
    condition     = var.cloudrun_min_instances >= 0 && var.cloudrun_min_instances <= 1000
    error_message = "Cloud Run min instances must be between 0 and 1000."
  }
}

variable "cloudrun_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 100
  validation {
    condition     = var.cloudrun_max_instances >= 1 && var.cloudrun_max_instances <= 3000
    error_message = "Cloud Run max instances must be between 1 and 3000."
  }
}

# CDN Configuration
variable "cdn_cache_mode" {
  description = "Cache mode for Cloud CDN"
  type        = string
  default     = "CACHE_ALL_STATIC"
  validation {
    condition = contains([
      "CACHE_ALL_STATIC", "USE_ORIGIN_HEADERS", "FORCE_CACHE_ALL"
    ], var.cdn_cache_mode)
    error_message = "CDN cache mode must be one of: CACHE_ALL_STATIC, USE_ORIGIN_HEADERS, FORCE_CACHE_ALL."
  }
}

variable "cdn_default_ttl" {
  description = "Default TTL for CDN cache in seconds"
  type        = number
  default     = 3600
  validation {
    condition     = var.cdn_default_ttl >= 0 && var.cdn_default_ttl <= 31536000
    error_message = "CDN default TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "cdn_max_ttl" {
  description = "Maximum TTL for CDN cache in seconds"
  type        = number
  default     = 86400
  validation {
    condition     = var.cdn_max_ttl >= 0 && var.cdn_max_ttl <= 31536000
    error_message = "CDN max TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "cdn_client_ttl" {
  description = "Client TTL for CDN cache in seconds"
  type        = number
  default     = 1800
  validation {
    condition     = var.cdn_client_ttl >= 0 && var.cdn_client_ttl <= 86400
    error_message = "CDN client TTL must be between 0 and 86400 seconds (1 day)."
  }
}

# Security Configuration
variable "enable_apis" {
  description = "List of Google Cloud APIs to enable for the project"
  type        = list(string)
  default = [
    "texttospeech.googleapis.com",
    "memcache.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudcdn.googleapis.com",
    "compute.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com"
  ]
}

variable "cors_origins" {
  description = "CORS origins for the storage bucket"
  type        = list(string)
  default     = ["*"]
}

variable "cors_methods" {
  description = "CORS methods for the storage bucket"
  type        = list(string)
  default     = ["GET", "HEAD", "OPTIONS"]
}

variable "cors_response_headers" {
  description = "CORS response headers for the storage bucket"
  type        = list(string)
  default     = ["Content-Type", "Range", "Cache-Control"]
}

variable "cors_max_age_seconds" {
  description = "CORS max age in seconds for the storage bucket"
  type        = number
  default     = 3600
  validation {
    condition     = var.cors_max_age_seconds >= 0 && var.cors_max_age_seconds <= 604800
    error_message = "CORS max age must be between 0 and 604800 seconds (1 week)."
  }
}

# Text-to-Speech Configuration
variable "tts_voice_config" {
  description = "Default Text-to-Speech voice configuration"
  type = object({
    language_code = string
    voice_name    = string
    ssml_gender   = string
  })
  default = {
    language_code = "en-US"
    voice_name    = "en-US-Casual"
    ssml_gender   = "NEUTRAL"
  }
}

variable "tts_audio_config" {
  description = "Default Text-to-Speech audio configuration"
  type = object({
    audio_encoding    = string
    sample_rate_hertz = number
    effects_profile   = list(string)
  })
  default = {
    audio_encoding    = "MP3"
    sample_rate_hertz = 24000
    effects_profile   = ["headphone-class-device"]
  }
}

# Monitoring and Logging
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for the infrastructure"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Cloud Logging for the infrastructure"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653 days (10 years)."
  }
}

# Resource Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "audio-distribution"
    managed-by  = "terraform"
    environment = "dev"
  }
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Cannot have more than 64 labels."
  }
}