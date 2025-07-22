# Project Configuration Variables
variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# BigQuery Configuration Variables
variable "dataset_name" {
  description = "Name of the BigQuery dataset for carbon footprint analytics"
  type        = string
  default     = "carbon_footprint_analytics"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_name))
    error_message = "Dataset name must contain only letters, numbers, and underscores."
  }
}

variable "dataset_description" {
  description = "Description for the BigQuery dataset"
  type        = string
  default     = "Carbon footprint and sustainability analytics data warehouse"
}

variable "table_expiration_days" {
  description = "Number of days after which BigQuery tables expire (0 for no expiration)"
  type        = number
  default     = 365
  validation {
    condition     = var.table_expiration_days >= 0
    error_message = "Table expiration days must be 0 or positive."
  }
}

# Storage Configuration Variables
variable "bucket_storage_class" {
  description = "Storage class for the carbon data bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_lifecycle_age_nearline" {
  description = "Age in days when objects transition to NEARLINE storage"
  type        = number
  default     = 30
  validation {
    condition     = var.bucket_lifecycle_age_nearline > 0
    error_message = "Nearline transition age must be positive."
  }
}

variable "bucket_lifecycle_age_coldline" {
  description = "Age in days when objects transition to COLDLINE storage"
  type        = number
  default     = 90
  validation {
    condition     = var.bucket_lifecycle_age_coldline > var.bucket_lifecycle_age_nearline
    error_message = "Coldline transition age must be greater than nearline transition age."
  }
}

# Pub/Sub Configuration Variables
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topic (in seconds)"
  type        = string
  default     = "604800s" # 7 days
}

# Vertex AI Configuration Variables
variable "agent_display_name" {
  description = "Display name for the Vertex AI sustainability agent"
  type        = string
  default     = "Carbon Footprint Sustainability Advisor"
}

variable "agent_description" {
  description = "Description for the Vertex AI sustainability agent"
  type        = string
  default     = "AI agent for carbon footprint analysis and sustainability recommendations"
}

variable "agent_instruction" {
  description = "System instruction for the Vertex AI agent"
  type        = string
  default     = "You are a sustainability expert focused on cloud infrastructure carbon footprint optimization. Analyze data from Cloud Asset Inventory and Carbon Footprint service to provide actionable recommendations for reducing environmental impact while optimizing costs."
}

# Monitoring Configuration Variables
variable "alert_threshold_carbon_emissions" {
  description = "Threshold for carbon emissions alert (kgCO2e)"
  type        = number
  default     = 10.0
  validation {
    condition     = var.alert_threshold_carbon_emissions > 0
    error_message = "Carbon emissions alert threshold must be positive."
  }
}

variable "notification_email" {
  description = "Email address for carbon emissions alerts (optional)"
  type        = string
  default     = ""
}

# Asset Inventory Configuration Variables
variable "asset_types_to_monitor" {
  description = "List of Google Cloud asset types to monitor for carbon footprint analysis"
  type        = list(string)
  default = [
    "compute.googleapis.com/Instance",
    "storage.googleapis.com/Bucket",
    "container.googleapis.com/Cluster",
    "bigquery.googleapis.com/Dataset",
    "cloudsql.googleapis.com/DatabaseInstance"
  ]
}

variable "asset_content_type" {
  description = "Content type for asset inventory feed"
  type        = string
  default     = "RESOURCE"
  validation {
    condition = contains([
      "CONTENT_TYPE_UNSPECIFIED", "RESOURCE", "IAM_POLICY", "ORG_POLICY", "ACCESS_POLICY"
    ], var.asset_content_type)
    error_message = "Asset content type must be a valid Cloud Asset Inventory content type."
  }
}

# Tagging and Organization Variables
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment   = "production"
    project       = "carbon-monitoring"
    managed_by    = "terraform"
    sustainability = "true"
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "carbon-monitor"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}