# Input Variables for GCP Edge Caching Performance Recipe
# This file defines all configurable parameters for the infrastructure

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must be a valid GCP project identifier."
  }
}

variable "region" {
  description = "The GCP region where resources will be created"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone where resources will be created"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone identifier."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "intelligent-cdn"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

# Network Configuration Variables
variable "network_cidr" {
  description = "CIDR block for the VPC network"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "Network CIDR must be a valid IPv4 CIDR block."
  }
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.0.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block."
  }
}

# Redis Configuration Variables
variable "redis_memory_size_gb" {
  description = "Memory size in GB for the Redis instance"
  type        = number
  default     = 5
  validation {
    condition     = var.redis_memory_size_gb >= 1 && var.redis_memory_size_gb <= 300
    error_message = "Redis memory size must be between 1 and 300 GB."
  }
}

variable "redis_version" {
  description = "Redis version to use"
  type        = string
  default     = "REDIS_6_X"
  validation {
    condition = contains([
      "REDIS_6_X", "REDIS_7_X"
    ], var.redis_version)
    error_message = "Redis version must be either REDIS_6_X or REDIS_7_X."
  }
}

variable "redis_tier" {
  description = "Redis service tier (STANDARD_HA for high availability)"
  type        = string
  default     = "STANDARD_HA"
  validation {
    condition = contains([
      "BASIC", "STANDARD_HA"
    ], var.redis_tier)
    error_message = "Redis tier must be either BASIC or STANDARD_HA."
  }
}

variable "redis_auth_enabled" {
  description = "Enable Redis AUTH for security"
  type        = bool
  default     = true
}

variable "redis_transit_encryption_mode" {
  description = "Transit encryption mode for Redis"
  type        = string
  default     = "SERVER_AUTHENTICATION"
  validation {
    condition = contains([
      "DISABLED", "SERVER_AUTHENTICATION"
    ], var.redis_transit_encryption_mode)
    error_message = "Transit encryption mode must be either DISABLED or SERVER_AUTHENTICATION."
  }
}

# CDN Configuration Variables
variable "cdn_cache_mode" {
  description = "Cache mode for Cloud CDN"
  type        = string
  default     = "CACHE_ALL_STATIC"
  validation {
    condition = contains([
      "CACHE_ALL_STATIC", "USE_ORIGIN_HEADERS", "FORCE_CACHE_ALL"
    ], var.cdn_cache_mode)
    error_message = "CDN cache mode must be CACHE_ALL_STATIC, USE_ORIGIN_HEADERS, or FORCE_CACHE_ALL."
  }
}

variable "cdn_default_ttl" {
  description = "Default TTL for cached content in seconds"
  type        = number
  default     = 3600
  validation {
    condition     = var.cdn_default_ttl >= 0 && var.cdn_default_ttl <= 31536000
    error_message = "CDN default TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "cdn_max_ttl" {
  description = "Maximum TTL for cached content in seconds"
  type        = number
  default     = 86400
  validation {
    condition     = var.cdn_max_ttl >= 0 && var.cdn_max_ttl <= 31536000
    error_message = "CDN max TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "cdn_client_ttl" {
  description = "Client TTL for cached content in seconds"
  type        = number
  default     = 3600
  validation {
    condition     = var.cdn_client_ttl >= 0 && var.cdn_client_ttl <= 31536000
    error_message = "CDN client TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

# Cloud Storage Configuration Variables
variable "storage_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.storage_location)
    error_message = "Storage location must be a valid GCP location."
  }
}

variable "storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for Cloud Storage bucket"
  type        = bool
  default     = true
}

# Load Balancer Configuration Variables
variable "health_check_path" {
  description = "Path for health check endpoint"
  type        = string
  default     = "/"
  validation {
    condition     = can(regex("^/.*", var.health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

variable "health_check_port" {
  description = "Port for health check"
  type        = number
  default     = 80
  validation {
    condition     = var.health_check_port >= 1 && var.health_check_port <= 65535
    error_message = "Health check port must be between 1 and 65535."
  }
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
  validation {
    condition     = var.health_check_interval >= 1 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 1 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 10
  validation {
    condition     = var.health_check_timeout >= 1 && var.health_check_timeout <= 60
    error_message = "Health check timeout must be between 1 and 60 seconds."
  }
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive successful health checks before marking healthy"
  type        = number
  default     = 2
  validation {
    condition     = var.health_check_healthy_threshold >= 1 && var.health_check_healthy_threshold <= 10
    error_message = "Health check healthy threshold must be between 1 and 10."
  }
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive failed health checks before marking unhealthy"
  type        = number
  default     = 3
  validation {
    condition     = var.health_check_unhealthy_threshold >= 1 && var.health_check_unhealthy_threshold <= 10
    error_message = "Health check unhealthy threshold must be between 1 and 10."
  }
}

# SSL Configuration Variables
variable "enable_ssl" {
  description = "Enable SSL/TLS for the load balancer"
  type        = bool
  default     = false
}

variable "ssl_certificate_domains" {
  description = "Domains for SSL certificate (if enable_ssl is true)"
  type        = list(string)
  default     = []
  validation {
    condition = length(var.ssl_certificate_domains) == 0 || alltrue([
      for domain in var.ssl_certificate_domains : can(regex("^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", domain))
    ])
    error_message = "All SSL certificate domains must be valid domain names."
  }
}

# Monitoring Configuration Variables
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

# Tagging Variables
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "production"
    project     = "edge-caching-performance"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k))
    ])
    error_message = "Label keys must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# API Services Configuration
variable "enable_required_apis" {
  description = "Enable required Google Cloud APIs"
  type        = bool
  default     = true
}