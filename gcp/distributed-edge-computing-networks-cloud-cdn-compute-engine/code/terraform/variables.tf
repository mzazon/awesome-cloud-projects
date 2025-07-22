# Variable Definitions for Distributed Edge Computing Network
# This file defines all configurable parameters for the edge computing infrastructure

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "default_region" {
  description = "Default region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.default_region)
    error_message = "Default region must be a valid Google Cloud region."
  }
}

variable "regions" {
  description = "List of regions for distributed edge compute clusters"
  type        = list(string)
  default     = ["us-central1", "europe-west1", "asia-southeast1"]
  validation {
    condition     = length(var.regions) >= 2 && length(var.regions) <= 5
    error_message = "Must specify between 2 and 5 regions for edge deployment."
  }
}

variable "zones" {
  description = "Map of regions to their primary zones for compute deployment"
  type        = map(string)
  default = {
    "us-central1"     = "us-central1-a"
    "europe-west1"    = "europe-west1-b"
    "asia-southeast1" = "asia-southeast1-a"
    "us-east1"        = "us-east1-b"
    "us-west1"        = "us-west1-a"
  }
}

variable "network_name" {
  description = "Name for the global VPC network"
  type        = string
  default     = "edge-network"
  validation {
    condition     = can(regex("^[a-z](?:[-a-z0-9]{0,61}[a-z0-9])?$", var.network_name))
    error_message = "Network name must be a valid Google Cloud resource name."
  }
}

variable "domain_name" {
  description = "Domain name for the edge computing service (optional, for DNS configuration)"
  type        = string
  default     = "edge-example.com"
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.[a-z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid DNS domain name."
  }
}

variable "machine_type" {
  description = "Machine type for Compute Engine instances in edge clusters"
  type        = string
  default     = "e2-standard-2"
  validation {
    condition = contains([
      "e2-standard-2", "e2-standard-4", "n2-standard-2", "n2-standard-4",
      "c2-standard-4", "c2-standard-8", "n1-standard-2", "n1-standard-4"
    ], var.machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "min_replicas" {
  description = "Minimum number of instances per regional cluster"
  type        = number
  default     = 2
  validation {
    condition     = var.min_replicas >= 1 && var.min_replicas <= 10
    error_message = "Minimum replicas must be between 1 and 10."
  }
}

variable "max_replicas" {
  description = "Maximum number of instances per regional cluster"
  type        = number
  default     = 5
  validation {
    condition     = var.max_replicas >= 2 && var.max_replicas <= 20
    error_message = "Maximum replicas must be between 2 and 20."
  }
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization for autoscaling (as a decimal, e.g., 0.7 for 70%)"
  type        = number
  default     = 0.7
  validation {
    condition     = var.target_cpu_utilization > 0 && var.target_cpu_utilization <= 1
    error_message = "Target CPU utilization must be between 0 and 1."
  }
}

variable "cdn_cache_mode" {
  description = "CDN cache mode for the backend service"
  type        = string
  default     = "CACHE_ALL_STATIC"
  validation {
    condition = contains([
      "USE_ORIGIN_HEADERS", "FORCE_CACHE_ALL", "CACHE_ALL_STATIC"
    ], var.cdn_cache_mode)
    error_message = "CDN cache mode must be a valid Google Cloud CDN cache mode."
  }
}

variable "cdn_default_ttl" {
  description = "Default TTL in seconds for CDN cache"
  type        = number
  default     = 3600
  validation {
    condition     = var.cdn_default_ttl >= 0 && var.cdn_default_ttl <= 86400
    error_message = "CDN default TTL must be between 0 and 86400 seconds (24 hours)."
  }
}

variable "cdn_max_ttl" {
  description = "Maximum TTL in seconds for CDN cache"
  type        = number
  default     = 86400
  validation {
    condition     = var.cdn_max_ttl >= 0 && var.cdn_max_ttl <= 31536000
    error_message = "CDN max TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "cdn_client_ttl" {
  description = "Client TTL in seconds for CDN cache"
  type        = number
  default     = 1800
  validation {
    condition     = var.cdn_client_ttl >= 0 && var.cdn_client_ttl <= 86400
    error_message = "CDN client TTL must be between 0 and 86400 seconds (24 hours)."
  }
}

variable "enable_dns" {
  description = "Whether to create Cloud DNS zone and records"
  type        = bool
  default     = true
}

variable "enable_storage_origins" {
  description = "Whether to create Cloud Storage buckets as content origins"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE", "REGIONAL", "MULTI_REGIONAL"
    ], var.storage_class)
    error_message = "Storage class must be a valid Google Cloud Storage class."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    project     = "edge-computing"
    managed-by  = "terraform"
  }
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Cannot specify more than 64 labels."
  }
}

variable "health_check_path" {
  description = "Path for health check requests"
  type        = string
  default     = "/"
  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "Health check path must start with '/'."
  }
}

variable "health_check_port" {
  description = "Port for health check requests"
  type        = number
  default     = 80
  validation {
    condition     = var.health_check_port > 0 && var.health_check_port <= 65535
    error_message = "Health check port must be between 1 and 65535."
  }
}

variable "enable_logging" {
  description = "Whether to enable access logging for the load balancer"
  type        = bool
  default     = false
}

variable "log_config_sample_rate" {
  description = "Sample rate for access logs (0.0 to 1.0)"
  type        = number
  default     = 1.0
  validation {
    condition     = var.log_config_sample_rate >= 0.0 && var.log_config_sample_rate <= 1.0
    error_message = "Log sample rate must be between 0.0 and 1.0."
  }
}