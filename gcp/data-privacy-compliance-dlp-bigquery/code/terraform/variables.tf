# variables.tf
# Variable Definitions for Data Privacy Compliance Infrastructure

# Project Configuration
variable "project_id" {
  description = "Google Cloud Project ID for deploying privacy compliance resources"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for deploying regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-southeast1", "asia-east1", "asia-northeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

# Resource Naming and Tagging
variable "environment" {
  description = "Environment name for resource tagging and naming (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "privacy-compliance"
  validation {
    condition     = length(var.resource_prefix) <= 20
    error_message = "Resource prefix must be 20 characters or less."
  }
}

# Storage Configuration
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

variable "bucket_lifecycle_age_days" {
  description = "Number of days after which objects in the bucket will be deleted"
  type        = number
  default     = 365
  validation {
    condition     = var.bucket_lifecycle_age_days > 0 && var.bucket_lifecycle_age_days <= 3650
    error_message = "Lifecycle age must be between 1 and 3650 days."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

# BigQuery Configuration
variable "dataset_location" {
  description = "Geographic location for BigQuery dataset"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "asia-northeast1", "asia-southeast1", "europe-west1", "us-central1", "us-east1"
    ], var.dataset_location)
    error_message = "Dataset location must be a valid BigQuery location."
  }
}

variable "table_expiration_ms" {
  description = "Table expiration time in milliseconds (0 = never expires)"
  type        = number
  default     = 0
  validation {
    condition     = var.table_expiration_ms >= 0
    error_message = "Table expiration must be non-negative."
  }
}

variable "enable_table_deletion_protection" {
  description = "Enable deletion protection for BigQuery tables"
  type        = bool
  default     = true
}

# DLP Configuration
variable "dlp_min_likelihood" {
  description = "Minimum likelihood threshold for DLP findings"
  type        = string
  default     = "POSSIBLE"
  validation {
    condition = contains([
      "VERY_UNLIKELY", "UNLIKELY", "POSSIBLE", "LIKELY", "VERY_LIKELY"
    ], var.dlp_min_likelihood)
    error_message = "DLP likelihood must be one of: VERY_UNLIKELY, UNLIKELY, POSSIBLE, LIKELY, VERY_LIKELY."
  }
}

variable "dlp_max_findings_per_request" {
  description = "Maximum number of findings per DLP request"
  type        = number
  default     = 1000
  validation {
    condition     = var.dlp_max_findings_per_request > 0 && var.dlp_max_findings_per_request <= 3000
    error_message = "Max findings per request must be between 1 and 3000."
  }
}

variable "dlp_info_types" {
  description = "List of information types to detect with Cloud DLP"
  type        = list(string)
  default = [
    "EMAIL_ADDRESS",
    "PHONE_NUMBER",
    "US_SOCIAL_SECURITY_NUMBER",
    "CREDIT_CARD_NUMBER",
    "PERSON_NAME",
    "US_DRIVERS_LICENSE_NUMBER",
    "DATE_OF_BIRTH",
    "IP_ADDRESS"
  ]
}

variable "bytes_limit_per_file" {
  description = "Maximum bytes to scan per file (Cloud DLP)"
  type        = number
  default     = 10485760 # 10MB
  validation {
    condition     = var.bytes_limit_per_file > 0
    error_message = "Bytes limit per file must be positive."
  }
}

variable "dlp_file_types" {
  description = "File types to scan with Cloud DLP"
  type        = list(string)
  default     = ["CSV", "TEXT_FILE", "JSON"]
}

# Cloud Function Configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python39"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (MB)"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout > 0 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.function_max_instances > 0 && var.function_max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

# Monitoring and Alerting Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for the privacy compliance solution"
  type        = bool
  default     = true
}

variable "enable_audit_logs" {
  description = "Enable audit logs for privacy compliance tracking"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for compliance notifications"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

# Security Configuration
variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_bucket_public_access_prevention" {
  description = "Enable public access prevention for Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "kms_key_name" {
  description = "Cloud KMS key name for encryption (optional)"
  type        = string
  default     = ""
}

# Cost Management
variable "enable_cost_controls" {
  description = "Enable cost control measures (quotas, limits)"
  type        = bool
  default     = true
}

variable "budget_amount" {
  description = "Budget amount for cost monitoring (USD)"
  type        = number
  default     = 100
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be positive."
  }
}

# Resource Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "privacy-compliance"
    managed-by  = "terraform"
    environment = "dev"
  }
  validation {
    condition     = length(var.labels) <= 10
    error_message = "Maximum of 10 labels allowed."
  }
}