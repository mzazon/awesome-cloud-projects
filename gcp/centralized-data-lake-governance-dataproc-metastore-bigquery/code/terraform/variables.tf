# Variables for centralized data lake governance infrastructure
# This file defines all configurable parameters for the deployment

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone cannot be empty."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "data-governance"
  validation {
    condition     = length(var.resource_prefix) <= 20 && can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must be lowercase alphanumeric with hyphens only, max 20 characters."
  }
}

# Cloud Storage Configuration
variable "storage_bucket_name" {
  description = "Name for the data lake storage bucket (will be suffixed with random string)"
  type        = string
  default     = ""
}

variable "storage_class" {
  description = "Storage class for the data lake bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "bucket_location" {
  description = "Location for the Cloud Storage bucket"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "asia-east1",
      "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.bucket_location)
    error_message = "Bucket location must be a valid GCS location."
  }
}

# BigLake Metastore Configuration
variable "metastore_name" {
  description = "Name for the BigLake Metastore service"
  type        = string
  default     = ""
}

variable "metastore_tier" {
  description = "Service tier for the BigLake Metastore"
  type        = string
  default     = "DEVELOPER"
  validation {
    condition     = contains(["DEVELOPER", "ENTERPRISE"], var.metastore_tier)
    error_message = "Metastore tier must be DEVELOPER or ENTERPRISE."
  }
}

variable "metastore_database_type" {
  description = "Database type for the metastore backend"
  type        = string
  default     = "MYSQL"
  validation {
    condition     = contains(["MYSQL", "SPANNER"], var.metastore_database_type)
    error_message = "Database type must be MYSQL or SPANNER."
  }
}

variable "hive_metastore_version" {
  description = "Hive Metastore version"
  type        = string
  default     = "3.1.2"
  validation {
    condition = contains([
      "2.3.9", "3.1.2", "3.1.3"
    ], var.hive_metastore_version)
    error_message = "Hive Metastore version must be supported."
  }
}

# BigQuery Configuration
variable "bigquery_dataset_id" {
  description = "BigQuery dataset ID for the governance dataset"
  type        = string
  default     = ""
}

variable "bigquery_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "asia-east1",
      "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid location."
  }
}

variable "dataset_description" {
  description = "Description for the BigQuery dataset"
  type        = string
  default     = "Governance dataset with metastore integration for centralized data lake management"
}

variable "table_expiration_ms" {
  description = "Default table expiration in milliseconds (null for no expiration)"
  type        = number
  default     = null
}

# Dataproc Configuration
variable "dataproc_cluster_name" {
  description = "Name for the Dataproc cluster"
  type        = string
  default     = ""
}

variable "dataproc_image_version" {
  description = "Dataproc image version"
  type        = string
  default     = "2.0-debian10"
  validation {
    condition = can(regex("^[0-9]\\.[0-9]-(debian10|ubuntu18|ubuntu20)$", var.dataproc_image_version))
    error_message = "Dataproc image version must be in format X.Y-osversion."
  }
}

variable "master_machine_type" {
  description = "Machine type for Dataproc master node"
  type        = string
  default     = "n1-standard-2"
}

variable "worker_machine_type" {
  description = "Machine type for Dataproc worker nodes"
  type        = string
  default     = "n1-standard-2"
}

variable "num_workers" {
  description = "Number of worker nodes in the Dataproc cluster"
  type        = number
  default     = 2
  validation {
    condition     = var.num_workers >= 0 && var.num_workers <= 1000
    error_message = "Number of workers must be between 0 and 1000."
  }
}

variable "preemptible_workers" {
  description = "Number of preemptible worker nodes"
  type        = number
  default     = 2
  validation {
    condition     = var.preemptible_workers >= 0 && var.preemptible_workers <= 1000
    error_message = "Number of preemptible workers must be between 0 and 1000."
  }
}

variable "enable_autoscaling" {
  description = "Enable autoscaling for the Dataproc cluster"
  type        = bool
  default     = true
}

variable "max_workers" {
  description = "Maximum number of workers when autoscaling is enabled"
  type        = number
  default     = 5
  validation {
    condition     = var.max_workers >= 0 && var.max_workers <= 1000
    error_message = "Maximum workers must be between 0 and 1000."
  }
}

variable "min_workers" {
  description = "Minimum number of workers when autoscaling is enabled"
  type        = number
  default     = 0
  validation {
    condition     = var.min_workers >= 0 && var.min_workers <= 1000
    error_message = "Minimum workers must be between 0 and 1000."
  }
}

variable "disk_size_gb" {
  description = "Disk size in GB for Dataproc nodes"
  type        = number
  default     = 100
  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536
    error_message = "Disk size must be between 10 and 65536 GB."
  }
}

variable "disk_type" {
  description = "Disk type for Dataproc nodes"
  type        = string
  default     = "pd-standard"
  validation {
    condition     = contains(["pd-standard", "pd-ssd", "pd-balanced"], var.disk_type)
    error_message = "Disk type must be pd-standard, pd-ssd, or pd-balanced."
  }
}

# Network Configuration
variable "enable_private_cluster" {
  description = "Enable private IP for Dataproc cluster"
  type        = bool
  default     = false
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint access only"
  type        = bool
  default     = false
}

variable "network" {
  description = "VPC network for Dataproc cluster (defaults to default network)"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Subnetwork for Dataproc cluster (optional)"
  type        = string
  default     = ""
}

# Security Configuration
variable "enable_encryption" {
  description = "Enable encryption at rest for data lake resources"
  type        = bool
  default     = true
}

variable "kms_key_name" {
  description = "KMS key name for encryption (optional, will create new key if not specified)"
  type        = string
  default     = ""
}

# Data Catalog Configuration
variable "enable_data_catalog" {
  description = "Enable Data Catalog integration for metadata discovery"
  type        = bool
  default     = true
}

# Sample Data Configuration
variable "load_sample_data" {
  description = "Load sample retail data for testing"
  type        = bool
  default     = true
}

variable "sample_data_source" {
  description = "Source bucket for sample data"
  type        = string
  default     = "gs://cloud-samples-data/bigquery/sample-transactions"
}

# Monitoring and Logging
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

# Resource Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "data-governance"
    environment = "development"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Cost Management
variable "auto_delete_cluster" {
  description = "Auto-delete Dataproc cluster after specified time (in seconds, 0 to disable)"
  type        = number
  default     = 0
  validation {
    condition     = var.auto_delete_cluster >= 0
    error_message = "Auto delete time must be non-negative."
  }
}

variable "enable_preemptible_masters" {
  description = "Use preemptible instances for master nodes (not recommended for production)"
  type        = bool
  default     = false
}