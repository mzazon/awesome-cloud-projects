# Variables for AI-Powered Cost Analytics with BigQuery Analytics Hub and Vertex AI
# This file defines all configurable parameters for the infrastructure deployment

variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

variable "dataset_id" {
  description = "BigQuery dataset ID for cost analytics data"
  type        = string
  default     = "cost_analytics"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_id))
    error_message = "Dataset ID must contain only letters, numbers, and underscores."
  }
}

variable "exchange_id" {
  description = "Analytics Hub data exchange ID"
  type        = string
  default     = "cost_data_exchange"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.exchange_id))
    error_message = "Exchange ID must contain only letters, numbers, and underscores."
  }
}

variable "model_name" {
  description = "Base name for the Vertex AI cost prediction model"
  type        = string
  default     = "cost-prediction-model"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.model_name))
    error_message = "Model name must contain only letters, numbers, and hyphens."
  }
}

variable "endpoint_name" {
  description = "Base name for the Vertex AI prediction endpoint"
  type        = string
  default     = "cost-prediction-endpoint"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.endpoint_name))
    error_message = "Endpoint name must contain only letters, numbers, and hyphens."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for Cloud Storage bucket name (suffix will be auto-generated)"
  type        = string
  default     = "cost-analytics-data"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_class" {
  description = "Cloud Storage class for the model artifacts bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs automatically"
  type        = bool
  default     = true
}

variable "bigquery_location" {
  description = "Location for BigQuery datasets (can be region or multi-region)"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid region or multi-region."
  }
}

variable "vertex_ai_machine_type" {
  description = "Machine type for Vertex AI endpoint deployment"
  type        = string
  default     = "n1-standard-2"
  validation {
    condition = contains([
      "n1-standard-2", "n1-standard-4", "n1-standard-8",
      "n1-highmem-2", "n1-highmem-4", "n1-highmem-8",
      "n2-standard-2", "n2-standard-4", "n2-standard-8"
    ], var.vertex_ai_machine_type)
    error_message = "Machine type must be a valid Compute Engine machine type."
  }
}

variable "min_replica_count" {
  description = "Minimum number of replicas for Vertex AI endpoint"
  type        = number
  default     = 1
  validation {
    condition     = var.min_replica_count >= 1 && var.min_replica_count <= 10
    error_message = "Minimum replica count must be between 1 and 10."
  }
}

variable "max_replica_count" {
  description = "Maximum number of replicas for Vertex AI endpoint"
  type        = number
  default     = 3
  validation {
    condition     = var.max_replica_count >= 1 && var.max_replica_count <= 100
    error_message = "Maximum replica count must be between 1 and 100."
  }
}

variable "sample_data_rows" {
  description = "Number of sample billing data rows to generate"
  type        = number
  default     = 1000
  validation {
    condition     = var.sample_data_rows >= 100 && var.sample_data_rows <= 10000
    error_message = "Sample data rows must be between 100 and 10000."
  }
}

variable "anomaly_threshold" {
  description = "Threshold for cost anomaly detection alerts"
  type        = number
  default     = 2.0
  validation {
    condition     = var.anomaly_threshold > 0 && var.anomaly_threshold <= 5.0
    error_message = "Anomaly threshold must be between 0 and 5.0."
  }
}

variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for cost anomaly notifications (optional)"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    team        = "analytics"
    purpose     = "cost-optimization"
    managed-by  = "terraform"
  }
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Maximum of 64 labels are allowed."
  }
}

variable "force_destroy" {
  description = "Allow deletion of non-empty buckets and datasets when destroying infrastructure"
  type        = bool
  default     = false
}