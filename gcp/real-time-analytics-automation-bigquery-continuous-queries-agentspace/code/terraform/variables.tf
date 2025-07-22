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
  description = "The GCP region for resource deployment"
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

# Resource Naming Variables
variable "dataset_name" {
  description = "Name for the BigQuery dataset"
  type        = string
  default     = "realtime_analytics"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_name))
    error_message = "Dataset name can only contain letters, numbers, and underscores."
  }
}

variable "table_name" {
  description = "Name for the BigQuery processed events table"
  type        = string
  default     = "processed_events"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.table_name))
    error_message = "Table name can only contain letters, numbers, and underscores."
  }
}

variable "insights_table_name" {
  description = "Name for the BigQuery insights table"
  type        = string
  default     = "insights"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.insights_table_name))
    error_message = "Table name can only contain letters, numbers, and underscores."
  }
}

# Resource Configuration Variables
variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "create_service_account" {
  description = "Whether to create a service account for Agentspace integration"
  type        = bool
  default     = true
}

variable "enable_continuous_query" {
  description = "Whether to deploy the BigQuery continuous query job"
  type        = bool
  default     = true
}

# Pub/Sub Configuration
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topics"
  type        = string
  default     = "604800s" # 7 days
}

# BigQuery Configuration
variable "bigquery_location" {
  description = "Location for BigQuery dataset (can be different from compute region)"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "asia-east1", "asia-northeast1", "asia-southeast1",
      "australia-southeast1", "europe-north1", "europe-west2", "europe-west4",
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid location."
  }
}

variable "table_deletion_protection" {
  description = "Enable deletion protection for BigQuery tables"
  type        = bool
  default     = false
}

# Cloud Workflows Configuration
variable "workflow_description" {
  description = "Description for the Cloud Workflows automation"
  type        = string
  default     = "Automated response workflow for real-time analytics insights"
}

# Monitoring and Alerting Configuration
variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring for the pipeline"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for monitoring alerts (optional)"
  type        = string
  default     = ""
  validation {
    condition     = var.alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address or empty."
  }
}

# Cost Management Variables
variable "labels" {
  description = "Labels to apply to all resources for cost tracking and organization"
  type        = map(string)
  default = {
    environment = "dev"
    project     = "real-time-analytics"
    managed-by  = "terraform"
  }
}

# Advanced Configuration
variable "max_continuous_query_slots" {
  description = "Maximum number of BigQuery slots for continuous query"
  type        = number
  default     = 100
  validation {
    condition     = var.max_continuous_query_slots > 0 && var.max_continuous_query_slots <= 2000
    error_message = "Continuous query slots must be between 1 and 2000."
  }
}

variable "pubsub_dead_letter_max_delivery_attempts" {
  description = "Maximum delivery attempts before sending to dead letter queue"
  type        = number
  default     = 5
  validation {
    condition     = var.pubsub_dead_letter_max_delivery_attempts >= 5 && var.pubsub_dead_letter_max_delivery_attempts <= 100
    error_message = "Dead letter max delivery attempts must be between 5 and 100."
  }
}