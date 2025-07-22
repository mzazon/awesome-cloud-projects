# Project and region configuration
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
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for resource deployment"
  type        = string
  default     = "us-central1-a"
}

# Resource naming configuration
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "ml-features"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# BigQuery configuration
variable "dataset_name" {
  description = "Name for the BigQuery dataset containing feature tables"
  type        = string
  default     = "feature_dataset"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_name))
    error_message = "Dataset name must contain only letters, numbers, and underscores."
  }
}

variable "feature_table_name" {
  description = "Name for the BigQuery table containing computed features"
  type        = string
  default     = "user_features"
}

variable "raw_events_table_name" {
  description = "Name for the BigQuery table containing raw event data"
  type        = string
  default     = "raw_user_events"
}

variable "dataset_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "asia-east1", "asia-northeast1", "asia-southeast1",
      "australia-southeast1", "europe-north1", "europe-west2", "europe-west3",
      "europe-west4", "europe-west6", "us-central1", "us-east1", "us-east4",
      "us-west1", "us-west2", "us-west3", "us-west4"
    ], var.dataset_location)
    error_message = "Dataset location must be a valid BigQuery location."
  }
}

# Cloud Batch configuration
variable "batch_job_name" {
  description = "Name for the Cloud Batch job"
  type        = string
  default     = "feature-pipeline"
}

variable "batch_machine_type" {
  description = "Machine type for Cloud Batch job"
  type        = string
  default     = "e2-standard-2"
  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "e2-standard-8", "e2-standard-16", "n1-standard-1", "n1-standard-2",
      "n1-standard-4", "n1-standard-8", "n2-standard-2", "n2-standard-4"
    ], var.batch_machine_type)
    error_message = "Machine type must be a valid GCP machine type."
  }
}

variable "batch_cpu_milli" {
  description = "CPU allocation in milliCPU for batch job (1000 = 1 CPU)"
  type        = number
  default     = 2000
  validation {
    condition     = var.batch_cpu_milli >= 1000 && var.batch_cpu_milli <= 8000
    error_message = "CPU allocation must be between 1000 and 8000 milliCPU."
  }
}

variable "batch_memory_mib" {
  description = "Memory allocation in MiB for batch job"
  type        = number
  default     = 4096
  validation {
    condition     = var.batch_memory_mib >= 1024 && var.batch_memory_mib <= 16384
    error_message = "Memory allocation must be between 1024 and 16384 MiB."
  }
}

variable "batch_max_retry_count" {
  description = "Maximum retry count for batch job tasks"
  type        = number
  default     = 3
  validation {
    condition     = var.batch_max_retry_count >= 0 && var.batch_max_retry_count <= 10
    error_message = "Max retry count must be between 0 and 10."
  }
}

variable "batch_max_run_duration" {
  description = "Maximum run duration for batch job in seconds"
  type        = string
  default     = "3600s"
}

# Pub/Sub configuration
variable "pubsub_topic_name" {
  description = "Name for the Pub/Sub topic triggering feature updates"
  type        = string
  default     = "feature-updates"
}

variable "pubsub_subscription_name" {
  description = "Name for the Pub/Sub subscription"
  type        = string
  default     = "feature-pipeline-sub"
}

variable "message_retention_duration" {
  description = "Message retention duration for Pub/Sub topic"
  type        = string
  default     = "604800s" # 7 days
}

# Vertex AI Feature Store configuration
variable "feature_group_name" {
  description = "Name for the Vertex AI Feature Group"
  type        = string
  default     = "user-feature-group"
}

variable "online_store_name" {
  description = "Name for the Vertex AI Online Store"
  type        = string
  default     = "user-features-store"
}

variable "feature_view_name" {
  description = "Name for the Vertex AI Feature View"
  type        = string
  default     = "user-feature-view"
}

variable "feature_sync_cron" {
  description = "Cron schedule for feature synchronization (every 6 hours by default)"
  type        = string
  default     = "0 */6 * * *"
}

# Cloud Storage configuration
variable "bucket_name" {
  description = "Name for the Cloud Storage bucket (will be prefixed with project ID)"
  type        = string
  default     = "ml-features-bucket"
}

variable "bucket_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "bucket_storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE", "REGIONAL", "MULTI_REGIONAL"
    ], var.bucket_storage_class)
    error_message = "Storage class must be a valid Cloud Storage class."
  }
}

# Cloud Function configuration
variable "function_name" {
  description = "Name for the Cloud Function"
  type        = string
  default     = "trigger-feature-pipeline"
}

variable "function_runtime" {
  description = "Runtime for Cloud Function"
  type        = string
  default     = "python39"
  validation {
    condition = contains([
      "python37", "python38", "python39", "python310", "python311",
      "nodejs16", "nodejs18", "nodejs20", "go119", "go120", "go121"
    ], var.function_runtime)
    error_message = "Runtime must be a supported Cloud Functions runtime."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 256
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Memory must be a valid Cloud Functions memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

# IAM and security configuration
variable "enable_apis" {
  description = "Whether to enable required GCP APIs"
  type        = bool
  default     = true
}

variable "create_service_accounts" {
  description = "Whether to create dedicated service accounts for resources"
  type        = bool
  default     = true
}

# Monitoring and logging configuration
variable "enable_logging" {
  description = "Whether to enable comprehensive logging for all resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Resource labeling
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "demo"
    purpose     = "ml-feature-engineering"
    recipe      = "real-time-ml-features"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}