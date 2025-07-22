# Project and Location Variables
variable "project_id" {
  description = "The Google Cloud project ID to deploy resources into"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for compute instances"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming Variables
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "perf-monitor"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  validation {
    condition = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

# Compute Instance Configuration
variable "instance_machine_type" {
  description = "Machine type for the sample application instance"
  type        = string
  default     = "e2-medium"
  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "n1-standard-1", "n1-standard-2", "n1-standard-4"
    ], var.instance_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "instance_image_family" {
  description = "Operating system image family for the compute instance"
  type        = string
  default     = "debian-11"
}

variable "instance_image_project" {
  description = "Project containing the OS image"
  type        = string
  default     = "debian-cloud"
}

# Monitoring Configuration
variable "alert_threshold_seconds" {
  description = "Response time threshold in seconds for triggering alerts"
  type        = number
  default     = 1.5
  validation {
    condition     = var.alert_threshold_seconds > 0 && var.alert_threshold_seconds <= 10
    error_message = "Alert threshold must be between 0 and 10 seconds."
  }
}

variable "alert_duration" {
  description = "Duration for which condition must be true before alerting"
  type        = string
  default     = "60s"
  validation {
    condition     = can(regex("^[0-9]+[sm]$", var.alert_duration))
    error_message = "Alert duration must be in format like '60s' or '5m'."
  }
}

# Cloud Function Configuration
variable "function_runtime" {
  description = "Runtime environment for Cloud Functions"
  type        = string
  default     = "python39"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311",
      "nodejs16", "nodejs18", "nodejs20"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

# Network Security
variable "allowed_source_ranges" {
  description = "List of CIDR blocks allowed to access the web application"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition = alltrue([
      for cidr in var.allowed_source_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "All source ranges must be valid CIDR blocks."
  }
}

# Resource Labels
variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "performance-monitoring"
    managed_by  = "terraform"
    team        = "devops"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# API Services to Enable
variable "enable_apis" {
  description = "List of Google Cloud APIs to enable for this project"
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "monitoring.googleapis.com",
    "cloudtrace.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com"
  ]
}