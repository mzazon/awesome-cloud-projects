# Variables for QA Workflows Infrastructure
# These variables allow customization of the deployment while maintaining security and best practices

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources (Cloud Functions, Cloud Run, etc.)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region with full service support."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone cannot be empty."
  }
}

variable "environment" {
  description = "Environment name for resource labeling (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "app_engine_location" {
  description = "App Engine application location (required for Cloud Tasks). Note: This cannot be changed after creation."
  type        = string
  default     = "us-central"
  validation {
    condition = contains([
      "us-central", "us-east1", "us-east4", "us-west2", "us-west3", "us-west4",
      "europe-west", "europe-west2", "europe-west3", "europe-west6",
      "asia-northeast1", "asia-south1", "australia-southeast1"
    ], var.app_engine_location)
    error_message = "App Engine location must be a valid region identifier."
  }
}

variable "firestore_location" {
  description = "Firestore database location. Choose based on your primary user base for optimal performance."
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or regional location."
  }
}

variable "dashboard_image" {
  description = "Container image for the QA Dashboard Cloud Run service"
  type        = string
  default     = "gcr.io/cloudrun/hello"
  validation {
    condition     = length(var.dashboard_image) > 0
    error_message = "Dashboard image cannot be empty."
  }
}

variable "notification_channels" {
  description = "List of notification channel IDs for monitoring alerts. Create these in Cloud Monitoring first."
  type        = list(string)
  default     = []
  validation {
    condition     = length(var.notification_channels) <= 16
    error_message = "Maximum of 16 notification channels allowed per alert policy."
  }
}

variable "enable_apis_automatically" {
  description = "Whether to automatically enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "task_queue_max_concurrent_dispatches" {
  description = "Maximum number of concurrent task dispatches for the main orchestration queue"
  type        = number
  default     = 10
  validation {
    condition     = var.task_queue_max_concurrent_dispatches >= 1 && var.task_queue_max_concurrent_dispatches <= 1000
    error_message = "Max concurrent dispatches must be between 1 and 1000."
  }
}

variable "task_queue_max_retry_duration" {
  description = "Maximum retry duration for tasks in seconds"
  type        = string
  default     = "3600s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.task_queue_max_retry_duration))
    error_message = "Retry duration must be in seconds format (e.g., '3600s')."
  }
}

variable "cloud_function_timeout" {
  description = "Timeout for Cloud Functions in seconds (max 540 for HTTP functions)"
  type        = number
  default     = 540
  validation {
    condition     = var.cloud_function_timeout >= 1 && var.cloud_function_timeout <= 540
    error_message = "Cloud Function timeout must be between 1 and 540 seconds."
  }
}

variable "cloud_function_memory" {
  description = "Memory allocation for Cloud Functions (128M, 256M, 512M, 1G, 2G, 4G, 8G)"
  type        = string
  default     = "256M"
  validation {
    condition = contains([
      "128M", "256M", "512M", "1G", "2G", "4G", "8G"
    ], var.cloud_function_memory)
    error_message = "Memory must be one of: 128M, 256M, 512M, 1G, 2G, 4G, 8G."
  }
}

variable "cloud_function_max_instances" {
  description = "Maximum number of Cloud Function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.cloud_function_max_instances >= 1 && var.cloud_function_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances for the dashboard"
  type        = number
  default     = 10
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "cloud_run_cpu_limit" {
  description = "CPU limit for Cloud Run service (e.g., '1', '2', '4')"
  type        = string
  default     = "1"
  validation {
    condition = contains([
      "0.08", "0.17", "0.25", "0.33", "0.5", "0.58", "0.67", "0.75", "0.83", "1", "1.25", "1.5", "1.75", "2", "2.5", "3", "3.5", "4", "6", "8"
    ], var.cloud_run_cpu_limit)
    error_message = "CPU limit must be a valid Cloud Run CPU value."
  }
}

variable "cloud_run_memory_limit" {
  description = "Memory limit for Cloud Run service (e.g., '512Mi', '1Gi', '2Gi')"
  type        = string
  default     = "1Gi"
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.cloud_run_memory_limit))
    error_message = "Memory limit must be in format like '512Mi' or '2Gi'."
  }
}

variable "storage_lifecycle_nearline_age" {
  description = "Age in days after which objects transition to Nearline storage class"
  type        = number
  default     = 30
  validation {
    condition     = var.storage_lifecycle_nearline_age >= 1
    error_message = "Nearline age must be at least 1 day."
  }
}

variable "storage_lifecycle_coldline_age" {
  description = "Age in days after which objects transition to Coldline storage class"
  type        = number
  default     = 90
  validation {
    condition     = var.storage_lifecycle_coldline_age >= var.storage_lifecycle_nearline_age
    error_message = "Coldline age must be greater than or equal to Nearline age."
  }
}

variable "storage_lifecycle_delete_age" {
  description = "Age in days after which objects are automatically deleted"
  type        = number
  default     = 365
  validation {
    condition     = var.storage_lifecycle_delete_age >= var.storage_lifecycle_coldline_age
    error_message = "Delete age must be greater than or equal to Coldline age."
  }
}

variable "bigquery_location" {
  description = "BigQuery dataset location (US, EU, or specific region)"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-west1", "us-west2", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-northeast2", "asia-northeast3", "asia-south1", "asia-southeast1", "asia-southeast2",
      "australia-southeast1"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid region or multi-region."
  }
}

variable "monitoring_alert_duration" {
  description = "Duration for monitoring alert conditions in seconds"
  type        = string
  default     = "300s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.monitoring_alert_duration))
    error_message = "Alert duration must be in seconds format (e.g., '300s')."
  }
}

variable "monitoring_alert_threshold" {
  description = "Threshold value for QA workflow failure alerts"
  type        = number
  default     = 5
  validation {
    condition     = var.monitoring_alert_threshold >= 1
    error_message = "Alert threshold must be at least 1."
  }
}

variable "vertex_ai_region" {
  description = "Vertex AI region for ML workloads"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.vertex_ai_region)
    error_message = "Vertex AI region must support AI Platform services."
  }
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage buckets (recommended for security)"
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Enable object versioning for Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "firestore_rules_file" {
  description = "Path to custom Firestore security rules file (optional)"
  type        = string
  default     = ""
}

variable "custom_labels" {
  description = "Custom labels to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition     = length(var.custom_labels) <= 64
    error_message = "Maximum of 64 custom labels allowed."
  }
}