# Variable Definitions for GCP Load Balancer Traffic Routing with Service Extensions

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
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "resource_name_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "intelligent-routing"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_name_prefix))
    error_message = "Resource name prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
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

variable "enable_apis" {
  description = "Enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "cloud_run_services" {
  description = "Configuration for Cloud Run services"
  type = object({
    service_a = object({
      image        = string
      memory       = string
      cpu          = string
      max_instances = number
      env_vars = map(string)
    })
    service_b = object({
      image        = string
      memory       = string
      cpu          = string
      max_instances = number
      env_vars = map(string)
    })
    service_c = object({
      image        = string
      memory       = string
      cpu          = string
      max_instances = number
      env_vars = map(string)
    })
  })
  default = {
    service_a = {
      image         = "gcr.io/cloudrun/hello"
      memory        = "512Mi"
      cpu           = "1000m"
      max_instances = 10
      env_vars = {
        SERVICE_TYPE    = "fast"
        RESPONSE_DELAY  = "100"
      }
    }
    service_b = {
      image         = "gcr.io/cloudrun/hello"
      memory        = "1Gi"
      cpu           = "1000m"
      max_instances = 10
      env_vars = {
        SERVICE_TYPE    = "standard"
        RESPONSE_DELAY  = "500"
      }
    }
    service_c = {
      image         = "gcr.io/cloudrun/hello"
      memory        = "2Gi"
      cpu           = "2000m"
      max_instances = 5
      env_vars = {
        SERVICE_TYPE    = "intensive"
        RESPONSE_DELAY  = "1000"
      }
    }
  }
}

variable "bigquery_dataset_config" {
  description = "Configuration for BigQuery dataset"
  type = object({
    location                    = string
    default_table_expiration_ms = number
    delete_contents_on_destroy  = bool
    description                = string
  })
  default = {
    location                    = "US"
    default_table_expiration_ms = 86400000  # 1 day
    delete_contents_on_destroy  = true
    description                = "Traffic analytics for intelligent routing"
  }
}

variable "service_extensions_config" {
  description = "Configuration for Service Extensions"
  type = object({
    callout_timeout_seconds = number
    failover_behavior      = string
  })
  default = {
    callout_timeout_seconds = 30
    failover_behavior      = "CONTINUE"
  }
}

variable "load_balancer_config" {
  description = "Configuration for Application Load Balancer"
  type = object({
    enable_https               = bool
    ssl_certificate_domains    = list(string)
    health_check_path         = string
    health_check_interval     = number
    health_check_timeout      = number
    health_check_healthy_threshold   = number
    health_check_unhealthy_threshold = number
  })
  default = {
    enable_https               = false
    ssl_certificate_domains    = []
    health_check_path         = "/health"
    health_check_interval     = 30
    health_check_timeout      = 10
    health_check_healthy_threshold   = 2
    health_check_unhealthy_threshold = 3
  }
}

variable "cloud_function_config" {
  description = "Configuration for traffic routing Cloud Function"
  type = object({
    runtime               = string
    memory_mb            = number
    timeout_seconds      = number
    max_instances        = number
    ingress_settings     = string
  })
  default = {
    runtime               = "python39"
    memory_mb            = 256
    timeout_seconds      = 60
    max_instances        = 100
    ingress_settings     = "ALLOW_ALL"
  }
}

variable "workflow_config" {
  description = "Configuration for Cloud Workflows"
  type = object({
    description = string
  })
  default = {
    description = "Analytics processor for intelligent traffic routing"
  }
}

variable "logging_config" {
  description = "Configuration for Cloud Logging"
  type = object({
    retention_days = number
    enable_export  = bool
  })
  default = {
    retention_days = 30
    enable_export  = true
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    terraform   = "true"
    recipe      = "load-balancer-traffic-routing"
    component   = "intelligent-routing"
  }
}