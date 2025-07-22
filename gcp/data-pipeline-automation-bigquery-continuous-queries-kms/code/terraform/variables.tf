# Variable definitions for GCP data pipeline automation with BigQuery Continuous Queries and Cloud KMS

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for resources (must support BigQuery Continuous Queries)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must support BigQuery Continuous Queries. Check documentation for current availability."
  }
}

variable "dataset_id" {
  description = "BigQuery dataset ID for streaming analytics"
  type        = string
  default     = "streaming_analytics"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_id))
    error_message = "Dataset ID can only contain letters, numbers, and underscores."
  }
}

variable "keyring_name" {
  description = "Cloud KMS key ring name for data encryption"
  type        = string
  default     = "pipeline-keyring"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.keyring_name))
    error_message = "Key ring name can only contain letters, numbers, underscores, and hyphens."
  }
}

variable "key_name" {
  description = "Cloud KMS key name for data encryption"
  type        = string
  default     = "data-encryption-key"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.key_name))
    error_message = "Key name can only contain letters, numbers, underscores, and hyphens."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topics"
  type        = string
  default     = "604800s" # 7 days
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_message_retention_duration))
    error_message = "Duration must be specified in seconds with 's' suffix (e.g., '604800s')."
  }
}

variable "key_rotation_period" {
  description = "Automatic rotation period for KMS keys"
  type        = string
  default     = "7776000s" # 90 days
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.key_rotation_period))
    error_message = "Duration must be specified in seconds with 's' suffix (e.g., '7776000s')."
  }
}

variable "storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "environment" {
  description = "Environment label for resource tagging"
  type        = string
  default     = "development"
  
  validation {
    condition = contains([
      "development", "staging", "production"
    ], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

variable "continuous_query_enable" {
  description = "Whether to create the BigQuery continuous query"
  type        = bool
  default     = true
}

variable "monitoring_enabled" {
  description = "Enable monitoring and logging resources"
  type        = bool
  default     = true
}

variable "security_audit_schedule" {
  description = "Cron schedule for automated security audits"
  type        = string
  default     = "0 2 * * *" # Daily at 2 AM
  
  validation {
    condition     = can(regex("^([0-9,*/-]+\\s+){4}[0-9,*/-]+$", var.security_audit_schedule))
    error_message = "Schedule must be a valid cron expression (e.g., '0 2 * * *')."
  }
}