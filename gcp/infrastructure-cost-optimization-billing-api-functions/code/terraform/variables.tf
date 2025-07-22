# Project and region configuration
variable "project_id" {
  description = "The Google Cloud project ID"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for resources that require it"
  type        = string
  default     = "us-central1-a"
}

# Billing configuration
variable "billing_account_id" {
  description = "The billing account ID for budget creation"
  type        = string
  validation {
    condition     = length(var.billing_account_id) > 0
    error_message = "Billing account ID must not be empty."
  }
}

# Resource naming
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "cost-opt"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

# BigQuery configuration
variable "dataset_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "asia-east1", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "europe-west6", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "us-west3", "us-west4"
    ], var.dataset_location)
    error_message = "Dataset location must be a valid BigQuery location."
  }
}

variable "dataset_description" {
  description = "Description for the BigQuery dataset"
  type        = string
  default     = "Cost optimization and billing analytics dataset"
}

# Cloud Functions configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312",
      "nodejs18", "nodejs20", "go119", "go120", "go121"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "512Mi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

# Budget configuration
variable "budget_amount" {
  description = "Budget amount in USD"
  type        = number
  default     = 1000
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "budget_thresholds" {
  description = "Budget alert thresholds as percentages"
  type        = list(number)
  default     = [0.5, 0.9, 1.0]
  validation {
    condition     = alltrue([for threshold in var.budget_thresholds : threshold > 0 && threshold <= 2.0])
    error_message = "Budget thresholds must be between 0 and 2.0 (200%)."
  }
}

# Scheduler configuration
variable "cost_analysis_schedule" {
  description = "Cron schedule for cost analysis function"
  type        = string
  default     = "0 9 * * *"
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.cost_analysis_schedule))
    error_message = "Cost analysis schedule must be a valid cron expression."
  }
}

variable "optimization_schedule" {
  description = "Cron schedule for optimization function"
  type        = string
  default     = "0 9 * * 1"
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.optimization_schedule))
    error_message = "Optimization schedule must be a valid cron expression."
  }
}

# Labels and tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "production"
    purpose     = "cost-optimization"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for key, value in var.labels :
      can(regex("^[a-z][a-z0-9_-]*$", key)) && can(regex("^[a-z0-9_-]*$", value))
    ])
    error_message = "Labels must follow Google Cloud labeling conventions."
  }
}

# API services to enable
variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "required_apis" {
  description = "List of required Google Cloud APIs"
  type        = list(string)
  default = [
    "cloudbilling.googleapis.com",
    "cloudfunctions.googleapis.com",
    "bigquery.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "eventarc.googleapis.com"
  ]
}