# Project configuration variables
variable "project_id" {
  description = "Google Cloud project ID for deploying resources"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "organization_id" {
  description = "Google Cloud organization ID for creating organization policies"
  type        = string
  validation {
    condition     = length(var.organization_id) > 0
    error_message = "Organization ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for deploying regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for deploying zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

# Resource naming variables
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "cost-alloc"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# BigQuery configuration
variable "dataset_location" {
  description = "Location for BigQuery dataset (regional or multi-regional)"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "asia-northeast1", "asia-southeast1", "australia-southeast1",
      "europe-north1", "europe-west2", "europe-west4", "us-central1", "us-east1", "us-west1"
    ], var.dataset_location)
    error_message = "Dataset location must be a valid BigQuery location."
  }
}

variable "dataset_description" {
  description = "Description for the BigQuery dataset"
  type        = string
  default     = "Cost allocation and resource tagging analytics dataset"
}

# Billing configuration
variable "billing_account_id" {
  description = "Billing account ID for Cloud Billing export configuration"
  type        = string
  default     = ""
}

# Organization policy configuration
variable "mandatory_labels" {
  description = "List of mandatory labels that must be present on all resources"
  type        = list(string)
  default     = ["department", "cost_center", "environment", "project_code"]
  validation {
    condition     = length(var.mandatory_labels) > 0
    error_message = "At least one mandatory label must be specified."
  }
}

variable "enforce_org_policy" {
  description = "Whether to enforce organization policy constraints (requires org admin permissions)"
  type        = bool
  default     = false
}

# Cloud Functions configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (in seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

# Asset inventory configuration
variable "monitored_asset_types" {
  description = "List of asset types to monitor with Cloud Asset Inventory"
  type        = list(string)
  default = [
    "compute.googleapis.com/Instance",
    "storage.googleapis.com/Bucket",
    "container.googleapis.com/Cluster"
  ]
}

# Notification configuration
variable "notification_channels" {
  description = "List of email addresses to receive cost allocation reports"
  type        = list(string)
  default     = []
}

# Storage configuration
variable "storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# Reporting configuration
variable "enable_automated_reporting" {
  description = "Whether to enable automated cost allocation reporting"
  type        = bool
  default     = true
}

variable "report_schedule" {
  description = "Cron schedule for automated reporting (Cloud Scheduler format)"
  type        = string
  default     = "0 9 * * 1" # Every Monday at 9 AM
  validation {
    condition     = can(regex("^[0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+ [0-9*,/-]+$", var.report_schedule))
    error_message = "Report schedule must be a valid cron expression."
  }
}

# Enable APIs flag
variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

# Tags for resource management
variable "default_labels" {
  description = "Default labels to apply to all resources"
  type        = map(string)
  default = {
    terraform   = "true"
    solution    = "cost-allocation"
    component   = "governance"
  }
}