# Variables for GCP Dynamic Pricing Optimization Infrastructure
# This file defines all configurable variables for the pricing optimization solution

# Core GCP Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "pricing-opt"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
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
variable "dataset_name" {
  description = "Name of the BigQuery dataset for pricing optimization data"
  type        = string
  default     = "pricing_optimization"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_name))
    error_message = "Dataset name must contain only letters, numbers, and underscores."
  }
}

variable "dataset_description" {
  description = "Description of the BigQuery dataset"
  type        = string
  default     = "Dataset for dynamic pricing optimization containing sales history, competitor pricing, and ML models"
}

variable "dataset_location" {
  description = "Location for BigQuery dataset (should match region for optimal performance)"
  type        = string
  default     = "US"
}

variable "dataset_delete_contents_on_destroy" {
  description = "Whether to delete dataset contents when destroying (be careful in production)"
  type        = bool
  default     = true
}

# Cloud Storage Configuration
variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_lifecycle_age" {
  description = "Number of days after which objects in the bucket are deleted"
  type        = number
  default     = 90
  validation {
    condition     = var.bucket_lifecycle_age > 0 && var.bucket_lifecycle_age <= 3650
    error_message = "Bucket lifecycle age must be between 1 and 3650 days."
  }
}

# Cloud Functions Configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 512
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of Cloud Function instances"
  type        = number
  default     = 100
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Function max instances must be between 1 and 3000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of Cloud Function instances (for reduced cold starts)"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 100
    error_message = "Function min instances must be between 0 and 100."
  }
}

# Cloud Scheduler Configuration
variable "scheduler_frequency" {
  description = "Cron expression for pricing optimization schedule"
  type        = string
  default     = "0 */6 * * *"
  validation {
    condition     = can(regex("^[0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+$", var.scheduler_frequency))
    error_message = "Scheduler frequency must be a valid cron expression."
  }
}

variable "scheduler_timezone" {
  description = "Timezone for scheduler jobs"
  type        = string
  default     = "UTC"
}

variable "product_ids" {
  description = "List of product IDs to schedule pricing optimization for"
  type        = list(string)
  default     = ["PROD001", "PROD002", "PROD003"]
  validation {
    condition     = length(var.product_ids) > 0
    error_message = "At least one product ID must be specified."
  }
}

# Vertex AI Configuration
variable "vertex_ai_machine_type" {
  description = "Machine type for Vertex AI training jobs"
  type        = string
  default     = "n1-standard-4"
  validation {
    condition = contains([
      "n1-standard-4", "n1-standard-8", "n1-highmem-2", "n1-highmem-4", "n1-highmem-8",
      "n2-standard-4", "n2-standard-8", "n2-highmem-2", "n2-highmem-4"
    ], var.vertex_ai_machine_type)
    error_message = "Machine type must be a valid Vertex AI training machine type."
  }
}

variable "vertex_ai_replica_count" {
  description = "Number of replicas for Vertex AI training"
  type        = number
  default     = 1
  validation {
    condition     = var.vertex_ai_replica_count >= 1 && var.vertex_ai_replica_count <= 10
    error_message = "Replica count must be between 1 and 10."
  }
}

# Monitoring Configuration
variable "enable_monitoring_dashboard" {
  description = "Whether to create Cloud Monitoring dashboard"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring notifications (optional)"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

# Security Configuration
variable "enable_public_access" {
  description = "Whether to enable public access to Cloud Function (disable for production)"
  type        = bool
  default     = false
}

variable "allowed_members" {
  description = "List of members allowed to invoke the Cloud Function (when public access is disabled)"
  type        = list(string)
  default     = []
}

# Sample Data Configuration
variable "load_sample_data" {
  description = "Whether to load sample data into BigQuery for testing"
  type        = bool
  default     = true
}

variable "sample_data_file" {
  description = "Path to sample data CSV file (relative to Terraform root)"
  type        = string
  default     = "sample_data/sales_history.csv"
}

# API Configuration
variable "enable_apis" {
  description = "List of APIs to enable for the project"
  type        = list(string)
  default = [
    "bigquery.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage-component.googleapis.com",
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]
}

# Resource Tagging
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "dynamic-pricing-optimization"
    component   = "ml-analytics"
    environment = "dev"
    managed-by  = "terraform"
  }
}

# Cost Control
variable "enable_cost_controls" {
  description = "Whether to enable cost control measures (quotas, limits)"
  type        = bool
  default     = true
}

variable "bigquery_daily_cost_limit" {
  description = "Daily cost limit for BigQuery in USD (0 for no limit)"
  type        = number
  default     = 10
  validation {
    condition     = var.bigquery_daily_cost_limit >= 0
    error_message = "BigQuery daily cost limit must be non-negative."
  }
}