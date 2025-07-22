# Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The default region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1",
      "southamerica-east1", "northamerica-northeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The default zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Naming Configuration
variable "project_name" {
  description = "A human-readable project name used for resource naming"
  type        = string
  default     = "climate-risk-assessment"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,28}[a-z0-9]$", var.project_name))
    error_message = "Project name must be 4-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# BigQuery Configuration
variable "dataset_location" {
  description = "The location for BigQuery datasets"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "asia-northeast1", "asia-south1", "asia-southeast1", "australia-southeast1",
      "europe-north1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west4"
    ], var.dataset_location)
    error_message = "Dataset location must be a valid BigQuery location."
  }
}

variable "dataset_description" {
  description = "Description for the BigQuery dataset"
  type        = string
  default     = "Climate risk assessment data containing satellite imagery analysis and risk metrics"
}

variable "dataset_delete_contents_on_destroy" {
  description = "Whether to delete dataset contents when destroying the dataset"
  type        = bool
  default     = true
}

variable "table_expiration_days" {
  description = "Number of days after which BigQuery tables expire (null for no expiration)"
  type        = number
  default     = null
  validation {
    condition     = var.table_expiration_days == null || var.table_expiration_days > 0
    error_message = "Table expiration days must be positive or null."
  }
}

# Cloud Storage Configuration
variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_versioning_enabled" {
  description = "Whether to enable versioning on the storage bucket"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age_days" {
  description = "Number of days after which objects are deleted (0 to disable)"
  type        = number
  default     = 365
  validation {
    condition     = var.bucket_lifecycle_age_days >= 0
    error_message = "Bucket lifecycle age days must be non-negative."
  }
}

# Cloud Functions Configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312",
      "nodejs16", "nodejs18", "nodejs20", "go116", "go118", "go119", "go120", "go121",
      "java11", "java17", "dotnet3", "dotnet6", "ruby27", "ruby30", "ruby32"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 2048
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Function max instances must be between 1 and 3000."
  }
}

# API Configuration
variable "enable_apis" {
  description = "List of APIs to enable"
  type        = list(string)
  default = [
    "earthengine.googleapis.com",
    "bigquery.googleapis.com",
    "cloudfunctions.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com"
  ]
}

# Monitoring Configuration
variable "enable_monitoring_alerts" {
  description = "Whether to enable Cloud Monitoring alerts"
  type        = bool
  default     = true
}

variable "notification_channels" {
  description = "List of notification channel IDs for monitoring alerts"
  type        = list(string)
  default     = []
}

# Climate Data Configuration
variable "default_analysis_region" {
  description = "Default geographic region for climate analysis [west_longitude, south_latitude, east_longitude, north_latitude]"
  type        = list(number)
  default     = [-104, 37, -94, 41] # Central United States
  validation {
    condition     = length(var.default_analysis_region) == 4
    error_message = "Analysis region must contain exactly 4 coordinates: [west_longitude, south_latitude, east_longitude, north_latitude]."
  }
}

variable "default_analysis_start_date" {
  description = "Default start date for climate analysis in YYYY-MM-DD format"
  type        = string
  default     = "2020-01-01"
  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.default_analysis_start_date))
    error_message = "Analysis start date must be in YYYY-MM-DD format."
  }
}

variable "default_analysis_end_date" {
  description = "Default end date for climate analysis in YYYY-MM-DD format"
  type        = string
  default     = "2023-12-31"
  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.default_analysis_end_date))
    error_message = "Analysis end date must be in YYYY-MM-DD format."
  }
}

# Security Configuration
variable "enable_uniform_bucket_level_access" {
  description = "Whether to enable uniform bucket-level access"
  type        = bool
  default     = true
}

variable "bucket_public_access_prevention" {
  description = "Public access prevention setting for storage bucket"
  type        = string
  default     = "enforced"
  validation {
    condition     = contains(["enforced", "inherited"], var.bucket_public_access_prevention)
    error_message = "Bucket public access prevention must be either 'enforced' or 'inherited'."
  }
}

# Labeling Configuration
variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "climate-risk-assessment"
    environment = "dev"
    managed-by  = "terraform"
    use-case    = "climate-analytics"
  }
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Maximum of 64 labels can be applied to resources."
  }
}