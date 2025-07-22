# Variables for Multi-Cloud Resource Discovery Infrastructure
# This file defines all configurable parameters for the solution

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must be provided."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "multicloud-discovery"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs automatically"
  type        = bool
  default     = true
}

variable "scheduler_frequency" {
  description = "Cloud Scheduler job frequency in cron format (default: every 6 hours)"
  type        = string
  default     = "0 */6 * * *"
  
  validation {
    condition     = can(regex("^[0-9/*,-]+ [0-9/*,-]+ [0-9/*,-]+ [0-9/*,-]+ [0-9/*,-]+$", var.scheduler_frequency))
    error_message = "Scheduler frequency must be a valid cron expression."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "pubsub_message_retention" {
  description = "Pub/Sub message retention duration"
  type        = string
  default     = "604800s" # 7 days
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_message_retention))
    error_message = "Message retention must be specified in seconds (e.g., 604800s for 7 days)."
  }
}

variable "pubsub_ack_deadline" {
  description = "Pub/Sub acknowledgment deadline in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.pubsub_ack_deadline >= 10 && var.pubsub_ack_deadline <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

variable "storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring dashboard and alerts"
  type        = bool
  default     = true
}

variable "alert_notification_channels" {
  description = "List of notification channel names for alerts (must be created separately)"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "multi-cloud-discovery"
    managed-by  = "terraform"
    component   = "location-finder"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "scheduler_timezone" {
  description = "Timezone for Cloud Scheduler job"
  type        = string
  default     = "UTC"
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}