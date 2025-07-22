# Variables for GCP Data Migration Workflows with Storage Bucket Relocation and Eventarc

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must be a valid GCP project identifier (lowercase letters, numbers, and hyphens only)."
  }
}

variable "region" {
  description = "The GCP region for regional resources like Cloud Functions"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "us-east4", "us-south1", "europe-west1", "europe-west2", "europe-west3",
      "europe-west4", "europe-west6", "europe-north1", "asia-east1", "asia-east2",
      "asia-northeast1", "asia-northeast2", "asia-northeast3", "asia-south1",
      "asia-southeast1", "asia-southeast2", "australia-southeast1", "australia-southeast2",
      "southamerica-east1", "northamerica-northeast1", "northamerica-northeast2"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "source_region" {
  description = "The GCP region for the source storage bucket"
  type        = string
  default     = "us-west1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "us-east4", "us-south1", "europe-west1", "europe-west2", "europe-west3",
      "europe-west4", "europe-west6", "europe-north1", "asia-east1", "asia-east2",
      "asia-northeast1", "asia-northeast2", "asia-northeast3", "asia-south1",
      "asia-southeast1", "asia-southeast2", "australia-southeast1", "australia-southeast2",
      "southamerica-east1", "northamerica-northeast1", "northamerica-northeast2"
    ], var.source_region)
    error_message = "Source region must be a valid GCP region."
  }
}

variable "destination_region" {
  description = "The GCP region for the destination storage bucket"
  type        = string
  default     = "us-east1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "us-east4", "us-south1", "europe-west1", "europe-west2", "europe-west3",
      "europe-west4", "europe-west6", "europe-north1", "asia-east1", "asia-east2",
      "asia-northeast1", "asia-northeast2", "asia-northeast3", "asia-south1",
      "asia-southeast1", "asia-southeast2", "australia-southeast1", "australia-southeast2",
      "southamerica-east1", "northamerica-northeast1", "northamerica-northeast2"
    ], var.destination_region)
    error_message = "Destination region must be a valid GCP region."
  }
}

variable "source_bucket_name" {
  description = "Name of the source storage bucket for data migration"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.source_bucket_name)) && length(var.source_bucket_name) >= 3 && length(var.source_bucket_name) <= 63
    error_message = "Bucket name must be 3-63 characters long, contain only lowercase letters, numbers, and hyphens, and start/end with alphanumeric characters."
  }
}

variable "destination_bucket_name" {
  description = "Name of the destination storage bucket for migrated data"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.destination_bucket_name)) && length(var.destination_bucket_name) >= 3 && length(var.destination_bucket_name) <= 63
    error_message = "Bucket name must be 3-63 characters long, contain only lowercase letters, numbers, and hyphens, and start/end with alphanumeric characters."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and organization"
  type        = string
  default     = "migration"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "force_destroy_buckets" {
  description = "Whether to force destroy storage buckets when they contain objects (use with caution)"
  type        = bool
  default     = false
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted objects in storage buckets"
  type        = number
  default     = 30
  
  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention must be between 7 and 90 days."
  }
}

variable "pre_migration_function_source_path" {
  description = "Path to the pre-migration validation function source code zip file"
  type        = string
  default     = "functions/pre-migration-validator.zip"
}

variable "progress_monitor_function_source_path" {
  description = "Path to the migration progress monitor function source code zip file"
  type        = string
  default     = "functions/migration-progress-monitor.zip"
}

variable "post_migration_function_source_path" {
  description = "Path to the post-migration validation function source code zip file"
  type        = string
  default     = "functions/post-migration-validator.zip"
}

variable "enable_bucket_notifications" {
  description = "Whether to enable bucket notifications for real-time event processing"
  type        = bool
  default     = true
}

variable "enable_audit_logging" {
  description = "Whether to enable comprehensive audit logging for migration operations"
  type        = bool
  default     = true
}

variable "enable_monitoring_alerts" {
  description = "Whether to enable Cloud Monitoring alerts for migration events"
  type        = bool
  default     = true
}

variable "function_timeout_seconds" {
  description = "Timeout in seconds for Cloud Functions execution"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 3600
    error_message = "Function timeout must be between 60 and 3600 seconds."
  }
}

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768
    ], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768 MB."
  }
}

variable "bigquery_dataset_location" {
  description = "Location for the BigQuery dataset storing audit logs"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "us-east4", "us-south1", "europe-west1", "europe-west2", "europe-west3",
      "europe-west4", "europe-west6", "europe-north1", "asia-east1", "asia-east2",
      "asia-northeast1", "asia-northeast2", "asia-northeast3", "asia-south1",
      "asia-southeast1", "asia-southeast2", "australia-southeast1", "australia-southeast2"
    ], var.bigquery_dataset_location)
    error_message = "BigQuery dataset location must be a valid location (US, EU, or specific region)."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain audit logs in BigQuery"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

variable "enable_lifecycle_management" {
  description = "Whether to enable lifecycle management policies on storage buckets"
  type        = bool
  default     = true
}

variable "lifecycle_delete_age_days" {
  description = "Age in days after which objects are deleted by lifecycle policy"
  type        = number
  default     = 365
  
  validation {
    condition     = var.lifecycle_delete_age_days >= 1 && var.lifecycle_delete_age_days <= 3653
    error_message = "Lifecycle delete age must be between 1 and 3653 days."
  }
}

variable "nearline_transition_age_days" {
  description = "Age in days after which objects transition to Nearline storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.nearline_transition_age_days >= 1 && var.nearline_transition_age_days <= 3653
    error_message = "Nearline transition age must be between 1 and 3653 days."
  }
}

variable "archive_transition_age_days" {
  description = "Age in days after which objects transition to Archive storage class"
  type        = number
  default     = 365
  
  validation {
    condition     = var.archive_transition_age_days >= 1 && var.archive_transition_age_days <= 3653
    error_message = "Archive transition age must be between 1 and 3653 days."
  }
}

variable "enable_bucket_versioning" {
  description = "Whether to enable object versioning on storage buckets"
  type        = bool
  default     = true
}

variable "enable_uniform_bucket_level_access" {
  description = "Whether to enable uniform bucket-level access for enhanced security"
  type        = bool
  default     = true
}

variable "enable_public_access_prevention" {
  description = "Whether to enable public access prevention on storage buckets"
  type        = bool
  default     = true
}

variable "custom_labels" {
  description = "Custom labels to apply to all created resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.custom_labels : can(regex("^[a-z][a-z0-9_-]*[a-z0-9]$", k))
    ])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "notification_channels" {
  description = "List of notification channel IDs for monitoring alerts"
  type        = list(string)
  default     = []
}

variable "enable_cloud_armor" {
  description = "Whether to enable Cloud Armor protection for Cloud Functions"
  type        = bool
  default     = false
}

variable "enable_vpc_connector" {
  description = "Whether to enable VPC connector for Cloud Functions"
  type        = bool
  default     = false
}

variable "vpc_connector_name" {
  description = "Name of the VPC connector for Cloud Functions (if enabled)"
  type        = string
  default     = ""
}

variable "enable_secrets_manager" {
  description = "Whether to use Secret Manager for sensitive configuration"
  type        = bool
  default     = false
}

variable "enable_cloud_kms" {
  description = "Whether to enable Cloud KMS for bucket encryption"
  type        = bool
  default     = false
}

variable "kms_key_name" {
  description = "Name of the Cloud KMS key for bucket encryption (if enabled)"
  type        = string
  default     = ""
}