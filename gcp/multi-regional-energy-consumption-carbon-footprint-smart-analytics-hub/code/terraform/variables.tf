# Variables for multi-regional energy consumption carbon footprint analytics solution

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "primary_region" {
  description = "Primary GCP region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.primary_region)
    error_message = "Primary region must be a valid GCP region."
  }
}

variable "analytics_regions" {
  description = "List of regions for multi-regional carbon analytics"
  type        = list(string)
  default     = ["us-central1", "europe-west1", "asia-northeast1"]
  validation {
    condition     = length(var.analytics_regions) >= 2
    error_message = "At least 2 regions must be specified for multi-regional analytics."
  }
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

variable "dataset_location" {
  description = "Location for BigQuery datasets (US, EU, or specific region)"
  type        = string
  default     = "US"
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "carbon_optimization_schedule" {
  description = "Cron schedule for carbon optimization (Cloud Scheduler format)"
  type        = string
  default     = "0 */2 * * *"
  validation {
    condition     = can(regex("^[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+$", var.carbon_optimization_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "renewable_optimization_schedule" {
  description = "Cron schedule for renewable energy optimization (Cloud Scheduler format)"
  type        = string
  default     = "0 14 * * *"
}

variable "carbon_intensity_threshold" {
  description = "Carbon intensity threshold for triggering workload migration (kg CO2e/kWh)"
  type        = number
  default     = 0.5
  validation {
    condition     = var.carbon_intensity_threshold > 0 && var.carbon_intensity_threshold <= 1.0
    error_message = "Carbon intensity threshold must be between 0 and 1.0."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (MB)"
  type        = number
  default     = 512
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (seconds)"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "analytics_hub_description" {
  description = "Description for the Analytics Hub data exchange"
  type        = string
  default     = "Shared carbon footprint and energy optimization data for sustainability initiatives"
}

variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_workload_migration" {
  description = "Whether to deploy workload migration automation"
  type        = bool
  default     = true
}

variable "migration_topic_name" {
  description = "Pub/Sub topic name for workload migration triggers"
  type        = string
  default     = "carbon-optimization-trigger"
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "carbon-optimization"
    managed-by  = "terraform"
    solution    = "energy-analytics"
  }
}

variable "bigquery_table_expiration_ms" {
  description = "Table expiration time in milliseconds (null for no expiration)"
  type        = number
  default     = null
}

variable "function_source_bucket" {
  description = "Name of the Cloud Storage bucket for function source code (if null, will be created)"
  type        = string
  default     = null
}

variable "retention_days" {
  description = "Data retention period in days for analytics data"
  type        = number
  default     = 90
  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 365
    error_message = "Retention days must be between 1 and 365."
  }
}

variable "enable_cross_region_replication" {
  description = "Whether to enable cross-region data replication for disaster recovery"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for carbon optimization alerts (optional)"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}