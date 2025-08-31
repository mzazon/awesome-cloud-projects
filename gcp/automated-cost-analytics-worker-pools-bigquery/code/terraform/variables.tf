# Variables for GCP Automated Cost Analytics Infrastructure
# This file defines all configurable parameters for the cost analytics solution

# Core Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for regional resources (Cloud Run, BigQuery dataset)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources (if needed)"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming Configuration
variable "name_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "cost-analytics"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name_prefix))
    error_message = "Name prefix must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment label for resource tagging (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# BigQuery Configuration
variable "dataset_location" {
  description = "Location for BigQuery dataset (should match region for optimal performance)"
  type        = string
  default     = "US"
}

variable "dataset_description" {
  description = "Description for the cost analytics BigQuery dataset"
  type        = string
  default     = "Automated cost analytics dataset for billing data processing and analysis"
}

variable "table_expiration_days" {
  description = "Number of days after which cost data tables expire (0 for no expiration)"
  type        = number
  default     = 0
  validation {
    condition     = var.table_expiration_days >= 0
    error_message = "Table expiration days must be non-negative."
  }
}

# Cloud Run Configuration
variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run instances (0.5, 1, 2, 4)"
  type        = string
  default     = "1"
  validation {
    condition     = contains(["0.5", "1", "2", "4"], var.cloud_run_cpu)
    error_message = "CPU must be one of: 0.5, 1, 2, 4."
  }
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run instances (512Mi, 1Gi, 2Gi, 4Gi, 8Gi)"
  type        = string
  default     = "1Gi"
  validation {
    condition = contains([
      "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.cloud_run_memory)
    error_message = "Memory must be one of: 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
  }
}

variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances (0 for serverless scaling)"
  type        = number
  default     = 0
  validation {
    condition     = var.cloud_run_min_instances >= 0 && var.cloud_run_min_instances <= 100
    error_message = "Minimum instances must be between 0 and 100."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances for scaling"
  type        = number
  default     = 10
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 1000
    error_message = "Maximum instances must be between 1 and 1000."
  }
}

variable "cloud_run_concurrency" {
  description = "Maximum number of concurrent requests per Cloud Run instance"
  type        = number
  default     = 10
  validation {
    condition     = var.cloud_run_concurrency >= 1 && var.cloud_run_concurrency <= 1000
    error_message = "Concurrency must be between 1 and 1000."
  }
}

variable "cloud_run_timeout" {
  description = "Request timeout for Cloud Run instances in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.cloud_run_timeout >= 1 && var.cloud_run_timeout <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

# Pub/Sub Configuration
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topic (e.g., '604800s' for 7 days)"
  type        = string
  default     = "604800s"
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscription in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

# Cloud Scheduler Configuration
variable "scheduler_cron_schedule" {
  description = "Cron schedule for automated cost processing (e.g., '0 1 * * *' for daily at 1 AM)"
  type        = string
  default     = "0 1 * * *"
}

variable "scheduler_timezone" {
  description = "Timezone for Cloud Scheduler jobs"
  type        = string
  default     = "America/New_York"
}

variable "scheduler_description" {
  description = "Description for the scheduled cost processing job"
  type        = string
  default     = "Daily automated cost analytics processing"
}

# Billing Configuration
variable "billing_account_id" {
  description = "Billing account ID for cost data access (optional, can be provided at runtime)"
  type        = string
  default     = ""
  sensitive   = true
}

# Security and IAM Configuration
variable "enable_apis" {
  description = "Whether to enable required GCP APIs automatically"
  type        = bool
  default     = true
}

variable "service_account_display_name" {
  description = "Display name for the cost analytics service account"
  type        = string
  default     = "Cost Analytics Worker"
}

# Monitoring and Logging Configuration
variable "enable_cloud_logging" {
  description = "Enable Cloud Logging for all resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs in Cloud Logging"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Resource Labels
variable "labels" {
  description = "A map of labels to assign to all resources"
  type        = map(string)
  default = {
    purpose     = "cost-analytics"
    managed-by  = "terraform"
    environment = "development"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k))
    ])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Container Image Configuration
variable "worker_container_image" {
  description = "Container image for the cost processing worker (will be built from source if not provided)"
  type        = string
  default     = ""
}

variable "build_container_locally" {
  description = "Whether to build the container image locally using Cloud Build"
  type        = bool
  default     = true
}

# Advanced Configuration
variable "enable_private_ip" {
  description = "Enable private IP for Cloud Run (requires VPC connector)"
  type        = bool
  default     = false
}

variable "vpc_connector_name" {
  description = "Name of VPC connector for private Cloud Run (required if enable_private_ip is true)"
  type        = string
  default     = ""
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for container image verification"
  type        = bool
  default     = false
}

variable "enable_vpc_access" {
  description = "Enable VPC access for Cloud Run service"
  type        = bool
  default     = false
}