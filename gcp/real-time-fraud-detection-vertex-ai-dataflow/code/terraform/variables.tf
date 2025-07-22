# Project and regional configuration variables
variable "project_id" {
  description = "The Google Cloud project ID"
  type        = string
  validation {
    condition     = length(var.project_id) > 6 && can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone."
  }
}

# Fraud detection system configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "fraud_detection_system_name" {
  description = "Name prefix for fraud detection system resources"
  type        = string
  default     = "fraud-detection"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.fraud_detection_system_name))
    error_message = "System name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with alphanumeric character."
  }
}

# BigQuery configuration
variable "bigquery_dataset_id" {
  description = "BigQuery dataset ID for fraud detection data"
  type        = string
  default     = "fraud_detection"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.bigquery_dataset_id))
    error_message = "Dataset ID must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "bigquery_dataset_description" {
  description = "Description for the BigQuery dataset"
  type        = string
  default     = "Fraud detection analytics dataset for transaction processing and alerting"
}

variable "bigquery_table_expiration_ms" {
  description = "Table expiration time in milliseconds (null for no expiration)"
  type        = number
  default     = null
}

# Pub/Sub configuration
variable "pubsub_topic_name" {
  description = "Name for the Pub/Sub topic for transaction streams"
  type        = string
  default     = "transaction-stream"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-_]*$", var.pubsub_topic_name))
    error_message = "Topic name must start with a letter and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "pubsub_subscription_name" {
  description = "Name for the Pub/Sub subscription for processing"
  type        = string
  default     = "fraud-processor"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-_]*$", var.pubsub_subscription_name))
    error_message = "Subscription name must start with a letter and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub subscription (e.g., '7d', '24h')"
  type        = string
  default     = "7d"
  validation {
    condition     = can(regex("^[0-9]+[dhms]$", var.pubsub_message_retention_duration))
    error_message = "Duration must be a number followed by d (days), h (hours), m (minutes), or s (seconds)."
  }
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline in seconds for Pub/Sub subscription"
  type        = number
  default     = 60
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

variable "pubsub_max_delivery_attempts" {
  description = "Maximum delivery attempts for Pub/Sub subscription"
  type        = number
  default     = 5
  validation {
    condition     = var.pubsub_max_delivery_attempts >= 1 && var.pubsub_max_delivery_attempts <= 100
    error_message = "Max delivery attempts must be between 1 and 100."
  }
}

# Cloud Storage configuration
variable "storage_bucket_name" {
  description = "Name for the Cloud Storage bucket (will be prefixed with project ID)"
  type        = string
  default     = "fraud-ml-artifacts"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_]*[a-z0-9]$", var.storage_bucket_name))
    error_message = "Bucket name must start and end with alphanumeric characters and contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

variable "storage_bucket_location" {
  description = "Location for the Cloud Storage bucket"
  type        = string
  default     = "US"
  validation {
    condition = contains(["US", "EU", "ASIA"], var.storage_bucket_location)
    error_message = "Bucket location must be one of: US, EU, ASIA."
  }
}

variable "storage_bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable object versioning for the Cloud Storage bucket"
  type        = bool
  default     = true
}

# Vertex AI configuration
variable "vertex_ai_region" {
  description = "Region for Vertex AI resources (may differ from general region)"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.vertex_ai_region))
    error_message = "Vertex AI region must be a valid Google Cloud region."
  }
}

variable "vertex_ai_dataset_display_name" {
  description = "Display name for the Vertex AI dataset"
  type        = string
  default     = "Fraud Detection Dataset"
}

variable "vertex_ai_model_display_name" {
  description = "Display name for the Vertex AI model"
  type        = string
  default     = "Fraud Detection Model"
}

variable "vertex_ai_endpoint_display_name" {
  description = "Display name for the Vertex AI endpoint"
  type        = string
  default     = "Fraud Detection Endpoint"
}

variable "vertex_ai_training_budget_hours" {
  description = "Training budget in milli node hours for AutoML (1000 = 1 hour)"
  type        = number
  default     = 2000
  validation {
    condition     = var.vertex_ai_training_budget_hours >= 1000 && var.vertex_ai_training_budget_hours <= 100000
    error_message = "Training budget must be between 1000 and 100000 milli node hours."
  }
}

# Dataflow configuration
variable "dataflow_job_name" {
  description = "Name for the Dataflow job"
  type        = string
  default     = "fraud-detection-pipeline"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.dataflow_job_name))
    error_message = "Job name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with alphanumeric character."
  }
}

variable "dataflow_max_workers" {
  description = "Maximum number of Dataflow workers"
  type        = number
  default     = 10
  validation {
    condition     = var.dataflow_max_workers >= 1 && var.dataflow_max_workers <= 1000
    error_message = "Max workers must be between 1 and 1000."
  }
}

variable "dataflow_machine_type" {
  description = "Machine type for Dataflow workers"
  type        = string
  default     = "n1-standard-2"
  validation {
    condition = can(regex("^(n1|n2|e2|c2)-(standard|highmem|highcpu)-[0-9]+$", var.dataflow_machine_type))
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

# IAM and security configuration
variable "create_service_accounts" {
  description = "Whether to create dedicated service accounts for each service"
  type        = bool
  default     = true
}

variable "enable_audit_logging" {
  description = "Enable audit logging for fraud detection resources"
  type        = bool
  default     = true
}

# Monitoring configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for fraud detection system"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for fraud detection alerts (optional)"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Resource labeling
variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    "application" = "fraud-detection"
    "managed-by"  = "terraform"
    "purpose"     = "real-time-analytics"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with a letter and both keys and values can only contain lowercase letters, numbers, underscores, and hyphens."
  }
}

# Cost optimization settings
variable "enable_cost_optimization" {
  description = "Enable cost optimization features (preemptible instances, etc.)"
  type        = bool
  default     = true
}

variable "auto_delete_resources_after_days" {
  description = "Number of days after which to auto-delete temporary resources (0 to disable)"
  type        = number
  default     = 7
  validation {
    condition     = var.auto_delete_resources_after_days >= 0 && var.auto_delete_resources_after_days <= 365
    error_message = "Auto-delete period must be between 0 and 365 days."
  }
}

# API configuration
variable "required_apis" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "aiplatform.googleapis.com",
    "bigquery.googleapis.com",
    "compute.googleapis.com",
    "dataflow.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com"
  ]
}

variable "disable_dependent_services" {
  description = "Whether to disable dependent services when destroying APIs"
  type        = bool
  default     = false
}