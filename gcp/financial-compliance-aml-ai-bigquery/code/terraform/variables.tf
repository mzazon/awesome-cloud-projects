# Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 6 && can(regex("^[a-z0-9-]+$", var.project_id))
    error_message = "Project ID must be at least 6 characters and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region where resources will be created"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "europe-west1", 
      "europe-west2", "asia-east1", "asia-northeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

# BigQuery Configuration
variable "dataset_id" {
  description = "BigQuery dataset ID for AML compliance data"
  type        = string
  default     = "aml_compliance_data"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_id))
    error_message = "Dataset ID must contain only letters, numbers, and underscores."
  }
}

variable "transaction_table_id" {
  description = "BigQuery table ID for transaction data"
  type        = string
  default     = "transactions"
}

variable "alerts_table_id" {
  description = "BigQuery table ID for compliance alerts"
  type        = string
  default     = "compliance_alerts"
}

variable "ml_model_id" {
  description = "BigQuery ML model ID for AML detection"
  type        = string
  default     = "aml_detection_model"
}

# Storage Configuration
variable "storage_bucket_name" {
  description = "Cloud Storage bucket name for compliance reports (will be auto-generated if not provided)"
  type        = string
  default     = ""
}

variable "storage_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "report_retention_days" {
  description = "Number of days to retain compliance reports in Cloud Storage"
  type        = number
  default     = 2555  # 7 years for financial compliance
  validation {
    condition     = var.report_retention_days >= 365 && var.report_retention_days <= 3650
    error_message = "Report retention must be between 1 and 10 years (365-3650 days)."
  }
}

# Pub/Sub Configuration
variable "pubsub_topic_name" {
  description = "Pub/Sub topic name for AML alerts"
  type        = string
  default     = "aml-alerts"
}

variable "pubsub_subscription_name" {
  description = "Pub/Sub subscription name for AML alerts"
  type        = string
  default     = "aml-alerts-subscription"
}

variable "message_retention_duration" {
  description = "How long to retain unacknowledged messages in Pub/Sub (in seconds)"
  type        = string
  default     = "604800s"  # 7 days
}

# Cloud Functions Configuration
variable "alert_function_name" {
  description = "Name for the AML alert processing Cloud Function"
  type        = string
  default     = "process-aml-alerts"
}

variable "report_function_name" {
  description = "Name for the compliance report generation Cloud Function"
  type        = string
  default     = "compliance-report-generator"
}

variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "alert_function_memory" {
  description = "Memory allocation for alert processing function in MB"
  type        = number
  default     = 256
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.alert_function_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "report_function_memory" {
  description = "Memory allocation for report generation function in MB"
  type        = number
  default     = 512
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.report_function_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

# Cloud Scheduler Configuration
variable "scheduler_job_name" {
  description = "Name for the Cloud Scheduler job"
  type        = string
  default     = "daily-compliance-report"
}

variable "report_schedule" {
  description = "Cron schedule for compliance report generation"
  type        = string
  default     = "0 2 * * *"  # Daily at 2 AM
  validation {
    condition     = can(regex("^[0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+$", var.report_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "scheduler_timezone" {
  description = "Timezone for the Cloud Scheduler job"
  type        = string
  default     = "America/New_York"
}

# IAM and Security Configuration
variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Enable versioning for Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable customer-managed encryption for sensitive resources"
  type        = bool
  default     = true
}

# Monitoring and Logging Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain Cloud Function logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Tagging and Organization
variable "environment" {
  description = "Environment designation (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition = contains([
      "dev", "development", "staging", "stage", "prod", "production"
    ], var.environment)
    error_message = "Environment must be one of: dev, development, staging, stage, prod, production."
  }
}

variable "cost_center" {
  description = "Cost center for resource billing and organization"
  type        = string
  default     = "compliance"
}

variable "business_unit" {
  description = "Business unit responsible for the resources"
  type        = string
  default     = "risk-management"
}

# Sample Data Configuration
variable "load_sample_data" {
  description = "Whether to load sample transaction data for testing"
  type        = bool
  default     = true
}

variable "create_ml_model" {
  description = "Whether to create the BigQuery ML model automatically"
  type        = bool
  default     = true
}

# API Configuration
variable "enable_apis" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "bigquery.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com"
  ]
}