# Variables for Large-Scale AI Model Inference with Ironwood TPU and Cloud Load Balancing
# This file defines all configurable parameters for the Terraform deployment

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west4",
      "asia-east1", "asia-southeast1", "asia-northeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region with TPU availability."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources (TPU pods)"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone cannot be empty."
  }
}

variable "model_name" {
  description = "Name of the AI model to deploy (e.g., llama-70b, palm-2)"
  type        = string
  default     = "llama-70b"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.model_name))
    error_message = "Model name must contain only lowercase letters, numbers, and hyphens."
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

variable "enable_small_tpu" {
  description = "Whether to create the small TPU pod (v7-256)"
  type        = bool
  default     = true
}

variable "enable_medium_tpu" {
  description = "Whether to create the medium TPU pod (v7-1024)"
  type        = bool
  default     = true
}

variable "enable_large_tpu" {
  description = "Whether to create the large TPU pod (v7-9216)"
  type        = bool
  default     = false
}

variable "tpu_version" {
  description = "TPU software version to use"
  type        = string
  default     = "tpu-ubuntu2204-base"
}

variable "min_replicas_small" {
  description = "Minimum number of replicas for small TPU endpoints"
  type        = number
  default     = 1
  
  validation {
    condition     = var.min_replicas_small >= 0 && var.min_replicas_small <= 10
    error_message = "Minimum replicas must be between 0 and 10."
  }
}

variable "max_replicas_small" {
  description = "Maximum number of replicas for small TPU endpoints"
  type        = number
  default     = 3
  
  validation {
    condition     = var.max_replicas_small >= 1 && var.max_replicas_small <= 20
    error_message = "Maximum replicas must be between 1 and 20."
  }
}

variable "min_replicas_medium" {
  description = "Minimum number of replicas for medium TPU endpoints"
  type        = number
  default     = 1
  
  validation {
    condition     = var.min_replicas_medium >= 0 && var.min_replicas_medium <= 10
    error_message = "Minimum replicas must be between 0 and 10."
  }
}

variable "max_replicas_medium" {
  description = "Maximum number of replicas for medium TPU endpoints"
  type        = number
  default     = 5
  
  validation {
    condition     = var.max_replicas_medium >= 1 && var.max_replicas_medium <= 20
    error_message = "Maximum replicas must be between 1 and 20."
  }
}

variable "min_replicas_large" {
  description = "Minimum number of replicas for large TPU endpoints"
  type        = number
  default     = 1
  
  validation {
    condition     = var.min_replicas_large >= 0 && var.min_replicas_large <= 5
    error_message = "Minimum replicas must be between 0 and 5."
  }
}

variable "max_replicas_large" {
  description = "Maximum number of replicas for large TPU endpoints"
  type        = number
  default     = 2
  
  validation {
    condition     = var.max_replicas_large >= 1 && var.max_replicas_large <= 10
    error_message = "Maximum replicas must be between 1 and 10."
  }
}

variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_redis_cache" {
  description = "Whether to create Redis cache for inference optimization"
  type        = bool
  default     = true
}

variable "redis_memory_size_gb" {
  description = "Memory size for Redis cache in GB"
  type        = number
  default     = 100
  
  validation {
    condition     = var.redis_memory_size_gb >= 1 && var.redis_memory_size_gb <= 300
    error_message = "Redis memory size must be between 1 and 300 GB."
  }
}

variable "enable_cdn" {
  description = "Whether to enable Cloud CDN for response caching"
  type        = bool
  default     = true
}

variable "budget_amount" {
  description = "Budget amount in USD for cost monitoring"
  type        = number
  default     = 10000
  
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "budget_threshold_percent" {
  description = "Budget threshold percentage for alerts (0.0 to 1.0)"
  type        = number
  default     = 0.8
  
  validation {
    condition     = var.budget_threshold_percent > 0 && var.budget_threshold_percent <= 1
    error_message = "Budget threshold must be between 0 and 1."
  }
}

variable "notification_email" {
  description = "Email address for monitoring alerts and notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "ai-inference"
    managed-by  = "terraform"
    environment = "dev"
  }
  
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k))])
    error_message = "Label keys must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "auto_scaling_target_cpu_utilization" {
  description = "Target CPU utilization for auto-scaling (0.0 to 1.0)"
  type        = number
  default     = 0.7
  
  validation {
    condition     = var.auto_scaling_target_cpu_utilization > 0 && var.auto_scaling_target_cpu_utilization <= 1
    error_message = "Target CPU utilization must be between 0 and 1."
  }
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 10
  
  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
  
  validation {
    condition     = var.health_check_timeout >= 1 && var.health_check_timeout <= 60
    error_message = "Health check timeout must be between 1 and 60 seconds."
  }
}

variable "enable_ssl" {
  description = "Whether to enable SSL/TLS for the load balancer"
  type        = bool
  default     = true
}

variable "ssl_certificate_domains" {
  description = "List of domains for SSL certificate (if enable_ssl is true)"
  type        = list(string)
  default     = []
}

variable "enable_bigquery_analytics" {
  description = "Whether to create BigQuery dataset for analytics"
  type        = bool
  default     = true
}

variable "bigquery_dataset_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-west1",
      "europe-west1", "europe-west2", "asia-east1"
    ], var.bigquery_dataset_location)
    error_message = "BigQuery dataset location must be a valid region or multi-region."
  }
}