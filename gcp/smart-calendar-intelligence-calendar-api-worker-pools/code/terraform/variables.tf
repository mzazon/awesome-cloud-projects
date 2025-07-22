# Variables for smart calendar intelligence infrastructure

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
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

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
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

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "calendar-ai"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

# Calendar Intelligence Worker Pool Configuration
variable "worker_pool_config" {
  description = "Configuration for the Cloud Run Worker Pool"
  type = object({
    name                    = optional(string, "calendar-intelligence-worker")
    cpu_limit              = optional(string, "2")
    memory_limit           = optional(string, "2Gi")
    min_instance_count     = optional(number, 0)
    max_instance_count     = optional(number, 10)
    container_image        = optional(string, "us-docker.pkg.dev/cloudrun/container/worker-pool")
    service_account_email  = optional(string, null)
  })
  default = {}
}

# API Service Configuration
variable "api_service_config" {
  description = "Configuration for the Cloud Run API Service"
  type = object({
    name              = optional(string, "calendar-intelligence-api")
    cpu_limit         = optional(string, "1")
    memory_limit      = optional(string, "1Gi")
    min_instance_count = optional(number, 0)
    max_instance_count = optional(number, 5)
    container_image   = optional(string, "us-docker.pkg.dev/cloudrun/container/hello")
  })
  default = {}
}

# Cloud Tasks Configuration
variable "task_queue_config" {
  description = "Configuration for Cloud Tasks queue"
  type = object({
    name                        = optional(string, "calendar-tasks")
    max_concurrent_dispatches   = optional(number, 10)
    max_dispatches_per_second   = optional(number, 5)
    max_retry_duration         = optional(string, "3600s")
    max_attempts               = optional(number, 3)
  })
  default = {}
}

# BigQuery Configuration
variable "bigquery_config" {
  description = "Configuration for BigQuery analytics dataset"
  type = object({
    dataset_id                   = optional(string, "calendar_analytics")
    description                  = optional(string, "Calendar intelligence analytics dataset")
    delete_contents_on_destroy   = optional(bool, true)
    default_table_expiration_ms  = optional(number, null)
  })
  default = {}
}

# Cloud Storage Configuration
variable "storage_config" {
  description = "Configuration for Cloud Storage bucket"
  type = object({
    bucket_name             = optional(string, null) # Will be auto-generated if null
    location               = optional(string, "US")
    storage_class          = optional(string, "STANDARD")
    versioning_enabled     = optional(bool, true)
    lifecycle_rules        = optional(list(object({
      action = object({
        type = string
      })
      condition = object({
        age = number
      })
    })), [])
  })
  default = {}
}

# IAM Configuration
variable "iam_config" {
  description = "IAM configuration options"
  type = object({
    create_service_accounts = optional(bool, true)
    custom_roles           = optional(bool, false)
  })
  default = {}
}

# Networking Configuration
variable "network_config" {
  description = "Networking configuration for VPC access"
  type = object({
    vpc_connector_name     = optional(string, null)
    vpc_network           = optional(string, "default")
    vpc_subnetwork        = optional(string, "default")
    enable_direct_vpc     = optional(bool, false)
  })
  default = {}
}

# Monitoring and Alerting Configuration
variable "monitoring_config" {
  description = "Monitoring and alerting configuration"
  type = object({
    enable_monitoring       = optional(bool, true)
    enable_cloud_trace     = optional(bool, true)
    enable_cloud_profiler  = optional(bool, true)
    log_level              = optional(string, "INFO")
  })
  default = {}
}

# Calendar API Configuration
variable "calendar_api_config" {
  description = "Google Calendar API configuration"
  type = object({
    enable_calendar_api     = optional(bool, true)
    enable_gmail_api       = optional(bool, true)
    domain_wide_delegation = optional(bool, false)
    calendar_scopes        = optional(list(string), ["https://www.googleapis.com/auth/calendar.readonly"])
  })
  default = {}
}

# Vertex AI Configuration
variable "vertex_ai_config" {
  description = "Vertex AI configuration for calendar intelligence"
  type = object({
    enable_vertex_ai       = optional(bool, true)
    model_name            = optional(string, "gemini-1.5-flash")
    model_location        = optional(string, "us-central1")
    enable_custom_training = optional(bool, false)
  })
  default = {}
}

# Scheduling Configuration
variable "scheduler_config" {
  description = "Cloud Scheduler configuration for automated analysis"
  type = object({
    schedule_expression     = optional(string, "0 9 * * *") # Daily at 9 AM
    time_zone              = optional(string, "UTC")
    description            = optional(string, "Daily calendar intelligence analysis trigger")
    enable_scheduler       = optional(bool, true)
  })
  default = {}
}

# Security Configuration
variable "security_config" {
  description = "Security configuration options"
  type = object({
    enable_binary_authorization = optional(bool, false)
    enable_secret_manager      = optional(bool, true)
    enable_cmek_encryption     = optional(bool, false)
    kms_key_id                = optional(string, null)
  })
  default = {}
}

# Resource Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "calendar-intelligence"
    component   = "ai-analytics"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Random suffix for resource uniqueness
variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 8
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 16
    error_message = "Random suffix length must be between 4 and 16 characters."
  }
}