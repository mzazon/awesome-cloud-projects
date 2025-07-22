# Project and Location Variables
variable "project_id" {
  description = "The Google Cloud Project ID"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central2"
  validation {
    condition = contains([
      "us-central1", "us-central2", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3", "asia-south1",
      "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central2-b"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone cannot be empty."
  }
}

# Storage Configuration
variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (will be made unique)"
  type        = string
  default     = "ml-training-pipeline"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9\\-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# TPU Configuration
variable "tpu_name_prefix" {
  description = "Prefix for the TPU instance name (will be made unique)"
  type        = string
  default     = "training-tpu"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9\\-]*[a-z0-9]$", var.tpu_name_prefix))
    error_message = "TPU name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "tpu_accelerator_type" {
  description = "TPU accelerator type for training workloads"
  type        = string
  default     = "v6e-8"
  validation {
    condition = contains([
      "v6e-8", "v6e-16", "v6e-32", "v6e-64", "v6e-128", "v6e-256"
    ], var.tpu_accelerator_type)
    error_message = "TPU accelerator type must be a valid v6e configuration."
  }
}

variable "tpu_runtime_version" {
  description = "TPU runtime version for the training environment"
  type        = string
  default     = "tpu-vm-v4-base"
  validation {
    condition     = length(var.tpu_runtime_version) > 0
    error_message = "TPU runtime version cannot be empty."
  }
}

variable "tpu_network" {
  description = "VPC network for TPU resources"
  type        = string
  default     = "default"
}

variable "tpu_subnetwork" {
  description = "VPC subnetwork for TPU resources"
  type        = string
  default     = "default"
}

# Dataproc Configuration
variable "dataproc_batch_id_prefix" {
  description = "Prefix for Dataproc Serverless batch job ID (will be made unique)"
  type        = string
  default     = "preprocessing"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9\\-]*[a-z0-9]$", var.dataproc_batch_id_prefix))
    error_message = "Dataproc batch ID prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "dataproc_executor_memory" {
  description = "Memory allocation for Spark executors"
  type        = string
  default     = "4g"
  validation {
    condition     = can(regex("^[0-9]+[mg]$", var.dataproc_executor_memory))
    error_message = "Executor memory must be in format like '4g' or '512m'."
  }
}

variable "dataproc_driver_memory" {
  description = "Memory allocation for Spark driver"
  type        = string
  default     = "2g"
  validation {
    condition     = can(regex("^[0-9]+[mg]$", var.dataproc_driver_memory))
    error_message = "Driver memory must be in format like '2g' or '512m'."
  }
}

variable "dataproc_max_executors" {
  description = "Maximum number of Spark executors for auto-scaling"
  type        = number
  default     = 10
  validation {
    condition     = var.dataproc_max_executors > 0 && var.dataproc_max_executors <= 100
    error_message = "Maximum executors must be between 1 and 100."
  }
}

# Vertex AI Configuration
variable "vertex_ai_training_display_name" {
  description = "Display name for Vertex AI training job"
  type        = string
  default     = "tpu-v6e-training-pipeline"
  validation {
    condition     = length(var.vertex_ai_training_display_name) > 0
    error_message = "Vertex AI training display name cannot be empty."
  }
}

variable "vertex_ai_container_image" {
  description = "Container image for Vertex AI training"
  type        = string
  default     = "gcr.io/deeplearning-platform-release/tf2-tpu.2-11"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9\\-\\.\\/:]*[a-z0-9]$", var.vertex_ai_container_image))
    error_message = "Container image must be a valid container registry URL."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring dashboards and alerts"
  type        = bool
  default     = true
}

variable "monitoring_dashboard_name" {
  description = "Name for the Cloud Monitoring dashboard"
  type        = string
  default     = "TPU v6e Training Dashboard"
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for alerting"
  type        = list(string)
  default     = []
}

# Service Account Configuration
variable "custom_service_account_email" {
  description = "Custom service account email for TPU and Dataproc (optional)"
  type        = string
  default     = ""
}

# Resource Tags
variable "resource_labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "ml-training"
    project     = "tpu-dataproc-pipeline"
    managed-by  = "terraform"
  }
  validation {
    condition     = can([for k, v in var.resource_labels : regex("^[a-z0-9_-]*$", k) if length(k) <= 63])
    error_message = "Label keys must contain only lowercase letters, numbers, underscores, and hyphens, and be <= 63 characters."
  }
}

# Network Security
variable "firewall_source_ranges" {
  description = "Source IP ranges for firewall rules"
  type        = list(string)
  default     = ["10.0.0.0/8"]
  validation {
    condition     = length(var.firewall_source_ranges) > 0
    error_message = "At least one source range must be specified."
  }
}

# Cost Control
variable "enable_preemptible_tpu" {
  description = "Enable preemptible TPU instances for cost savings (development only)"
  type        = bool
  default     = false
}

variable "auto_delete_bucket" {
  description = "Automatically delete storage bucket when destroying infrastructure"
  type        = bool
  default     = false
}

# Performance Tuning
variable "bucket_uniform_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

variable "bucket_versioning_enabled" {
  description = "Enable object versioning for the Cloud Storage bucket"
  type        = bool
  default     = true
}