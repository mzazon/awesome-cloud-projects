# Variables for AI Training Optimization with Dynamic Workload Scheduler and Batch
# These variables allow customization of the training infrastructure deployment

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region with GPU availability."
  }
}

variable "zone" {
  description = "The Google Cloud zone for resource deployment"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and organization"
  type        = string
  default     = "development"
  validation {
    condition = contains([
      "development", "staging", "production", "testing", "demo"
    ], var.environment)
    error_message = "Environment must be one of: development, staging, production, testing, demo."
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

# Storage Configuration Variables
variable "storage_bucket_name" {
  description = "Name for the Cloud Storage bucket (will be suffixed with random string if not unique)"
  type        = string
  default     = "ai-training-data"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_.]*[a-z0-9]$", var.storage_bucket_name))
    error_message = "Bucket name must be valid according to Cloud Storage naming conventions."
  }
}

variable "storage_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west4", "asia-east1", "asia-northeast1"
    ], var.storage_location)
    error_message = "Storage location must be a valid Cloud Storage location."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the Cloud Storage bucket for model checkpoint protection"
  type        = bool
  default     = true
}

# Compute Configuration Variables
variable "machine_type" {
  description = "Machine type for training instances"
  type        = string
  default     = "g2-standard-4"
  validation {
    condition = contains([
      "g2-standard-4", "g2-standard-8", "g2-standard-12", "g2-standard-16",
      "a2-highgpu-1g", "a2-highgpu-2g", "a2-highgpu-4g", "a2-highgpu-8g"
    ], var.machine_type)
    error_message = "Machine type must be a valid GPU-enabled machine type."
  }
}

variable "accelerator_type" {
  description = "Type of GPU accelerator for training workloads"
  type        = string
  default     = "nvidia-l4"
  validation {
    condition = contains([
      "nvidia-l4", "nvidia-t4", "nvidia-v100", "nvidia-a100-80gb", "nvidia-h100-80gb"
    ], var.accelerator_type)
    error_message = "Accelerator type must be a valid NVIDIA GPU type available in Google Cloud."
  }
}

variable "accelerator_count" {
  description = "Number of GPU accelerators per training instance"
  type        = number
  default     = 1
  validation {
    condition     = var.accelerator_count >= 1 && var.accelerator_count <= 8
    error_message = "Accelerator count must be between 1 and 8."
  }
}

variable "boot_disk_size_gb" {
  description = "Size of the boot disk in GB for training instances"
  type        = number
  default     = 50
  validation {
    condition     = var.boot_disk_size_gb >= 20 && var.boot_disk_size_gb <= 2048
    error_message = "Boot disk size must be between 20 GB and 2048 GB."
  }
}

variable "boot_disk_type" {
  description = "Type of boot disk for training instances"
  type        = string
  default     = "pd-standard"
  validation {
    condition = contains([
      "pd-standard", "pd-ssd", "pd-balanced", "pd-extreme"
    ], var.boot_disk_type)
    error_message = "Boot disk type must be a valid persistent disk type."
  }
}

# Container and Training Configuration Variables
variable "container_image" {
  description = "Container image for training workloads"
  type        = string
  default     = "gcr.io/deeplearning-platform-release/pytorch-gpu.1-13:latest"
  validation {
    condition     = can(regex("^[a-z0-9.-]+(/[a-z0-9._-]+)*:[a-z0-9._-]+$", var.container_image))
    error_message = "Container image must be a valid container image reference."
  }
}

variable "training_script_path" {
  description = "Path to the training script in the Cloud Storage bucket"
  type        = string
  default     = "scripts/training_script.py"
}

variable "max_training_duration" {
  description = "Maximum duration for training jobs in seconds"
  type        = number
  default     = 3600
  validation {
    condition     = var.max_training_duration >= 300 && var.max_training_duration <= 86400
    error_message = "Training duration must be between 5 minutes (300s) and 24 hours (86400s)."
  }
}

variable "max_retry_count" {
  description = "Maximum number of retries for failed training tasks"
  type        = number
  default     = 2
  validation {
    condition     = var.max_retry_count >= 0 && var.max_retry_count <= 10
    error_message = "Retry count must be between 0 and 10."
  }
}

# Batch Job Configuration Variables
variable "task_count" {
  description = "Number of parallel training tasks to run"
  type        = number
  default     = 1
  validation {
    condition     = var.task_count >= 1 && var.task_count <= 100
    error_message = "Task count must be between 1 and 100."
  }
}

variable "parallelism" {
  description = "Maximum number of tasks that can run in parallel"
  type        = number
  default     = 1
  validation {
    condition     = var.parallelism >= 1 && var.parallelism <= 100
    error_message = "Parallelism must be between 1 and 100."
  }
}

variable "cpu_milli" {
  description = "CPU allocation in millicores for training tasks"
  type        = number
  default     = 4000
  validation {
    condition     = var.cpu_milli >= 500 && var.cpu_milli <= 64000
    error_message = "CPU allocation must be between 500 and 64000 millicores."
  }
}

variable "memory_mib" {
  description = "Memory allocation in MiB for training tasks"
  type        = number
  default     = 16384
  validation {
    condition     = var.memory_mib >= 1024 && var.memory_mib <= 655360
    error_message = "Memory allocation must be between 1024 MiB (1 GB) and 655360 MiB (640 GB)."
  }
}

# Service Account Configuration Variables
variable "service_account_name" {
  description = "Name for the service account used by batch training jobs"
  type        = string
  default     = "batch-training-sa"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.service_account_name))
    error_message = "Service account name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "service_account_display_name" {
  description = "Display name for the batch training service account"
  type        = string
  default     = "Batch Training Service Account"
}

# Monitoring and Alerting Configuration Variables
variable "enable_monitoring_dashboard" {
  description = "Enable creation of Cloud Monitoring dashboard for training visibility"
  type        = bool
  default     = true
}

variable "enable_cost_monitoring" {
  description = "Enable cost monitoring and alerting for training workloads"
  type        = bool
  default     = true
}

variable "gpu_utilization_threshold" {
  description = "GPU utilization threshold for alerting (0.0 to 1.0)"
  type        = number
  default     = 0.7
  validation {
    condition     = var.gpu_utilization_threshold >= 0.1 && var.gpu_utilization_threshold <= 1.0
    error_message = "GPU utilization threshold must be between 0.1 and 1.0."
  }
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for monitoring alerts"
  type        = list(string)
  default     = []
}

# Network Configuration Variables
variable "network_name" {
  description = "Name of the VPC network (if empty, uses default network)"
  type        = string
  default     = ""
}

variable "subnet_name" {
  description = "Name of the subnet (if empty, uses default subnet)"
  type        = string
  default     = ""
}

variable "enable_ip_forwarding" {
  description = "Enable IP forwarding for training instances"
  type        = bool
  default     = false
}

# Security Configuration Variables
variable "enable_secure_boot" {
  description = "Enable secure boot for training instances"
  type        = bool
  default     = true
}

variable "enable_vtpm" {
  description = "Enable vTPM for training instances"
  type        = bool
  default     = true
}

variable "enable_integrity_monitoring" {
  description = "Enable integrity monitoring for training instances"
  type        = bool
  default     = true
}

# API Configuration Variables
variable "enable_required_apis" {
  description = "Automatically enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "required_apis" {
  description = "List of required Google Cloud APIs for the training infrastructure"
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "batch.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com"
  ]
}

# Tagging and Organization Variables
variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : can(regex("^[a-z][a-z0-9_-]*$", k))
    ])
    error_message = "Label keys must start with lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "cost_center" {
  description = "Cost center for billing and cost allocation"
  type        = string
  default     = "ml-research"
}

variable "team" {
  description = "Team responsible for the training workloads"
  type        = string
  default     = "ai-team"
}