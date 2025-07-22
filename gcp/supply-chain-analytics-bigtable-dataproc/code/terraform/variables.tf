# Project configuration variables
variable "project_id" {
  description = "Google Cloud Project ID for supply chain analytics"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource naming variables
variable "name_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "supply-chain"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "Name prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
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

# Bigtable configuration variables
variable "bigtable_display_name" {
  description = "Display name for the Bigtable instance"
  type        = string
  default     = "Supply Chain Analytics Instance"
}

variable "bigtable_cluster_num_nodes" {
  description = "Number of nodes in the Bigtable cluster"
  type        = number
  default     = 3
  validation {
    condition     = var.bigtable_cluster_num_nodes >= 1 && var.bigtable_cluster_num_nodes <= 30
    error_message = "Bigtable cluster must have between 1 and 30 nodes."
  }
}

variable "bigtable_storage_type" {
  description = "Storage type for Bigtable cluster (SSD or HDD)"
  type        = string
  default     = "SSD"
  validation {
    condition     = contains(["SSD", "HDD"], var.bigtable_storage_type)
    error_message = "Bigtable storage type must be either SSD or HDD."
  }
}

variable "bigtable_instance_type" {
  description = "Instance type for Bigtable (PRODUCTION or DEVELOPMENT)"
  type        = string
  default     = "PRODUCTION"
  validation {
    condition     = contains(["PRODUCTION", "DEVELOPMENT"], var.bigtable_instance_type)
    error_message = "Bigtable instance type must be either PRODUCTION or DEVELOPMENT."
  }
}

# Dataproc configuration variables
variable "dataproc_master_machine_type" {
  description = "Machine type for Dataproc master node"
  type        = string
  default     = "n1-standard-4"
}

variable "dataproc_master_disk_size" {
  description = "Boot disk size for Dataproc master node (GB)"
  type        = number
  default     = 50
  validation {
    condition     = var.dataproc_master_disk_size >= 10 && var.dataproc_master_disk_size <= 65536
    error_message = "Master disk size must be between 10 and 65536 GB."
  }
}

variable "dataproc_worker_machine_type" {
  description = "Machine type for Dataproc worker nodes"
  type        = string
  default     = "n1-standard-2"
}

variable "dataproc_worker_disk_size" {
  description = "Boot disk size for Dataproc worker nodes (GB)"
  type        = number
  default     = 50
  validation {
    condition     = var.dataproc_worker_disk_size >= 10 && var.dataproc_worker_disk_size <= 65536
    error_message = "Worker disk size must be between 10 and 65536 GB."
  }
}

variable "dataproc_num_workers" {
  description = "Number of worker nodes in Dataproc cluster"
  type        = number
  default     = 3
  validation {
    condition     = var.dataproc_num_workers >= 0 && var.dataproc_num_workers <= 1000
    error_message = "Number of workers must be between 0 and 1000."
  }
}

variable "dataproc_num_preemptible_workers" {
  description = "Number of preemptible worker nodes in Dataproc cluster"
  type        = number
  default     = 3
  validation {
    condition     = var.dataproc_num_preemptible_workers >= 0 && var.dataproc_num_preemptible_workers <= 1000
    error_message = "Number of preemptible workers must be between 0 and 1000."
  }
}

variable "dataproc_max_workers" {
  description = "Maximum number of workers for autoscaling"
  type        = number
  default     = 8
  validation {
    condition     = var.dataproc_max_workers >= var.dataproc_num_workers
    error_message = "Maximum workers must be greater than or equal to the number of workers."
  }
}

variable "dataproc_image_version" {
  description = "Dataproc image version"
  type        = string
  default     = "2.0-debian10"
}

# Cloud Storage configuration
variable "storage_bucket_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "storage_bucket_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_bucket_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# Cloud Function configuration
variable "cloud_function_runtime" {
  description = "Runtime for Cloud Function"
  type        = string
  default     = "python39"
  validation {
    condition = contains([
      "python37", "python38", "python39", "python310", "python311"
    ], var.cloud_function_runtime)
    error_message = "Runtime must be a supported Python version."
  }
}

variable "cloud_function_memory" {
  description = "Memory allocation for Cloud Function (MB)"
  type        = number
  default     = 256
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.cloud_function_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "cloud_function_timeout" {
  description = "Timeout for Cloud Function (seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.cloud_function_timeout >= 1 && var.cloud_function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

# Cloud Scheduler configuration
variable "scheduler_cron_schedule" {
  description = "Cron schedule for automated analytics job"
  type        = string
  default     = "0 */6 * * *"
}

variable "scheduler_timezone" {
  description = "Timezone for Cloud Scheduler"
  type        = string
  default     = "UTC"
}

# Network configuration
variable "enable_private_nodes" {
  description = "Enable private nodes for Dataproc cluster"
  type        = bool
  default     = false
}

variable "enable_ip_alias" {
  description = "Enable IP alias for Dataproc cluster"
  type        = bool
  default     = true
}

# Monitoring and logging configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for resources"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Cloud Logging for resources"
  type        = bool
  default     = true
}

# Labels for resource organization
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "supply-chain-analytics"
    managed-by  = "terraform"
    environment = "development"
  }
}

# Service account configuration
variable "create_service_account" {
  description = "Create a dedicated service account for the analytics workload"
  type        = bool
  default     = true
}

variable "service_account_name" {
  description = "Name for the analytics service account"
  type        = string
  default     = "supply-chain-analytics-sa"
}

# Optional API enablement control
variable "enable_apis" {
  description = "Enable required Google Cloud APIs"
  type        = bool
  default     = true
}