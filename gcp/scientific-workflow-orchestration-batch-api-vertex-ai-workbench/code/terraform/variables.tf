# Variable definitions for scientific workflow orchestration infrastructure
# These variables allow customization of the genomics research environment

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "genomics"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

# Cloud Storage Configuration
variable "storage_class" {
  description = "Storage class for the genomics data bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for the genomics data bucket"
  type        = bool
  default     = true
}

variable "lifecycle_age_days" {
  description = "Number of days after which to transition objects to cheaper storage class"
  type        = number
  default     = 30
  validation {
    condition     = var.lifecycle_age_days > 0 && var.lifecycle_age_days <= 3650
    error_message = "Lifecycle age must be between 1 and 3650 days."
  }
}

# BigQuery Configuration
variable "bigquery_location" {
  description = "Location for BigQuery datasets"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "asia-east1", "asia-northeast1", "asia-southeast1",
      "australia-southeast1", "europe-west1", "europe-west2", "europe-west3",
      "europe-west4", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid region or multi-region."
  }
}

variable "bq_deletion_protection" {
  description = "Enable deletion protection for BigQuery datasets"
  type        = bool
  default     = true
}

# Vertex AI Workbench Configuration
variable "workbench_machine_type" {
  description = "Machine type for Vertex AI Workbench instance"
  type        = string
  default     = "n1-standard-4"
  validation {
    condition = can(regex("^(n1|n2|e2|c2|m1|m2)-(standard|highmem|highcpu)-[0-9]+$", var.workbench_machine_type))
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "workbench_boot_disk_size" {
  description = "Boot disk size for Workbench instance in GB"
  type        = number
  default     = 100
  validation {
    condition     = var.workbench_boot_disk_size >= 20 && var.workbench_boot_disk_size <= 2048
    error_message = "Boot disk size must be between 20 and 2048 GB."
  }
}

variable "workbench_data_disk_size" {
  description = "Data disk size for Workbench instance in GB"
  type        = number
  default     = 200
  validation {
    condition     = var.workbench_data_disk_size >= 10 && var.workbench_data_disk_size <= 64000
    error_message = "Data disk size must be between 10 and 64000 GB."
  }
}

variable "enable_gpu" {
  description = "Enable GPU for Vertex AI Workbench instance"
  type        = bool
  default     = false
}

variable "gpu_type" {
  description = "GPU type for Workbench instance (only used if enable_gpu is true)"
  type        = string
  default     = "NVIDIA_TESLA_T4"
  validation {
    condition = contains([
      "NVIDIA_TESLA_K80", "NVIDIA_TESLA_P4", "NVIDIA_TESLA_P100",
      "NVIDIA_TESLA_V100", "NVIDIA_TESLA_T4", "NVIDIA_A100_40GB", "NVIDIA_A100_80GB"
    ], var.gpu_type)
    error_message = "GPU type must be a valid NVIDIA GPU type available in Google Cloud."
  }
}

variable "gpu_count" {
  description = "Number of GPUs for Workbench instance (only used if enable_gpu is true)"
  type        = number
  default     = 1
  validation {
    condition     = var.gpu_count >= 1 && var.gpu_count <= 8
    error_message = "GPU count must be between 1 and 8."
  }
}

# Cloud Batch Configuration
variable "batch_job_parallelism" {
  description = "Number of parallel tasks for Cloud Batch jobs"
  type        = number
  default     = 3
  validation {
    condition     = var.batch_job_parallelism >= 1 && var.batch_job_parallelism <= 100
    error_message = "Batch job parallelism must be between 1 and 100."
  }
}

variable "batch_task_count" {
  description = "Total number of tasks for Cloud Batch jobs"
  type        = number
  default     = 5
  validation {
    condition     = var.batch_task_count >= 1 && var.batch_task_count <= 1000
    error_message = "Batch task count must be between 1 and 1000."
  }
}

variable "batch_machine_type" {
  description = "Machine type for Cloud Batch worker nodes"
  type        = string
  default     = "e2-standard-2"
  validation {
    condition = can(regex("^(n1|n2|e2|c2|m1|m2)-(standard|highmem|highcpu)-[0-9]+$", var.batch_machine_type))
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "use_preemptible" {
  description = "Use preemptible instances for Cloud Batch to reduce costs"
  type        = bool
  default     = true
}

# Network Configuration
variable "enable_private_ip" {
  description = "Enable private IP for Vertex AI Workbench instance"
  type        = bool
  default     = false
}

variable "network_name" {
  description = "Name of the VPC network (uses default if not specified)"
  type        = string
  default     = "default"
}

variable "subnet_name" {
  description = "Name of the subnet (uses default if not specified)"
  type        = string
  default     = "default"
}

# IAM and Security Configuration
variable "enable_os_login" {
  description = "Enable OS Login for enhanced security"
  type        = bool
  default     = true
}

variable "enable_ip_forwarding" {
  description = "Enable IP forwarding for the Workbench instance"
  type        = bool
  default     = false
}

# Monitoring and Logging
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for resources"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Cloud Logging for Batch jobs"
  type        = bool
  default     = true
}

# Tagging and Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "genomics-research"
    team        = "bioinformatics"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain lowercase letters, numbers, underscores, and hyphens."
  }
}