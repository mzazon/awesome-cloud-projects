# Project and region configuration
variable "project_id" {
  description = "The GCP project ID for deploying resources"
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
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports Parallelstore."
  }
}

variable "zone" {
  description = "The GCP zone for deploying zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

# Resource naming configuration
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "hpc-analytics"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

# Storage configuration
variable "bucket_location" {
  description = "Location for the Cloud Storage bucket (should match region for performance)"
  type        = string
  default     = "US-CENTRAL1"
}

variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

# Parallelstore configuration
variable "parallelstore_capacity_gib" {
  description = "Capacity of the Parallelstore instance in GiB (minimum 12,000 GiB)"
  type        = number
  default     = 12000
  validation {
    condition     = var.parallelstore_capacity_gib >= 12000
    error_message = "Parallelstore capacity must be at least 12,000 GiB."
  }
}

variable "parallelstore_performance_tier" {
  description = "Performance tier for Parallelstore (affects throughput and IOPS)"
  type        = string
  default     = "parallelstore-standard"
  validation {
    condition = contains([
      "parallelstore-standard", "parallelstore-premium"
    ], var.parallelstore_performance_tier)
    error_message = "Performance tier must be either 'parallelstore-standard' or 'parallelstore-premium'."
  }
}

# Compute configuration
variable "vm_machine_type" {
  description = "Machine type for the analytics VM"
  type        = string
  default     = "c2-standard-16"
}

variable "vm_boot_disk_size" {
  description = "Boot disk size for the analytics VM in GB"
  type        = number
  default     = 200
  validation {
    condition     = var.vm_boot_disk_size >= 100
    error_message = "Boot disk size must be at least 100 GB."
  }
}

variable "vm_boot_disk_type" {
  description = "Boot disk type for the analytics VM"
  type        = string
  default     = "pd-ssd"
  validation {
    condition = contains([
      "pd-standard", "pd-ssd", "pd-balanced"
    ], var.vm_boot_disk_type)
    error_message = "Boot disk type must be one of: pd-standard, pd-ssd, pd-balanced."
  }
}

# Dataproc configuration
variable "dataproc_num_workers" {
  description = "Number of worker nodes in the Dataproc cluster"
  type        = number
  default     = 4
  validation {
    condition     = var.dataproc_num_workers >= 2 && var.dataproc_num_workers <= 100
    error_message = "Number of workers must be between 2 and 100."
  }
}

variable "dataproc_worker_machine_type" {
  description = "Machine type for Dataproc worker nodes"
  type        = string
  default     = "c2-standard-8"
}

variable "dataproc_master_machine_type" {
  description = "Machine type for Dataproc master node"
  type        = string
  default     = "c2-standard-4"
}

variable "dataproc_image_version" {
  description = "Dataproc image version"
  type        = string
  default     = "2.1-ubuntu20"
}

# Networking configuration
variable "network_name" {
  description = "Name of the VPC network (leave empty to use default network)"
  type        = string
  default     = ""
}

variable "subnet_name" {
  description = "Name of the subnet (leave empty to use default subnet)"
  type        = string
  default     = ""
}

variable "enable_private_google_access" {
  description = "Enable Private Google Access for the subnet"
  type        = bool
  default     = true
}

# BigQuery configuration
variable "bigquery_dataset_location" {
  description = "Location for the BigQuery dataset"
  type        = string
  default     = "US"
}

variable "bigquery_dataset_description" {
  description = "Description for the BigQuery dataset"
  type        = string
  default     = "High-performance analytics dataset with Cloud Storage FUSE and Parallelstore integration"
}

# Monitoring and alerting configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "monitoring_notification_channels" {
  description = "List of notification channel IDs for monitoring alerts"
  type        = list(string)
  default     = []
}

# Service account configuration
variable "create_service_account" {
  description = "Create a dedicated service account for the resources"
  type        = bool
  default     = true
}

variable "service_account_roles" {
  description = "List of IAM roles to assign to the service account"
  type        = list(string)
  default = [
    "roles/storage.admin",
    "roles/bigquery.admin",
    "roles/dataproc.admin",
    "roles/compute.admin",
    "roles/monitoring.editor",
    "roles/logging.admin"
  ]
}

# Labels for resource organization
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "demo"
    project     = "hpc-analytics"
    managed-by  = "terraform"
  }
}

# Data generation configuration
variable "create_sample_data" {
  description = "Create sample data for testing the analytics pipeline"
  type        = bool
  default     = true
}

variable "sample_data_files_count" {
  description = "Number of sample data files to create"
  type        = number
  default     = 100
  validation {
    condition     = var.sample_data_files_count >= 1 && var.sample_data_files_count <= 1000
    error_message = "Sample data files count must be between 1 and 1000."
  }
}

# Security configuration
variable "enable_shielded_vm" {
  description = "Enable Shielded VM features for enhanced security"
  type        = bool
  default     = true
}

variable "enable_secure_boot" {
  description = "Enable secure boot for VMs"
  type        = bool
  default     = true
}

variable "enable_vtpm" {
  description = "Enable virtual Trusted Platform Module (vTPM)"
  type        = bool
  default     = true
}

variable "enable_integrity_monitoring" {
  description = "Enable integrity monitoring for VMs"
  type        = bool
  default     = true
}