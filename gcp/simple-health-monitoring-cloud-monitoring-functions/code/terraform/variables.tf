# Input Variables for Simple Health Monitoring Infrastructure
# This file defines all configurable parameters for the monitoring solution

variable "project_id" {
  description = "The Google Cloud Platform project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must be provided and cannot be empty."
  }
}

variable "region" {
  description = "The GCP region where resources will be deployed"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod) for resource naming and tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "monitored_url" {
  description = "The URL to monitor for uptime checks (must include protocol)"
  type        = string
  default     = "https://www.google.com"
  
  validation {
    condition     = can(regex("^https?://", var.monitored_url))
    error_message = "Monitored URL must include http:// or https:// protocol."
  }
}

variable "uptime_check_timeout" {
  description = "Timeout duration for uptime checks in seconds"
  type        = string
  default     = "10s"
  
  validation {
    condition     = can(regex("^[1-9][0-9]*s$", var.uptime_check_timeout))
    error_message = "Timeout must be in format 'Xs' where X is a positive integer."
  }
}

variable "uptime_check_period" {
  description = "How often to run uptime checks"
  type        = string
  default     = "60s"
  
  validation {
    condition = contains(["60s", "300s", "600s", "900s"], var.uptime_check_period)
    error_message = "Period must be one of: 60s, 300s, 600s, 900s."
  }
}

variable "alert_threshold_duration" {
  description = "Duration for which condition must be true before alerting"
  type        = string
  default     = "120s"
  
  validation {
    condition     = can(regex("^[1-9][0-9]*s$", var.alert_threshold_duration))
    error_message = "Duration must be in format 'Xs' where X is a positive integer."
  }
}

variable "function_timeout" {
  description = "Cloud Function timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 256
  
  validation {
    condition = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_max_instances" {
  description = "Maximum number of Cloud Function instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "enable_ssl_validation" {
  description = "Whether to validate SSL certificates in uptime checks"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for alert notifications (optional, for documentation purposes)"
  type        = string
  default     = ""
}

variable "labels" {
  description = "Labels to be applied to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    component  = "health-monitoring"
  }
  
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k))])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}