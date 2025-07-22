# Input Variables for Continuous Performance Optimization Infrastructure
# This file defines all configurable parameters for the Terraform deployment

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region where resources will be created"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-southeast1",
      "australia-southeast1", "southamerica-east1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone where resources will be created"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z-]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., us-central1-a)."
  }
}

variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.resource_suffix))
    error_message = "Resource suffix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "repo_name" {
  description = "Name of the Cloud Source Repository"
  type        = string
  default     = "app-performance-repo"
  
  validation {
    condition     = can(regex("^[a-z0-9-_]+$", var.repo_name))
    error_message = "Repository name must contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

variable "service_name" {
  description = "Name of the Cloud Run service"
  type        = string
  default     = "performance-app"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service_name))
    error_message = "Service name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "build_trigger_name" {
  description = "Name of the Cloud Build trigger"
  type        = string
  default     = "perf-optimization-trigger"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.build_trigger_name))
    error_message = "Build trigger name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "container_image" {
  description = "Container image for the Cloud Run service"
  type        = string
  default     = "gcr.io/cloudrun/hello"
  
  validation {
    condition     = can(regex("^(gcr\\.io|asia\\.gcr\\.io|eu\\.gcr\\.io|us\\.gcr\\.io)/[a-z0-9-]+/[a-z0-9-]+(:.*)?$", var.container_image))
    error_message = "Container image must be a valid GCR image path."
  }
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "512Mi"
  
  validation {
    condition     = can(regex("^[0-9]+Mi$", var.cloud_run_memory))
    error_message = "Memory must be specified in Mi format (e.g., 512Mi)."
  }
}

variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "1"
  
  validation {
    condition     = contains(["1", "2", "4", "8"], var.cloud_run_cpu)
    error_message = "CPU must be one of: 1, 2, 4, or 8."
  }
}

variable "cloud_run_concurrency" {
  description = "Maximum number of concurrent requests per instance"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cloud_run_concurrency >= 1 && var.cloud_run_concurrency <= 1000
    error_message = "Concurrency must be between 1 and 1000."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 1
  
  validation {
    condition     = var.cloud_run_min_instances >= 0 && var.cloud_run_min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "response_time_threshold" {
  description = "Response time threshold in seconds for alerting"
  type        = number
  default     = 1.0
  
  validation {
    condition     = var.response_time_threshold > 0 && var.response_time_threshold <= 30
    error_message = "Response time threshold must be between 0 and 30 seconds."
  }
}

variable "memory_threshold" {
  description = "Memory utilization threshold (0-1) for alerting"
  type        = number
  default     = 0.8
  
  validation {
    condition     = var.memory_threshold > 0 && var.memory_threshold <= 1
    error_message = "Memory threshold must be between 0 and 1."
  }
}

variable "alert_duration" {
  description = "Duration for which condition must be true before alerting"
  type        = string
  default     = "300s"
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.alert_duration))
    error_message = "Alert duration must be in seconds format (e.g., 300s)."
  }
}

variable "notification_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "performance-optimization"
    managed-by  = "terraform"
    purpose     = "continuous-performance-optimization"
  }
  
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))])
    error_message = "Label keys and values must contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

variable "build_timeout" {
  description = "Cloud Build timeout in seconds"
  type        = number
  default     = 600
  
  validation {
    condition     = var.build_timeout >= 60 && var.build_timeout <= 86400
    error_message = "Build timeout must be between 60 and 86400 seconds."
  }
}

variable "github_repo_owner" {
  description = "GitHub repository owner (for GitHub-based triggers)"
  type        = string
  default     = ""
}

variable "github_repo_name" {
  description = "GitHub repository name (for GitHub-based triggers)"
  type        = string
  default     = ""
}

variable "branch_pattern" {
  description = "Branch pattern for build triggers"
  type        = string
  default     = ".*"
}

variable "environment_variables" {
  description = "Environment variables for Cloud Run service"
  type        = map(string)
  default = {
    NODE_ENV = "production"
  }
}