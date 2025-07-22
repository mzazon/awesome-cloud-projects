# Variables for Data Governance Workflows Infrastructure

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region where resources will be created"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1, europe-west1)."
  }
}

variable "environment" {
  description = "The environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "organization_domain" {
  description = "The organization domain for BigQuery access control"
  type        = string
  default     = "example.com"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\\.[a-zA-Z]{2,}$", var.organization_domain))
    error_message = "Organization domain must be a valid domain name format."
  }
}

variable "metastore_service_id" {
  description = "The ID of the Dataproc Metastore service to use with Dataplex (optional)"
  type        = string
  default     = null
}

variable "notification_channels" {
  description = "List of notification channel IDs for Cloud Monitoring alerts"
  type        = list(string)
  default     = []
}

variable "data_retention_days" {
  description = "Number of days to retain data in BigQuery tables"
  type        = number
  default     = 90
  validation {
    condition     = var.data_retention_days >= 1 && var.data_retention_days <= 3650
    error_message = "Data retention days must be between 1 and 3650."
  }
}

variable "dlp_scan_frequency" {
  description = "Frequency for DLP scans in seconds (default: weekly)"
  type        = number
  default     = 604800  # 7 days
  validation {
    condition     = var.dlp_scan_frequency >= 3600 && var.dlp_scan_frequency <= 2592000
    error_message = "DLP scan frequency must be between 1 hour (3600s) and 30 days (2592000s)."
  }
}

variable "quality_threshold" {
  description = "Minimum acceptable data quality score (0.0 to 1.0)"
  type        = number
  default     = 0.8
  validation {
    condition     = var.quality_threshold >= 0.0 && var.quality_threshold <= 1.0
    error_message = "Quality threshold must be between 0.0 and 1.0."
  }
}

variable "enable_data_discovery" {
  description = "Enable automatic data discovery in Dataplex zones"
  type        = bool
  default     = true
}

variable "discovery_schedule_raw" {
  description = "Cron schedule for raw data zone discovery (default: every 6 hours)"
  type        = string
  default     = "0 */6 * * *"
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.discovery_schedule_raw))
    error_message = "Discovery schedule must be a valid cron expression."
  }
}

variable "discovery_schedule_curated" {
  description = "Cron schedule for curated data zone discovery (default: every 12 hours)"
  type        = string
  default     = "0 */12 * * *"
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.discovery_schedule_curated))
    error_message = "Discovery schedule must be a valid cron expression."
  }
}

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
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

variable "enable_versioning" {
  description = "Enable versioning for Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable customer-managed encryption for resources"
  type        = bool
  default     = true
}

variable "bigquery_location" {
  description = "Location for BigQuery datasets (can be different from region for multi-region)"
  type        = string
  default     = null
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Labels must follow GCP naming conventions: keys must start with lowercase letter, values can contain lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "dlp_info_types" {
  description = "List of DLP info types to detect in data scanning"
  type        = list(string)
  default = [
    "EMAIL_ADDRESS",
    "PHONE_NUMBER",
    "CREDIT_CARD_NUMBER",
    "US_SOCIAL_SECURITY_NUMBER",
    "PERSON_NAME"
  ]
}

variable "dlp_min_likelihood" {
  description = "Minimum likelihood for DLP findings"
  type        = string
  default     = "POSSIBLE"
  validation {
    condition     = contains(["VERY_UNLIKELY", "UNLIKELY", "POSSIBLE", "LIKELY", "VERY_LIKELY"], var.dlp_min_likelihood)
    error_message = "DLP minimum likelihood must be one of: VERY_UNLIKELY, UNLIKELY, POSSIBLE, LIKELY, VERY_LIKELY."
  }
}

variable "dlp_max_findings" {
  description = "Maximum number of findings per DLP request"
  type        = number
  default     = 1000
  validation {
    condition     = var.dlp_max_findings >= 1 && var.dlp_max_findings <= 10000
    error_message = "DLP max findings must be between 1 and 10000."
  }
}

variable "monitoring_alert_duration" {
  description = "Duration for monitoring alert conditions in seconds"
  type        = string
  default     = "300s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.monitoring_alert_duration))
    error_message = "Monitoring alert duration must be in seconds format (e.g., 300s)."
  }
}

variable "alert_auto_close" {
  description = "Auto-close duration for alerts in seconds"
  type        = string
  default     = "1800s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.alert_auto_close))
    error_message = "Alert auto-close duration must be in seconds format (e.g., 1800s)."
  }
}

variable "create_sample_data" {
  description = "Create sample data for testing purposes"
  type        = bool
  default     = true
}

variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "Default storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "lifecycle_nearline_days" {
  description = "Number of days before moving objects to NEARLINE storage"
  type        = number
  default     = 30
  validation {
    condition     = var.lifecycle_nearline_days >= 0 && var.lifecycle_nearline_days <= 365
    error_message = "Lifecycle nearline days must be between 0 and 365."
  }
}

variable "lifecycle_coldline_days" {
  description = "Number of days before moving objects to COLDLINE storage"
  type        = number
  default     = 365
  validation {
    condition     = var.lifecycle_coldline_days >= 0 && var.lifecycle_coldline_days <= 3650
    error_message = "Lifecycle coldline days must be between 0 and 3650."
  }
}

variable "bigquery_table_expiration_days" {
  description = "Number of days before BigQuery tables expire (0 for no expiration)"
  type        = number
  default     = 0
  validation {
    condition     = var.bigquery_table_expiration_days >= 0
    error_message = "BigQuery table expiration days must be non-negative."
  }
}

variable "enable_bigquery_clustering" {
  description = "Enable clustering for BigQuery tables"
  type        = bool
  default     = true
}

variable "enable_bigquery_partitioning" {
  description = "Enable partitioning for BigQuery tables"
  type        = bool
  default     = true
}