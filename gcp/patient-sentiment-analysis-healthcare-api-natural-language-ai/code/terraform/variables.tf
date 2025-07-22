# Core project configuration
variable "project_id" {
  description = "Google Cloud Project ID for healthcare sentiment analysis deployment"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-southeast1", "asia-northeast1", "asia-east1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Healthcare API configuration
variable "healthcare_dataset_name" {
  description = "Name for the Healthcare API dataset"
  type        = string
  default     = "patient-records"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]*[a-z0-9]$", var.healthcare_dataset_name))
    error_message = "Healthcare dataset name must be lowercase letters, numbers, hyphens, and underscores only."
  }
}

variable "fhir_store_name" {
  description = "Name for the FHIR store within the healthcare dataset"
  type        = string
  default     = "patient-fhir"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]*[a-z0-9]$", var.fhir_store_name))
    error_message = "FHIR store name must be lowercase letters, numbers, hyphens, and underscores only."
  }
}

variable "fhir_version" {
  description = "FHIR version for the healthcare store"
  type        = string
  default     = "R4"
  validation {
    condition     = contains(["DSTU2", "STU3", "R4"], var.fhir_version)
    error_message = "FHIR version must be one of: DSTU2, STU3, R4."
  }
}

# Cloud Function configuration
variable "function_name" {
  description = "Name for the sentiment analysis Cloud Function"
  type        = string
  default     = "sentiment-processor"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must be lowercase letters, numbers, and hyphens only."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "python39"
  validation {
    condition = contains([
      "python37", "python38", "python39", "python310", "python311"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

# Pub/Sub configuration
variable "pubsub_topic_name" {
  description = "Name for the Pub/Sub topic for FHIR notifications"
  type        = string
  default     = "fhir-notifications"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.pubsub_topic_name))
    error_message = "Pub/Sub topic name must be lowercase letters, numbers, and hyphens only."
  }
}

# BigQuery configuration
variable "bigquery_dataset_id" {
  description = "BigQuery dataset ID for sentiment analysis results"
  type        = string
  default     = "patient_sentiment"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.bigquery_dataset_id))
    error_message = "BigQuery dataset ID must contain only letters, numbers, and underscores."
  }
}

variable "bigquery_table_id" {
  description = "BigQuery table ID for sentiment analysis results"
  type        = string
  default     = "sentiment_analysis"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.bigquery_table_id))
    error_message = "BigQuery table ID must contain only letters, numbers, and underscores."
  }
}

variable "bigquery_location" {
  description = "Location for BigQuery dataset (must match region for optimal performance)"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-southeast1", "asia-northeast1"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid location."
  }
}

# IAM and Security configuration
variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

# Resource naming configuration
variable "resource_suffix" {
  description = "Optional suffix for resource naming to ensure uniqueness"
  type        = string
  default     = ""
  validation {
    condition     = var.resource_suffix == "" || can(regex("^[a-z0-9-]*$", var.resource_suffix))
    error_message = "Resource suffix must be lowercase letters, numbers, and hyphens only."
  }
}

# Environment and tagging
variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    solution    = "patient-sentiment-analysis"
    managed-by  = "terraform"
    environment = "dev"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Cost optimization settings
variable "function_min_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Function min instances must be between 0 and 1000."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances for scaling"
  type        = number
  default     = 100
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function max instances must be between 1 and 1000."
  }
}