# Variables for BigQuery Query Optimization Infrastructure
# This file defines all configurable parameters for the solution

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
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
      "asia-east1", "asia-southeast1", "asia-northeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone within the region"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "Environment must be lowercase alphanumeric with hyphens."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "bq-opt"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must be lowercase alphanumeric with hyphens."
  }
}

# BigQuery Configuration
variable "dataset_name" {
  description = "Name of the BigQuery dataset for analytics"
  type        = string
  default     = "optimization_analytics"
}

variable "dataset_location" {
  description = "Location for BigQuery dataset (must be compatible with region)"
  type        = string
  default     = "US"
}

variable "dataset_description" {
  description = "Description for the BigQuery dataset"
  type        = string
  default     = "Query optimization analytics dataset with performance monitoring and recommendations"
}

variable "sample_data_size" {
  description = "Number of sample records to generate for testing (thousands)"
  type        = number
  default     = 100
  validation {
    condition     = var.sample_data_size >= 10 && var.sample_data_size <= 1000
    error_message = "Sample data size must be between 10 and 1000 thousand records."
  }
}

# Cloud Composer Configuration
variable "composer_environment_name" {
  description = "Name of the Cloud Composer environment"
  type        = string
  default     = "query-optimizer"
}

variable "composer_node_count" {
  description = "Number of nodes in the Composer environment"
  type        = number
  default     = 3
  validation {
    condition     = var.composer_node_count >= 3 && var.composer_node_count <= 10
    error_message = "Composer node count must be between 3 and 10."
  }
}

variable "composer_machine_type" {
  description = "Machine type for Composer nodes"
  type        = string
  default     = "n1-standard-2"
  validation {
    condition = contains([
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n1-standard-8",
      "n2-standard-2", "n2-standard-4", "n2-standard-8"
    ], var.composer_machine_type)
    error_message = "Machine type must be a valid Composer-supported machine type."
  }
}

variable "composer_disk_size" {
  description = "Disk size in GB for Composer nodes"
  type        = number
  default     = 100
  validation {
    condition     = var.composer_disk_size >= 30 && var.composer_disk_size <= 1000
    error_message = "Disk size must be between 30 and 1000 GB."
  }
}

variable "composer_python_version" {
  description = "Python version for Composer environment"
  type        = string
  default     = "3"
  validation {
    condition     = contains(["3"], var.composer_python_version)
    error_message = "Python version must be 3."
  }
}

# Cloud Storage Configuration
variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "bucket_lifecycle_age" {
  description = "Age in days after which objects are deleted"
  type        = number
  default     = 90
  validation {
    condition     = var.bucket_lifecycle_age >= 30 && var.bucket_lifecycle_age <= 365
    error_message = "Lifecycle age must be between 30 and 365 days."
  }
}

# Vertex AI Configuration
variable "vertex_ai_region" {
  description = "Region for Vertex AI training jobs"
  type        = string
  default     = "us-central1"
}

variable "training_machine_type" {
  description = "Machine type for Vertex AI training jobs"
  type        = string
  default     = "n1-standard-4"
}

variable "training_disk_size" {
  description = "Boot disk size for training jobs in GB"
  type        = number
  default     = 100
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring dashboards and alerts"
  type        = bool
  default     = true
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

# Materialized View Configuration
variable "materialized_view_refresh_interval" {
  description = "Refresh interval for materialized views in minutes"
  type        = number
  default     = 60
  validation {
    condition     = var.materialized_view_refresh_interval >= 15 && var.materialized_view_refresh_interval <= 1440
    error_message = "Refresh interval must be between 15 minutes and 24 hours."
  }
}

variable "materialized_view_partition_days" {
  description = "Number of days to partition materialized views"
  type        = number
  default     = 90
  validation {
    condition     = var.materialized_view_partition_days >= 30 && var.materialized_view_partition_days <= 365
    error_message = "Partition days must be between 30 and 365."
  }
}

# Security and IAM Configuration
variable "create_service_accounts" {
  description = "Whether to create dedicated service accounts for each component"
  type        = bool
  default     = true
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

# Cost Management
variable "enable_cost_controls" {
  description = "Enable cost control measures like table expiration"
  type        = bool
  default     = true
}

variable "table_expiration_days" {
  description = "Days after which temporary tables expire"
  type        = number
  default     = 7
  validation {
    condition     = var.table_expiration_days >= 1 && var.table_expiration_days <= 30
    error_message = "Table expiration must be between 1 and 30 days."
  }
}

# Tags and Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    project     = "query-optimization"
    managed-by  = "terraform"
  }
}