# Input Variables for IoT Data Processing Pipeline
# This file defines all configurable parameters for the infrastructure deployment

variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "development"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "iot_registry_name" {
  description = "Name for the IoT Core device registry"
  type        = string
  default     = "sensor-registry"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,61}[a-z0-9]$", var.iot_registry_name))
    error_message = "IoT registry name must be 3-63 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "device_name" {
  description = "Name for the IoT device"
  type        = string
  default     = "temperature-sensor"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]{2,254}$", var.device_name))
    error_message = "Device name must be 3-255 characters, start with a letter, and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "pubsub_topic_name" {
  description = "Name for the Pub/Sub topic for IoT telemetry"
  type        = string
  default     = "iot-telemetry"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]{2,254}$", var.pubsub_topic_name))
    error_message = "Topic name must be 3-255 characters, start with a letter, and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "pubsub_subscription_name" {
  description = "Name for the Pub/Sub subscription"
  type        = string
  default     = "iot-data-subscription"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]{2,254}$", var.pubsub_subscription_name))
    error_message = "Subscription name must be 3-255 characters, start with a letter, and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "bigquery_dataset_name" {
  description = "Name for the BigQuery dataset"
  type        = string
  default     = "iot_analytics"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,1023}$", var.bigquery_dataset_name))
    error_message = "Dataset name must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "bigquery_table_name" {
  description = "Name for the BigQuery table"
  type        = string
  default     = "sensor_readings"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,1023}$", var.bigquery_table_name))
    error_message = "Table name must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "storage_bucket_name" {
  description = "Name for the Cloud Storage bucket for Dataprep staging (will be suffixed with random string)"
  type        = string
  default     = "dataprep-staging"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_]{1,61}[a-z0-9]$", var.storage_bucket_name))
    error_message = "Bucket name must be 3-63 characters, start and end with alphanumeric characters, and contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

variable "message_retention_duration" {
  description = "Message retention duration for Pub/Sub topic and subscription"
  type        = string
  default     = "604800s" # 7 days
  validation {
    condition     = can(regex("^[0-9]+s$", var.message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., 604800s)."
  }
}

variable "ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscription in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.ack_deadline_seconds >= 10 && var.ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring dashboard and alerting"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable detailed logging for all services"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "iot-data-processing"
    managed-by  = "terraform"
    environment = "development"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))])
    error_message = "Label keys must be 1-63 characters, start with a letter, and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "dataprep_service_account_name" {
  description = "Name for the Dataprep service account"
  type        = string
  default     = "dataprep-pipeline"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.dataprep_service_account_name))
    error_message = "Service account name must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bigquery_location" {
  description = "Location for BigQuery dataset (must match region for optimal performance)"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1", "europe-north1",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid multi-region or region location."
  }
}

variable "storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_apis" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "cloudiot.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "dataprep.googleapis.com",
    "dataflow.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com"
  ]
}