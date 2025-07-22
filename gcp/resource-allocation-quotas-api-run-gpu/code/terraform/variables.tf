# Variables for GCP Intelligent Resource Allocation with Cloud Quotas API and Cloud Run GPU

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-southeast1", "asia-northeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region with GPU support."
  }
}

variable "zone" {
  description = "The GCP zone for deploying zonal resources"
  type        = string
  default     = "us-central1-a"
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

variable "resource_suffix" {
  description = "Random suffix for resource names to ensure uniqueness"
  type        = string
  default     = ""
}

# Cloud Run GPU Configuration
variable "cloud_run_gpu_type" {
  description = "GPU type for Cloud Run services"
  type        = string
  default     = "nvidia-l4"
  validation {
    condition = contains([
      "nvidia-l4", "nvidia-t4"
    ], var.cloud_run_gpu_type)
    error_message = "GPU type must be a supported Cloud Run GPU type."
  }
}

variable "cloud_run_gpu_count" {
  description = "Number of GPUs to allocate per Cloud Run instance"
  type        = number
  default     = 1
  validation {
    condition     = var.cloud_run_gpu_count >= 1 && var.cloud_run_gpu_count <= 4
    error_message = "GPU count must be between 1 and 4."
  }
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "4Gi"
}

variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "2"
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 100
    error_message = "Max instances must be between 1 and 100."
  }
}

variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 0
  validation {
    condition     = var.cloud_run_min_instances >= 0 && var.cloud_run_min_instances <= 10
    error_message = "Min instances must be between 0 and 10."
  }
}

# Cloud Function Configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Function"
  type        = string
  default     = "512MB"
}

variable "function_timeout" {
  description = "Timeout for Cloud Function execution"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 60 and 3600 seconds."
  }
}

# Quota Management Configuration
variable "quota_analysis_schedule" {
  description = "Cron schedule for regular quota analysis"
  type        = string
  default     = "*/15 * * * *"
}

variable "peak_analysis_schedule" {
  description = "Cron schedule for peak hour quota analysis"
  type        = string
  default     = "0 9-17 * * 1-5"
}

variable "gpu_utilization_threshold" {
  description = "GPU utilization threshold for quota adjustments"
  type        = number
  default     = 0.8
  validation {
    condition     = var.gpu_utilization_threshold > 0 && var.gpu_utilization_threshold <= 1
    error_message = "GPU utilization threshold must be between 0 and 1."
  }
}

variable "max_gpu_quota" {
  description = "Maximum GPU quota per family"
  type        = number
  default     = 10
  validation {
    condition     = var.max_gpu_quota >= 1 && var.max_gpu_quota <= 100
    error_message = "Max GPU quota must be between 1 and 100."
  }
}

variable "min_gpu_quota" {
  description = "Minimum GPU quota per family"
  type        = number
  default     = 1
  validation {
    condition     = var.min_gpu_quota >= 1 && var.min_gpu_quota <= 10
    error_message = "Min GPU quota must be between 1 and 10."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring dashboard and alerts"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = ""
}

# Cost Management
variable "enable_cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

variable "max_cost_per_hour" {
  description = "Maximum cost per hour for GPU resources"
  type        = number
  default     = 50.0
  validation {
    condition     = var.max_cost_per_hour >= 0
    error_message = "Max cost per hour must be non-negative."
  }
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    recipe     = "resource-allocation-quotas-api-run-gpu"
  }
}

variable "firestore_location" {
  description = "Location for Firestore database"
  type        = string
  default     = "us-central"
  validation {
    condition = contains([
      "us-central", "us-east1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3",
      "asia-northeast1", "asia-southeast1"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or regional location."
  }
}