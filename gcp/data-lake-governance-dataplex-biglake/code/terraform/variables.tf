# Variable definitions for GCP Data Lake Governance with Dataplex and BigLake
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone within the specified region"
  type        = string
  default     = ""
}

variable "lake_name" {
  description = "Name for the Dataplex lake"
  type        = string
  default     = "enterprise-data-lake"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.lake_name))
    error_message = "Lake name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens (max 63 characters)."
  }
}

variable "zone_name" {
  description = "Name for the Dataplex zone within the lake"
  type        = string
  default     = "raw-data-zone"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.zone_name))
    error_message = "Zone name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens (max 63 characters)."
  }
}

variable "dataset_name" {
  description = "Name for the BigQuery dataset for analytics"
  type        = string
  default     = "governance_analytics"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{1,1024}$", var.dataset_name))
    error_message = "Dataset name must contain only alphanumeric characters and underscores (max 1024 characters)."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (will be suffixed with random string)"
  type        = string
  default     = "governance-demo"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must be 3-63 characters, start and end with alphanumeric, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "connection_name_prefix" {
  description = "Prefix for the BigQuery connection name (will be suffixed with random string)"
  type        = string
  default     = "biglake-connection"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,60}$", var.connection_name_prefix))
    error_message = "Connection name prefix must be 1-60 characters and contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "function_name" {
  description = "Name for the Cloud Function for governance monitoring"
  type        = string
  default     = "governance-monitor"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.function_name))
    error_message = "Function name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens (max 63 characters)."
  }
}

variable "asset_name" {
  description = "Name for the Dataplex asset"
  type        = string
  default     = "governance-bucket-asset"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.asset_name))
    error_message = "Asset name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens (max 63 characters)."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "create_sample_data" {
  description = "Whether to create and upload sample data files"
  type        = bool
  default     = true
}

variable "function_source_archive_bucket" {
  description = "Cloud Storage bucket for storing Cloud Function source code archive"
  type        = string
  default     = ""
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "demo"
    project     = "data-governance"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens (max 63 characters)."
  }
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}