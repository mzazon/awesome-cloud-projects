# Project and location variables
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
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
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

# BigQuery dataset configuration
variable "dataset_name" {
  description = "Name for the BigQuery dataset (will have timestamp suffix added)"
  type        = string
  default     = "retail_analytics"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.dataset_name))
    error_message = "Dataset name must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "dataset_description" {
  description = "Description for the BigQuery dataset"
  type        = string
  default     = "Dataset for interactive data storytelling with BigQuery Data Canvas and Looker Studio"
}

variable "dataset_location" {
  description = "Location for the BigQuery dataset"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1", "europe-north1",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6", "northamerica-northeast1",
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4"
    ], var.dataset_location)
    error_message = "Dataset location must be a valid BigQuery location."
  }
}

# Cloud Function configuration
variable "function_name" {
  description = "Name for the Cloud Function"
  type        = string
  default     = "data-storytelling-automation"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

# Cloud Scheduler configuration
variable "scheduler_job_name" {
  description = "Name for the Cloud Scheduler job"
  type        = string
  default     = "storytelling-job"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-_]*$", var.scheduler_job_name))
    error_message = "Scheduler job name must start with a letter and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "scheduler_cron" {
  description = "Cron schedule for automated report generation (default: weekdays at 9 AM)"
  type        = string
  default     = "0 9 * * 1-5"
  validation {
    condition     = can(regex("^[0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+$", var.scheduler_cron))
    error_message = "Scheduler cron must be a valid cron expression."
  }
}

variable "scheduler_timezone" {
  description = "Timezone for the Cloud Scheduler job"
  type        = string
  default     = "America/New_York"
}

# Storage configuration
variable "bucket_location" {
  description = "Location for the Cloud Storage bucket"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.bucket_location)
    error_message = "Bucket location must be a valid Cloud Storage location."
  }
}

variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.bucket_storage_class)
    error_message = "Bucket storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# Sample data configuration
variable "load_sample_data" {
  description = "Whether to load sample retail data into the BigQuery table"
  type        = bool
  default     = true
}

variable "sample_data_records" {
  description = "Number of sample data records to generate (if load_sample_data is true)"
  type        = number
  default     = 50
  validation {
    condition     = var.sample_data_records >= 10 && var.sample_data_records <= 1000
    error_message = "Sample data records must be between 10 and 1000."
  }
}

# Vertex AI configuration
variable "enable_vertex_ai" {
  description = "Whether to enable Vertex AI services for advanced analytics"
  type        = bool
  default     = true
}

# Resource naming configuration
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# Labels and tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "data-storytelling"
    environment = "demo"
    recipe      = "interactive-data-storytelling"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens. Values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}