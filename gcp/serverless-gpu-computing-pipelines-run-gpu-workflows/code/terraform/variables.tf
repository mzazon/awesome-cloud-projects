# Core Project Configuration
variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for resources (GPU regions: us-central1, europe-west1, europe-west4, asia-southeast1, asia-south1)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "europe-west1", "europe-west4", 
      "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must support Cloud Run GPU. Valid options: us-central1, europe-west1, europe-west4, asia-southeast1, asia-south1."
  }
}

variable "zone" {
  description = "Google Cloud zone within the region"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming Configuration
variable "service_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "ml-pipeline"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.service_prefix))
    error_message = "Service prefix must be 3-21 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
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

# Cloud Run GPU Configuration
variable "gpu_service_config" {
  description = "Configuration for GPU-accelerated inference service"
  type = object({
    memory_gb    = number
    cpu_count    = number
    gpu_count    = number
    gpu_type     = string
    timeout_seconds = number
    concurrency  = number
    max_instances = number
  })
  default = {
    memory_gb       = 16
    cpu_count       = 4
    gpu_count       = 1
    gpu_type        = "nvidia-l4"
    timeout_seconds = 300
    concurrency     = 4
    max_instances   = 10
  }
  validation {
    condition     = var.gpu_service_config.gpu_type == "nvidia-l4"
    error_message = "Currently only nvidia-l4 GPU type is supported for Cloud Run GPU."
  }
}

# Cloud Run CPU Services Configuration
variable "cpu_service_config" {
  description = "Configuration for CPU-based preprocessing and postprocessing services"
  type = object({
    preprocess_memory_gb = number
    preprocess_cpu_count = number
    postprocess_memory_gb = number
    postprocess_cpu_count = number
    timeout_seconds      = number
    max_instances        = number
  })
  default = {
    preprocess_memory_gb  = 2
    preprocess_cpu_count  = 1
    postprocess_memory_gb = 1
    postprocess_cpu_count = 1
    timeout_seconds       = 60
    max_instances         = 50
  }
}

# Storage Configuration
variable "storage_config" {
  description = "Configuration for Cloud Storage buckets"
  type = object({
    location      = string
    storage_class = string
    lifecycle_age = number
  })
  default = {
    location      = "US"
    storage_class = "STANDARD"
    lifecycle_age = 30
  }
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_config.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# Workflow Configuration
variable "workflow_config" {
  description = "Configuration for Cloud Workflows"
  type = object({
    description = string
    call_log_level = string
  })
  default = {
    description    = "Serverless GPU ML Pipeline Orchestration"
    call_log_level = "LOG_ERRORS_ONLY"
  }
  validation {
    condition     = contains(["LOG_ERRORS_ONLY", "LOG_ALL_CALLS", "LOG_NONE"], var.workflow_config.call_log_level)
    error_message = "Call log level must be one of: LOG_ERRORS_ONLY, LOG_ALL_CALLS, LOG_NONE."
  }
}

# Eventarc Configuration
variable "eventarc_config" {
  description = "Configuration for Eventarc triggers"
  type = object({
    event_type = string
    retry_policy = object({
      max_retry_duration = string
      min_backoff_duration = string
      max_backoff_duration = string
    })
  })
  default = {
    event_type = "google.cloud.storage.object.v1.finalized"
    retry_policy = {
      max_retry_duration   = "600s"
      min_backoff_duration = "5s"
      max_backoff_duration = "60s"
    }
  }
}

# Container Registry Configuration
variable "container_registry" {
  description = "Container registry configuration"
  type = object({
    location = string
    format   = string
  })
  default = {
    location = "us-central1"
    format   = "DOCKER"
  }
}

# IAM Configuration
variable "iam_config" {
  description = "IAM configuration for service accounts"
  type = object({
    eventarc_sa_display_name = string
    workflow_sa_display_name = string
  })
  default = {
    eventarc_sa_display_name = "Eventarc Service Account for ML Pipeline"
    workflow_sa_display_name = "Workflow Service Account for ML Pipeline"
  }
}

# Monitoring Configuration
variable "monitoring_config" {
  description = "Configuration for monitoring and logging"
  type = object({
    enable_cloud_monitoring = bool
    log_retention_days     = number
    alert_threshold_cpu    = number
    alert_threshold_memory = number
  })
  default = {
    enable_cloud_monitoring = true
    log_retention_days     = 30
    alert_threshold_cpu    = 80
    alert_threshold_memory = 80
  }
}

# Security Configuration
variable "security_config" {
  description = "Security configuration for the pipeline"
  type = object({
    require_authentication = bool
    cors_allowed_origins   = list(string)
    vpc_connector_name     = string
  })
  default = {
    require_authentication = false
    cors_allowed_origins   = ["*"]
    vpc_connector_name     = ""
  }
}

# Tags and Labels
variable "labels" {
  description = "Labels to be applied to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    project     = "ml-pipeline"
    managed_by  = "terraform"
    cost_center = "ml-ops"
  }
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}