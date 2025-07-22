# Variables for multi-language content optimization with Cloud Translation and Cloud Run Worker Pools

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
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
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "content-opt"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with alphanumeric character."
  }
}

# Storage Configuration
variable "source_bucket_name" {
  description = "Name for the source content bucket (will be prefixed with resource_prefix)"
  type        = string
  default     = "source"
}

variable "translated_bucket_name" {
  description = "Name for the translated content bucket (will be prefixed with resource_prefix)"
  type        = string
  default     = "translated"
}

variable "models_bucket_name" {
  description = "Name for the custom models bucket (will be prefixed with resource_prefix)"
  type        = string
  default     = "models"
}

variable "bucket_location" {
  description = "Location for Cloud Storage buckets"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "ASIA", 
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.bucket_location)
    error_message = "Bucket location must be a valid Cloud Storage location."
  }
}

variable "bucket_storage_class" {
  description = "Default storage class for buckets"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# Pub/Sub Configuration
variable "pubsub_topic_name" {
  description = "Name for the Pub/Sub topic (will be prefixed with resource_prefix)"
  type        = string
  default     = "content-processing"
}

variable "pubsub_subscription_ack_deadline" {
  description = "Acknowledgment deadline for Pub/Sub subscription in seconds"
  type        = number
  default     = 600
  
  validation {
    condition     = var.pubsub_subscription_ack_deadline >= 10 && var.pubsub_subscription_ack_deadline <= 600
    error_message = "Ack deadline must be between 10 and 600 seconds."
  }
}

variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub subscription"
  type        = string
  default     = "604800s" # 7 days
}

# BigQuery Configuration
variable "bigquery_dataset_name" {
  description = "Name for the BigQuery dataset (will be prefixed with resource_prefix)"
  type        = string
  default     = "content_analytics"
}

variable "bigquery_dataset_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "US"
}

variable "bigquery_table_expiration_ms" {
  description = "Default table expiration time in milliseconds (null for no expiration)"
  type        = number
  default     = null
}

# Cloud Run Worker Pool Configuration
variable "worker_pool_name" {
  description = "Name for the Cloud Run worker pool (will be prefixed with resource_prefix)"
  type        = string
  default     = "translation-workers"
}

variable "worker_pool_cpu" {
  description = "CPU allocation for worker pool instances"
  type        = string
  default     = "2"
  
  validation {
    condition     = contains(["1", "2", "4", "8"], var.worker_pool_cpu)
    error_message = "CPU must be one of: 1, 2, 4, 8."
  }
}

variable "worker_pool_memory" {
  description = "Memory allocation for worker pool instances"
  type        = string
  default     = "4Gi"
  
  validation {
    condition     = can(regex("^[1-9][0-9]*Gi$", var.worker_pool_memory))
    error_message = "Memory must be specified in Gi format (e.g., 4Gi)."
  }
}

variable "worker_pool_min_instances" {
  description = "Minimum number of worker pool instances"
  type        = number
  default     = 1
  
  validation {
    condition     = var.worker_pool_min_instances >= 0 && var.worker_pool_min_instances <= 100
    error_message = "Min instances must be between 0 and 100."
  }
}

variable "worker_pool_max_instances" {
  description = "Maximum number of worker pool instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.worker_pool_max_instances >= 1 && var.worker_pool_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "container_image" {
  description = "Container image for the translation worker (will be built if not provided)"
  type        = string
  default     = ""
}

# Translation API Configuration
variable "enable_translation_api" {
  description = "Whether to enable the Cloud Translation API"
  type        = bool
  default     = true
}

variable "translation_model_location" {
  description = "Location for custom translation models"
  type        = string
  default     = "us-central1"
}

# IAM Configuration
variable "service_account_name" {
  description = "Name for the worker service account (will be prefixed with resource_prefix)"
  type        = string
  default     = "translation-worker"
}

# Monitoring and Logging
variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring for resources"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Whether to enable Cloud Logging for resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Network Configuration
variable "vpc_network_name" {
  description = "Name for the VPC network (will be prefixed with resource_prefix)"
  type        = string
  default     = "translation-network"
}

variable "subnet_name" {
  description = "Name for the subnet (will be prefixed with resource_prefix)"
  type        = string
  default     = "translation-subnet"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/24"
  
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid CIDR block."
  }
}

# Security Configuration
variable "enable_private_google_access" {
  description = "Whether to enable private Google access for the subnet"
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Whether to enable VPC flow logs"
  type        = bool
  default     = false
}

# Cost Optimization
variable "enable_preemptible_instances" {
  description = "Whether to use preemptible instances for cost optimization (not recommended for production)"
  type        = bool
  default     = false
}

# Additional APIs to enable
variable "additional_apis" {
  description = "Additional Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "translate.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "artifactregistry.googleapis.com"
  ]
}

# Labels for resource organization
variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "content-optimization"
  }
}