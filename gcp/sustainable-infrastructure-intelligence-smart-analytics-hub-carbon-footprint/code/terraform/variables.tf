# ==============================================================================
# PROJECT CONFIGURATION VARIABLES
# ==============================================================================

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.project_id))
    error_message = "Project ID must start with a lowercase letter, followed by lowercase letters, numbers, or hyphens, and end with a lowercase letter or number."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.region))
    error_message = "Region must be a valid Google Cloud region format."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format."
  }
}

# ==============================================================================
# NAMING AND LABELING VARIABLES
# ==============================================================================

variable "project_name" {
  description = "A human-readable name for the project, used in resource naming"
  type        = string
  default     = "sustainability-intel"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "labels" {
  description = "A map of labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "sustainability-intelligence"
    managed-by  = "terraform"
    purpose     = "carbon-footprint-analytics"
  }
}

# ==============================================================================
# BIGQUERY CONFIGURATION VARIABLES
# ==============================================================================

variable "dataset_name" {
  description = "Name of the BigQuery dataset for carbon intelligence data"
  type        = string
  default     = "carbon_intelligence"
  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.dataset_name))
    error_message = "Dataset name must start with a letter or underscore, followed by letters, numbers, or underscores."
  }
}

variable "dataset_description" {
  description = "Description for the BigQuery dataset"
  type        = string
  default     = "Carbon footprint intelligence and sustainability analytics data"
}

variable "dataset_location" {
  description = "Location for BigQuery dataset (should match region for optimal performance)"
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU", "us-central1", "europe-west1", "asia-northeast1"], var.dataset_location)
    error_message = "Dataset location must be a valid BigQuery location."
  }
}

variable "data_retention_days" {
  description = "Number of days to retain carbon footprint data in BigQuery"
  type        = number
  default     = 2555  # ~7 years for sustainability reporting requirements
  validation {
    condition     = var.data_retention_days >= 30 && var.data_retention_days <= 3650
    error_message = "Data retention days must be between 30 and 3650 (10 years)."
  }
}

# ==============================================================================
# CLOUD STORAGE CONFIGURATION VARIABLES
# ==============================================================================

variable "reports_bucket_name" {
  description = "Name of the Cloud Storage bucket for sustainability reports (will have random suffix appended)"
  type        = string
  default     = "carbon-reports"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]*[a-z0-9]$", var.reports_bucket_name))
    error_message = "Bucket name must start and end with alphanumeric characters and contain only lowercase letters, numbers, hyphens, underscores, and periods."
  }
}

variable "reports_bucket_storage_class" {
  description = "Storage class for the reports bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.reports_bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the reports bucket"
  type        = bool
  default     = true
}

# ==============================================================================
# PUB/SUB CONFIGURATION VARIABLES
# ==============================================================================

variable "alerts_topic_name" {
  description = "Name of the Pub/Sub topic for carbon emission alerts"
  type        = string
  default     = "carbon-alerts"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9._~%+-]*$", var.alerts_topic_name))
    error_message = "Topic name must start with a letter and contain only alphanumeric characters and certain special characters."
  }
}

variable "message_retention_duration" {
  description = "Message retention duration for Pub/Sub topic (in seconds)"
  type        = string
  default     = "604800s"  # 7 days
  validation {
    condition     = can(regex("^[0-9]+s$", var.message_retention_duration))
    error_message = "Message retention duration must be specified in seconds with 's' suffix."
  }
}

# ==============================================================================
# CLOUD FUNCTIONS CONFIGURATION VARIABLES
# ==============================================================================

variable "data_processor_function_name" {
  description = "Name of the Cloud Function for processing carbon data"
  type        = string
  default     = "carbon-processor"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.data_processor_function_name))
    error_message = "Function name must start with a lowercase letter, followed by lowercase letters, numbers, or hyphens, and end with a lowercase letter or number."
  }
}

variable "recommendations_function_name" {
  description = "Name of the Cloud Function for generating sustainability recommendations"
  type        = string
  default     = "recommendations-engine"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.recommendations_function_name))
    error_message = "Function name must start with a lowercase letter, followed by lowercase letters, numbers, or hyphens, and end with a lowercase letter or number."
  }
}

variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python312"
  validation {
    condition     = contains(["python39", "python310", "python311", "python312"], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = string
  default     = "512M"
  validation {
    condition     = contains(["128M", "256M", "512M", "1024M", "2048M", "4096M", "8192M"], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions memory allocation."
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

# ==============================================================================
# ANALYTICS HUB CONFIGURATION VARIABLES
# ==============================================================================

variable "data_exchange_name" {
  description = "Name of the Analytics Hub data exchange"
  type        = string
  default     = "sustainability-analytics-exchange"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.data_exchange_name))
    error_message = "Data exchange name must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "data_exchange_display_name" {
  description = "Display name for the Analytics Hub data exchange"
  type        = string
  default     = "Sustainability Analytics Exchange"
}

variable "enable_data_sharing" {
  description = "Enable Analytics Hub data sharing capabilities"
  type        = bool
  default     = true
}

# ==============================================================================
# SCHEDULER CONFIGURATION VARIABLES
# ==============================================================================

variable "recommendations_schedule" {
  description = "Cron schedule for generating sustainability recommendations"
  type        = string
  default     = "0 9 * * 1"  # Weekly on Monday at 9 AM
  validation {
    condition     = can(regex("^[0-9*/-]+\\s+[0-9*/-]+\\s+[0-9*/-]+\\s+[0-9*/-]+\\s+[0-9*/-]+$", var.recommendations_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "data_processing_schedule" {
  description = "Cron schedule for monthly data processing"
  type        = string
  default     = "0 6 15 * *"  # Monthly on the 15th at 6 AM
  validation {
    condition     = can(regex("^[0-9*/-]+\\s+[0-9*/-]+\\s+[0-9*/-]+\\s+[0-9*/-]+\\s+[0-9*/-]+$", var.data_processing_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "scheduler_timezone" {
  description = "Timezone for Cloud Scheduler jobs"
  type        = string
  default     = "America/New_York"
  validation {
    condition     = can(regex("^[A-Za-z]+/[A-Za-z_]+$", var.scheduler_timezone))
    error_message = "Timezone must be a valid IANA timezone format (e.g., America/New_York)."
  }
}

# ==============================================================================
# CARBON FOOTPRINT MONITORING VARIABLES
# ==============================================================================

variable "carbon_increase_threshold" {
  description = "Percentage threshold for carbon emission increase alerts"
  type        = number
  default     = 20
  validation {
    condition     = var.carbon_increase_threshold > 0 && var.carbon_increase_threshold <= 100
    error_message = "Carbon increase threshold must be between 1 and 100 percent."
  }
}

variable "enable_anomaly_detection" {
  description = "Enable automated anomaly detection for carbon emissions"
  type        = bool
  default     = true
}

variable "monitoring_window_months" {
  description = "Number of months to analyze for carbon emission trends"
  type        = number
  default     = 6
  validation {
    condition     = var.monitoring_window_months >= 1 && var.monitoring_window_months <= 24
    error_message = "Monitoring window must be between 1 and 24 months."
  }
}

# ==============================================================================
# SECURITY AND IAM VARIABLES
# ==============================================================================

variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_public_access_prevention" {
  description = "Prevent public access to Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "create_service_accounts" {
  description = "Whether to create dedicated service accounts for functions"
  type        = bool
  default     = true
}

# ==============================================================================
# BILLING AND COST VARIABLES
# ==============================================================================

variable "billing_account_id" {
  description = "Billing account ID for carbon footprint data export (optional - can be detected automatically)"
  type        = string
  default     = ""
}

variable "enable_cost_alerts" {
  description = "Enable cost-based alerts for infrastructure optimization"
  type        = bool
  default     = true
}