# Variables for collaborative data science workflows with Colab Enterprise and Dataform

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must be provided and cannot be empty."
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
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
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

variable "team_name" {
  description = "Name of the data science team for resource labeling"
  type        = string
  default     = "data-science"
}

variable "bucket_location" {
  description = "Location for Cloud Storage bucket (US, EU, ASIA or specific region)"
  type        = string
  default     = "US"
}

variable "dataset_location" {
  description = "Location for BigQuery dataset (US, EU, asia-northeast1, etc.)"
  type        = string
  default     = "US"
}

variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access for enhanced security"
  type        = bool
  default     = true
}

variable "enable_public_access_prevention" {
  description = "Prevent public access to storage bucket"
  type        = bool
  default     = true
}

variable "bigquery_time_travel_hours" {
  description = "Number of hours for BigQuery time travel (between 48 and 168)"
  type        = number
  default     = 168
  
  validation {
    condition     = var.bigquery_time_travel_hours >= 48 && var.bigquery_time_travel_hours <= 168
    error_message = "BigQuery time travel hours must be between 48 and 168."
  }
}

variable "notebook_machine_type" {
  description = "Machine type for Colab Enterprise notebook instances"
  type        = string
  default     = "n1-standard-4"
}

variable "dataform_git_url" {
  description = "Git repository URL for Dataform (optional, leave empty for local development)"
  type        = string
  default     = ""
}

variable "dataform_default_branch" {
  description = "Default branch for Dataform Git repository"
  type        = string
  default     = "main"
}

variable "data_scientists" {
  description = "List of email addresses for data scientists who need access"
  type        = list(string)
  default     = []
}

variable "data_engineers" {
  description = "List of email addresses for data engineers who need access"
  type        = list(string)
  default     = []
}

variable "analysts" {
  description = "List of email addresses for analysts who need read access"
  type        = list(string)
  default     = []
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "storage_lifecycle_age_days" {
  description = "Number of days after which to delete old storage objects"
  type        = number
  default     = 365
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted storage objects"
  type        = number
  default     = 7
  
  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention must be between 7 and 90 days."
  }
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_dataform_workspace" {
  description = "Whether to create a Dataform development workspace"
  type        = bool
  default     = true
}

variable "enable_sample_data" {
  description = "Whether to create sample tables with schemas for demonstration"
  type        = bool
  default     = true
}