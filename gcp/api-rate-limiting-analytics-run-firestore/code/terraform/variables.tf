# Variable definitions for GCP API Rate Limiting and Analytics infrastructure
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0 && can(regex("^[a-z][-a-z0-9]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must be a valid GCP project identifier."
  }
}

variable "region" {
  description = "The GCP region for deploying resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
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

variable "service_name" {
  description = "Name of the Cloud Run service for the API gateway"
  type        = string
  default     = "api-rate-limiter"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.service_name))
    error_message = "Service name must be lowercase letters, numbers, and hyphens only."
  }
}

variable "container_image" {
  description = "Container image for the API gateway (will be built and pushed during deployment)"
  type        = string
  default     = ""
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

# Cloud Run Configuration Variables
variable "cloud_run_config" {
  description = "Configuration for Cloud Run service"
  type = object({
    cpu_limit         = string
    memory_limit      = string
    max_instances     = number
    min_instances     = number
    concurrency       = number
    timeout_seconds   = number
    allow_unauthenticated = bool
  })
  default = {
    cpu_limit         = "1"
    memory_limit      = "1Gi"
    max_instances     = 10
    min_instances     = 0
    concurrency       = 100
    timeout_seconds   = 300
    allow_unauthenticated = true
  }
  
  validation {
    condition     = var.cloud_run_config.max_instances >= var.cloud_run_config.min_instances
    error_message = "Max instances must be greater than or equal to min instances."
  }
  
  validation {
    condition     = var.cloud_run_config.concurrency > 0 && var.cloud_run_config.concurrency <= 1000
    error_message = "Concurrency must be between 1 and 1000."
  }
}

# Firestore Configuration Variables
variable "firestore_config" {
  description = "Configuration for Firestore database"
  type = object({
    location_id                 = string
    type                       = string
    concurrency_mode           = string
    app_engine_integration_mode = string
    point_in_time_recovery_enablement = string
    delete_protection_state    = string
  })
  default = {
    location_id                 = "us-central"
    type                       = "FIRESTORE_NATIVE"
    concurrency_mode           = "OPTIMISTIC"
    app_engine_integration_mode = "DISABLED"
    point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_DISABLED"
    delete_protection_state    = "DELETE_PROTECTION_DISABLED"
  }
}

# Monitoring Configuration Variables
variable "monitoring_config" {
  description = "Configuration for Cloud Monitoring and alerting"
  type = object({
    enable_dashboard     = bool
    enable_alerts       = bool
    alert_email         = string
    log_retention_days  = number
  })
  default = {
    enable_dashboard    = true
    enable_alerts      = true
    alert_email        = ""
    log_retention_days = 30
  }
}

# Rate Limiting Configuration
variable "rate_limiting_config" {
  description = "Default rate limiting configuration"
  type = object({
    default_requests_per_hour = number
    rate_window_seconds      = number
    burst_capacity          = number
  })
  default = {
    default_requests_per_hour = 100
    rate_window_seconds      = 3600
    burst_capacity          = 10
  }
  
  validation {
    condition     = var.rate_limiting_config.default_requests_per_hour > 0
    error_message = "Default requests per hour must be greater than 0."
  }
}

# Security Configuration
variable "security_config" {
  description = "Security configuration options"
  type = object({
    enable_binary_authorization = bool
    enable_vpc_connector       = bool
    enable_private_ip          = bool
    allowed_ingress           = string
  })
  default = {
    enable_binary_authorization = false
    enable_vpc_connector       = false
    enable_private_ip          = false
    allowed_ingress           = "all"
  }
  
  validation {
    condition     = contains(["all", "internal", "internal-and-cloud-load-balancing"], var.security_config.allowed_ingress)
    error_message = "Allowed ingress must be one of: all, internal, internal-and-cloud-load-balancing."
  }
}

# Resource Tagging
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "component"  = "api-gateway"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}