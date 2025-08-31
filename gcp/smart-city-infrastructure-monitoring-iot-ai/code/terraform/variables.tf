# Input variables for Smart City Infrastructure Monitoring with IoT and AI
# These variables allow customization of the infrastructure deployment

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 6 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must be at least 6 characters and follow GCP naming conventions."
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
      "asia-east1", "asia-east2", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for resource deployment"
  type        = string
  default     = "us-central1-a"
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

# Resource naming variables
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "smart-city"
  validation {
    condition     = length(var.resource_prefix) <= 20 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must be lowercase, start with a letter, and be 20 characters or less."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 8
    error_message = "Random suffix length must be between 4 and 8 characters."
  }
}

# Pub/Sub configuration
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topics (in seconds)"
  type        = string
  default     = "604800s" # 7 days
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscriptions"
  type        = number
  default     = 60
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

variable "pubsub_max_retry_delay" {
  description = "Maximum retry delay for failed messages (in seconds)"
  type        = string
  default     = "300s"
}

# BigQuery configuration
variable "bigquery_location" {
  description = "Location for BigQuery dataset (should match region for optimal performance)"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "asia-east1", "asia-northeast1"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid region or multi-region."
  }
}

variable "bigquery_table_expiration_ms" {
  description = "Table expiration time in milliseconds (null for no expiration)"
  type        = number
  default     = null
}

variable "bigquery_partition_expiration_ms" {
  description = "Partition expiration time in milliseconds"
  type        = number
  default     = 7776000000 # 90 days
}

# Cloud Storage configuration
variable "storage_class" {
  description = "Default storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "enable_storage_versioning" {
  description = "Enable versioning for Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "storage_lifecycle_age_days" {
  description = "Number of days after which to apply lifecycle rules"
  type        = number
  default     = 30
  validation {
    condition     = var.storage_lifecycle_age_days >= 1 && var.storage_lifecycle_age_days <= 365
    error_message = "Storage lifecycle age must be between 1 and 365 days."
  }
}

# Cloud Function configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312",
      "nodejs18", "nodejs20", "go119", "go121"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported runtime version."
  }
}

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Functions (in seconds)"
  type        = number
  default     = 120
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 100
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

# Vertex AI configuration
variable "vertex_ai_region" {
  description = "Region for Vertex AI resources (must support Vertex AI)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west4", "asia-east1", "asia-northeast1"
    ], var.vertex_ai_region)
    error_message = "Vertex AI region must support Vertex AI services."
  }
}

variable "enable_vertex_ai_logging" {
  description = "Enable detailed logging for Vertex AI operations"
  type        = bool
  default     = true
}

# Monitoring configuration
variable "notification_channels" {
  description = "List of notification channel names for alerting"
  type        = list(string)
  default     = []
}

variable "alert_policy_enabled" {
  description = "Enable alert policies for monitoring"
  type        = bool
  default     = true
}

variable "dashboard_enabled" {
  description = "Create monitoring dashboards"
  type        = bool
  default     = true
}

# Security configuration
variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_public_access_prevention" {
  description = "Enable public access prevention for Cloud Storage"
  type        = bool
  default     = true
}

variable "service_account_display_name" {
  description = "Display name for the IoT service account"
  type        = string
  default     = "Smart City IoT Sensors"
}

# Cost optimization variables
variable "enable_cost_optimization" {
  description = "Enable cost optimization features (preemptible instances, etc.)"
  type        = bool
  default     = true
}

variable "budget_amount" {
  description = "Monthly budget amount in USD (set to 0 to disable budget alerts)"
  type        = number
  default     = 100
  validation {
    condition     = var.budget_amount >= 0
    error_message = "Budget amount must be non-negative."
  }
}

# Network configuration
variable "enable_private_google_access" {
  description = "Enable Private Google Access for enhanced security"
  type        = bool
  default     = true
}

# Data retention policies
variable "log_retention_days" {
  description = "Number of days to retain Cloud Logging data"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# API enablement
variable "apis_to_enable" {
  description = "List of APIs to enable for the project"
  type        = list(string)
  default = [
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "aiplatform.googleapis.com",
    "monitoring.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com"
  ]
}

# Tags for resource organization
variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for k, v in var.additional_labels : can(regex("^[a-z][a-z0-9_-]*$", k))])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}