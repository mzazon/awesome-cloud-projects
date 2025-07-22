# Project Configuration
variable "project_id" {
  description = "The GCP project ID for cost optimization resources"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.region))
    error_message = "Region must be a valid GCP region format."
  }
}

variable "zone" {
  description = "The GCP zone for deploying zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Billing Configuration
variable "billing_account_id" {
  description = "The billing account ID to monitor and optimize"
  type        = string
  validation {
    condition     = length(var.billing_account_id) > 0
    error_message = "Billing account ID must not be empty."
  }
}

variable "target_project_ids" {
  description = "List of project IDs to monitor for cost optimization"
  type        = list(string)
  default     = []
}

# Resource Configuration
variable "dataset_location" {
  description = "BigQuery dataset location"
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU", "us-central1", "us-east1", "us-west1", "europe-west1"], var.dataset_location)
    error_message = "Dataset location must be a valid BigQuery location."
  }
}

variable "storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# Function Configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python39"
  validation {
    condition     = contains(["python39", "python310", "python311"], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (MB)"
  type        = string
  default     = "512MB"
  validation {
    condition     = contains(["128MB", "256MB", "512MB", "1024MB", "2048MB", "4096MB"], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions memory allocation."
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

# Scheduling Configuration
variable "cost_analysis_schedule" {
  description = "Cron schedule for daily cost analysis"
  type        = string
  default     = "0 9 * * *"
}

variable "weekly_report_schedule" {
  description = "Cron schedule for weekly cost reports"
  type        = string
  default     = "0 8 * * 1"
}

variable "monthly_review_schedule" {
  description = "Cron schedule for monthly optimization review"
  type        = string
  default     = "0 7 1 * *"
}

variable "schedule_timezone" {
  description = "Timezone for scheduled jobs"
  type        = string
  default     = "America/New_York"
}

# Alerting Configuration
variable "notification_email" {
  description = "Email address for cost optimization alerts"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cost_threshold" {
  description = "Cost threshold for high-value optimization alerts (USD)"
  type        = number
  default     = 100
  validation {
    condition     = var.cost_threshold > 0
    error_message = "Cost threshold must be a positive number."
  }
}

# Monitoring Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring and logging"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Tagging and Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "cost-optimization"
    environment = "production"
    managed-by  = "terraform"
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "cost-opt"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

# Data Retention Configuration
variable "bigquery_table_expiration_days" {
  description = "Number of days to retain BigQuery table data"
  type        = number
  default     = 365
  validation {
    condition     = var.bigquery_table_expiration_days > 0
    error_message = "BigQuery table expiration must be a positive number."
  }
}

variable "storage_lifecycle_age" {
  description = "Age in days for storage lifecycle management"
  type        = number
  default     = 90
  validation {
    condition     = var.storage_lifecycle_age > 0
    error_message = "Storage lifecycle age must be a positive number."
  }
}