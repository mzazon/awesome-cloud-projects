# Variables for TimesFM BigQuery DataCanvas Time Series Forecasting Infrastructure

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region where resources will be deployed"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region with BigQuery and Vertex AI support."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "dataset_name" {
  description = "Name for the BigQuery dataset storing financial time series data"
  type        = string
  default     = "financial_forecasting"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_name))
    error_message = "Dataset name must contain only letters, numbers, and underscores."
  }
}

variable "storage_bucket_name" {
  description = "Name for the Cloud Storage bucket (will be suffixed with random string)"
  type        = string
  default     = "timesfm-data"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_.]*[a-z0-9]$", var.storage_bucket_name))
    error_message = "Bucket name must start and end with alphanumeric characters and contain only lowercase letters, numbers, hyphens, underscores, and periods."
  }
}

variable "function_name" {
  description = "Name for the Cloud Function processing financial data"
  type        = string
  default     = "forecast-processor"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-_]*[a-zA-Z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, end with alphanumeric character, and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "scheduler_timezone" {
  description = "Timezone for Cloud Scheduler jobs"
  type        = string
  default     = "America/New_York"
  
  validation {
    condition     = contains(["America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles", "Europe/London", "Europe/Paris", "Asia/Tokyo", "UTC"], var.scheduler_timezone)
    error_message = "Timezone must be a valid IANA timezone identifier."
  }
}

variable "daily_forecast_schedule" {
  description = "Cron schedule for daily forecasting (6:00 AM by default)"
  type        = string
  default     = "0 6 * * *"
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.daily_forecast_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "monitoring_schedule" {
  description = "Cron schedule for forecast accuracy monitoring (6:00 PM by default)"
  type        = string
  default     = "0 18 * * *"
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.monitoring_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "forecast_symbols" {
  description = "List of stock symbols to include in automated forecasting"
  type        = list(string)
  default     = ["AAPL", "GOOGL", "MSFT", "AMZN"]
  
  validation {
    condition     = alltrue([for s in var.forecast_symbols : can(regex("^[A-Z]{1,5}$", s))])
    error_message = "Stock symbols must be 1-5 uppercase letters."
  }
}

variable "forecast_horizon_days" {
  description = "Number of days to forecast ahead"
  type        = number
  default     = 7
  
  validation {
    condition     = var.forecast_horizon_days >= 1 && var.forecast_horizon_days <= 30
    error_message = "Forecast horizon must be between 1 and 30 days."
  }
}

variable "confidence_level" {
  description = "Confidence level for prediction intervals (0.80-0.99)"
  type        = number
  default     = 0.95
  
  validation {
    condition     = var.confidence_level >= 0.80 && var.confidence_level <= 0.99
    error_message = "Confidence level must be between 0.80 and 0.99."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Function (in MB)"
  type        = number
  default     = 512
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Function execution (in seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "bigquery_location" {
  description = "Location for BigQuery dataset (multi-region or region)"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west4", "asia-east1", "asia-northeast1"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid multi-region (US, EU) or supported region."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "timesfm-forecasting"
    environment = "development"
    team        = "data-science"
    cost-center = "analytics"
  }
  
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}