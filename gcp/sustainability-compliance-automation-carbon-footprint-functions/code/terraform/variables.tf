# Variables for the sustainability compliance automation solution
# This file defines all configurable parameters for the Terraform deployment

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "europe-west1", 
      "europe-west2", "asia-southeast1", "asia-northeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "billing_account_id" {
  description = "The billing account ID for Carbon Footprint data export"
  type        = string
  validation {
    condition     = length(var.billing_account_id) > 0
    error_message = "Billing account ID must not be empty."
  }
}

variable "dataset_name" {
  description = "Name for the BigQuery dataset to store carbon footprint data"
  type        = string
  default     = "carbon_footprint_data"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_name))
    error_message = "Dataset name must contain only alphanumeric characters and underscores."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (MB)"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "alert_function_timeout" {
  description = "Timeout for the alert function (seconds)"
  type        = number
  default     = 120
  validation {
    condition     = var.alert_function_timeout >= 60 && var.alert_function_timeout <= 540
    error_message = "Alert function timeout must be between 60 and 540 seconds."
  }
}

variable "alert_function_memory" {
  description = "Memory allocation for the alert function (MB)"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096], var.alert_function_memory)
    error_message = "Alert function memory must be one of: 128, 256, 512, 1024, 2048, 4096 MB."
  }
}

variable "monthly_emissions_threshold" {
  description = "Monthly emissions threshold for alerts (kg CO2e)"
  type        = number
  default     = 1000
  validation {
    condition     = var.monthly_emissions_threshold > 0
    error_message = "Monthly emissions threshold must be greater than 0."
  }
}

variable "growth_threshold" {
  description = "Month-over-month growth threshold for alerts (percentage)"
  type        = number
  default     = 0.15
  validation {
    condition     = var.growth_threshold > 0 && var.growth_threshold < 1
    error_message = "Growth threshold must be between 0 and 1 (0-100%)."
  }
}

variable "enable_scheduled_processing" {
  description = "Enable Cloud Scheduler jobs for automated processing"
  type        = bool
  default     = true
}

variable "enable_alerts" {
  description = "Enable carbon emission alert monitoring"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "Storage class for the ESG reports bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "sustainability"
    purpose     = "carbon-tracking"
    managed-by  = "terraform"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python312"
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}