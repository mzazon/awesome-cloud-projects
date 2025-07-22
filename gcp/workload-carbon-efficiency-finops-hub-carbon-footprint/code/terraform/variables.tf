# Project and location configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id must be a valid Google Cloud project ID."
  }
}

variable "region" {
  description = "The Google Cloud region where resources will be created"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "The region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone where resources will be created"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.zone))
    error_message = "The zone must be a valid Google Cloud zone."
  }
}

# Carbon efficiency configuration
variable "carbon_efficiency_threshold" {
  description = "Carbon efficiency threshold below which alerts are triggered"
  type        = number
  default     = 70.0
  validation {
    condition     = var.carbon_efficiency_threshold >= 0 && var.carbon_efficiency_threshold <= 100
    error_message = "Carbon efficiency threshold must be between 0 and 100."
  }
}

variable "efficiency_analysis_schedule" {
  description = "Cron schedule for automated carbon efficiency analysis (Cloud Scheduler format)"
  type        = string
  default     = "0 9 * * *"
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.efficiency_analysis_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

# Monitoring and alerting configuration
variable "notification_channels" {
  description = "List of notification channel IDs for carbon efficiency alerts"
  type        = list(string)
  default     = []
}

variable "enable_finops_hub_integration" {
  description = "Enable FinOps Hub 2.0 integration for waste detection"
  type        = bool
  default     = true
}

variable "enable_gemini_cloud_assist" {
  description = "Enable Gemini Cloud Assist integration for AI-powered recommendations"
  type        = bool
  default     = true
}

# Function deployment configuration
variable "carbon_efficiency_memory" {
  description = "Memory allocation for carbon efficiency correlation function (MB)"
  type        = number
  default     = 512
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.carbon_efficiency_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, or 8192 MB."
  }
}

variable "optimization_memory" {
  description = "Memory allocation for optimization automation function (MB)"
  type        = number
  default     = 1024
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.optimization_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, or 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

# BigQuery dataset configuration
variable "create_bigquery_dataset" {
  description = "Create BigQuery dataset for FinOps Hub insights storage"
  type        = bool
  default     = true
}

variable "bigquery_dataset_id" {
  description = "BigQuery dataset ID for storing carbon efficiency data"
  type        = string
  default     = "carbon_efficiency"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.bigquery_dataset_id))
    error_message = "BigQuery dataset ID must contain only letters, numbers, and underscores."
  }
}

variable "dataset_retention_days" {
  description = "Number of days to retain data in BigQuery dataset"
  type        = number
  default     = 90
  validation {
    condition     = var.dataset_retention_days >= 1 && var.dataset_retention_days <= 3650
    error_message = "Dataset retention must be between 1 and 3650 days."
  }
}

# Tagging and labeling
variable "labels" {
  description = "A map of labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "carbon-efficiency"
    environment = "production"
    managed-by  = "terraform"
    solution    = "finops-carbon-footprint"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

# Advanced configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring with custom metrics"
  type        = bool
  default     = true
}

variable "enable_automation" {
  description = "Enable automated optimization actions based on recommendations"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Number of days to retain Cloud Function logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3650
    error_message = "Log retention must be between 1 and 3650 days."
  }
}