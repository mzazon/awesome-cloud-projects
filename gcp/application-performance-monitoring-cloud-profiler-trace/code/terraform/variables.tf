# Variables for Application Performance Monitoring with Cloud Profiler and Cloud Trace

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be between 6 and 30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region where resources will be created"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1, europe-west1)."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "application_name" {
  description = "Name of the application for resource naming"
  type        = string
  default     = "performance-monitoring"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.application_name))
    error_message = "Application name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "service_account_name" {
  description = "Name for the service account used by Cloud Run services"
  type        = string
  default     = "profiler-trace-sa"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_account_name))
    error_message = "Service account name must be between 6 and 30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cloud_run_services" {
  description = "Configuration for Cloud Run services"
  type = map(object({
    cpu_limit      = string
    memory_limit   = string
    max_instances  = number
    min_instances  = number
    port           = number
    timeout        = number
    env_vars       = map(string)
  }))
  default = {
    frontend = {
      cpu_limit     = "1000m"
      memory_limit  = "1Gi"
      max_instances = 10
      min_instances = 0
      port          = 8080
      timeout       = 300
      env_vars      = {}
    }
    api-gateway = {
      cpu_limit     = "1000m"
      memory_limit  = "1Gi"
      max_instances = 10
      min_instances = 0
      port          = 8081
      timeout       = 300
      env_vars      = {}
    }
    auth-service = {
      cpu_limit     = "1000m"
      memory_limit  = "1Gi"
      max_instances = 10
      min_instances = 0
      port          = 8082
      timeout       = 300
      env_vars      = {}
    }
    data-service = {
      cpu_limit     = "1000m"
      memory_limit  = "1Gi"
      max_instances = 10
      min_instances = 0
      port          = 8083
      timeout       = 300
      env_vars      = {}
    }
  }
}

variable "monitoring_dashboard_enabled" {
  description = "Whether to create a Cloud Monitoring dashboard"
  type        = bool
  default     = true
}

variable "alert_policies_enabled" {
  description = "Whether to create alert policies for performance monitoring"
  type        = bool
  default     = true
}

variable "high_latency_threshold" {
  description = "High latency threshold in seconds for alerting"
  type        = number
  default     = 2.0
  
  validation {
    condition     = var.high_latency_threshold > 0
    error_message = "High latency threshold must be greater than 0."
  }
}

variable "notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "performance-monitoring"
    environment = "dev"
    component   = "observability"
  }
}

variable "artifact_registry_location" {
  description = "Location for Artifact Registry repository"
  type        = string
  default     = "us-central1"
}

variable "artifact_registry_format" {
  description = "Format for Artifact Registry repository"
  type        = string
  default     = "DOCKER"
  
  validation {
    condition     = contains(["DOCKER", "MAVEN", "NPM", "PYTHON", "APT", "YUM"], var.artifact_registry_format)
    error_message = "Artifact Registry format must be one of: DOCKER, MAVEN, NPM, PYTHON, APT, YUM."
  }
}

variable "cloud_profiler_enabled" {
  description = "Whether to enable Cloud Profiler for the services"
  type        = bool
  default     = true
}

variable "cloud_trace_enabled" {
  description = "Whether to enable Cloud Trace for the services"
  type        = bool
  default     = true
}

variable "cloud_trace_sample_rate" {
  description = "Sampling rate for Cloud Trace (0.0 to 1.0)"
  type        = number
  default     = 1.0
  
  validation {
    condition     = var.cloud_trace_sample_rate >= 0.0 && var.cloud_trace_sample_rate <= 1.0
    error_message = "Cloud Trace sample rate must be between 0.0 and 1.0."
  }
}

variable "cloud_run_allow_unauthenticated" {
  description = "Whether to allow unauthenticated access to Cloud Run services"
  type        = bool
  default     = true
}

variable "delete_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}