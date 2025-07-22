# Variables for real-time analytics platform deployment
# Configure these values according to your requirements and environment

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
    condition = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The GCP zone for resources that require zone specification"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., us-central1-a)."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "analytics"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

# Pub/Sub Configuration
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topic (in seconds)"
  type        = string
  default     = "604800" # 7 days
  validation {
    condition     = can(regex("^[0-9]+$", var.pubsub_message_retention_duration))
    error_message = "Message retention duration must be a valid number in seconds."
  }
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscription (in seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

# Dataflow Configuration
variable "dataflow_max_workers" {
  description = "Maximum number of workers for Dataflow job"
  type        = number
  default     = 10
  validation {
    condition     = var.dataflow_max_workers >= 1 && var.dataflow_max_workers <= 1000
    error_message = "Maximum workers must be between 1 and 1000."
  }
}

variable "dataflow_machine_type" {
  description = "Machine type for Dataflow workers"
  type        = string
  default     = "n1-standard-2"
  validation {
    condition = contains([
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n1-standard-8",
      "n1-highmem-2", "n1-highmem-4", "n1-highmem-8",
      "n2-standard-2", "n2-standard-4", "n2-standard-8"
    ], var.dataflow_machine_type)
    error_message = "Machine type must be a valid Dataflow-supported machine type."
  }
}

variable "dataflow_use_public_ips" {
  description = "Whether Dataflow workers should use public IP addresses"
  type        = bool
  default     = false
}

# Cloud Storage Configuration
variable "storage_lifecycle_age_nearline" {
  description = "Number of days after which objects transition to Nearline storage"
  type        = number
  default     = 30
  validation {
    condition     = var.storage_lifecycle_age_nearline >= 1
    error_message = "Nearline transition age must be at least 1 day."
  }
}

variable "storage_lifecycle_age_coldline" {
  description = "Number of days after which objects transition to Coldline storage"
  type        = number
  default     = 90
  validation {
    condition     = var.storage_lifecycle_age_coldline >= var.storage_lifecycle_age_nearline
    error_message = "Coldline transition age must be greater than or equal to Nearline transition age."
  }
}

variable "storage_lifecycle_age_archive" {
  description = "Number of days after which objects transition to Archive storage"
  type        = number
  default     = 365
  validation {
    condition     = var.storage_lifecycle_age_archive >= var.storage_lifecycle_age_coldline
    error_message = "Archive transition age must be greater than or equal to Coldline transition age."
  }
}

variable "storage_force_destroy" {
  description = "Allow Terraform to destroy the storage bucket even if it contains objects"
  type        = bool
  default     = false
}

# Firestore Configuration
variable "firestore_location_id" {
  description = "The location for the Firestore database"
  type        = string
  default     = "us-central"
  validation {
    condition = contains([
      "us-central", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.firestore_location_id)
    error_message = "Location must be a valid Firestore location."
  }
}

variable "firestore_database_type" {
  description = "The type of Firestore database"
  type        = string
  default     = "FIRESTORE_NATIVE"
  validation {
    condition     = contains(["FIRESTORE_NATIVE", "DATASTORE_MODE"], var.firestore_database_type)
    error_message = "Database type must be either FIRESTORE_NATIVE or DATASTORE_MODE."
  }
}

# Service Account Configuration
variable "service_account_display_name" {
  description = "Display name for the Dataflow service account"
  type        = string
  default     = "Dataflow Analytics Pipeline Service Account"
}

variable "service_account_description" {
  description = "Description for the Dataflow service account"
  type        = string
  default     = "Service account for streaming analytics pipeline with Cloud Dataflow"
}

# API Services Configuration
variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "required_apis" {
  description = "List of Google Cloud APIs required for the analytics platform"
  type        = list(string)
  default = [
    "dataflow.googleapis.com",
    "pubsub.googleapis.com",
    "firestore.googleapis.com",
    "storage.googleapis.com",
    "appengine.googleapis.com",
    "compute.googleapis.com"
  ]
}

# Resource Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "real-time-analytics"
    managed-by  = "terraform"
    environment = "development"
  }
  validation {
    condition     = can(keys(var.labels))
    error_message = "Labels must be a valid map of key-value pairs."
  }
}

# Network Configuration
variable "network_name" {
  description = "Name of the VPC network (leave empty to use default network)"
  type        = string
  default     = ""
}

variable "subnet_name" {
  description = "Name of the subnet (leave empty to use default subnet)"
  type        = string
  default     = ""
}

# Pipeline Configuration
variable "pipeline_template_path" {
  description = "Path to the Dataflow pipeline template (optional)"
  type        = string
  default     = ""
}

variable "pipeline_temp_location" {
  description = "Temporary location for Dataflow pipeline (will use bucket if not specified)"
  type        = string
  default     = ""
}

variable "pipeline_staging_location" {
  description = "Staging location for Dataflow pipeline (will use bucket if not specified)"
  type        = string
  default     = ""
}