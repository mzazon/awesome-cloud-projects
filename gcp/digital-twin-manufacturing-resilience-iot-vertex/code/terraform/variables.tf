# Variables for GCP Digital Twin Manufacturing Resilience Infrastructure
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for resource deployment"
  type        = string
  default     = "us-central1-a"
}

variable "dataset_name" {
  description = "BigQuery dataset name for manufacturing data"
  type        = string
  default     = "manufacturing_data"
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

variable "bigquery_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "US"
}

variable "vertex_ai_region" {
  description = "Region for Vertex AI resources"
  type        = string
  default     = "us-central1"
}

variable "cloud_function_memory" {
  description = "Memory allocation for Cloud Function (MB)"
  type        = number
  default     = 256
  validation {
    condition     = var.cloud_function_memory >= 128 && var.cloud_function_memory <= 8192
    error_message = "Cloud Function memory must be between 128MB and 8192MB."
  }
}

variable "cloud_function_timeout" {
  description = "Timeout for Cloud Function (seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.cloud_function_timeout >= 1 && var.cloud_function_timeout <= 540
    error_message = "Cloud Function timeout must be between 1 and 540 seconds."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "labels" {
  description = "A map of labels to apply to resources"
  type        = map(string)
  default = {
    project     = "digital-twin-manufacturing"
    environment = "dev"
    managed-by  = "terraform"
  }
}

variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topics"
  type        = string
  default     = "86400s" # 24 hours
}

variable "bigquery_table_expiration_ms" {
  description = "Table expiration time in milliseconds (null for no expiration)"
  type        = number
  default     = null
}

variable "storage_lifecycle_rules" {
  description = "Lifecycle rules for Cloud Storage bucket"
  type = object({
    enabled = bool
    action = object({
      type          = string
      storage_class = string
    })
    condition = object({
      age = number
    })
  })
  default = {
    enabled = true
    action = {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition = {
      age = 30
    }
  }
}

variable "monitoring_dashboard_enabled" {
  description = "Whether to create monitoring dashboard"
  type        = bool
  default     = true
}

variable "vertex_ai_dataset_display_name" {
  description = "Display name for Vertex AI dataset"
  type        = string
  default     = "manufacturing-failure-prediction"
}