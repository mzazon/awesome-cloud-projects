# Variables for ML Pipeline Governance Infrastructure
# This file defines all configurable parameters for the ML governance solution

variable "project_id" {
  description = "Google Cloud project ID for deploying ML governance infrastructure"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-southeast1", "asia-northeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for deploying compute resources"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "ml-gov"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and be 2-21 characters long."
  }
}

# Hyperdisk ML Configuration
variable "hyperdisk_size_gb" {
  description = "Size of Hyperdisk ML volume in GB"
  type        = number
  default     = 1000
  validation {
    condition     = var.hyperdisk_size_gb >= 100 && var.hyperdisk_size_gb <= 65536
    error_message = "Hyperdisk ML size must be between 100 GB and 65,536 GB."
  }
}

variable "hyperdisk_provisioned_throughput" {
  description = "Provisioned throughput for Hyperdisk ML in MiB/s"
  type        = number
  default     = 10000
  validation {
    condition     = var.hyperdisk_provisioned_throughput >= 1000 && var.hyperdisk_provisioned_throughput <= 50000
    error_message = "Hyperdisk ML provisioned throughput must be between 1,000 and 50,000 MiB/s."
  }
}

# Compute Instance Configuration
variable "machine_type" {
  description = "Machine type for ML training instance"
  type        = string
  default     = "n1-standard-8"
  validation {
    condition = contains([
      "n1-standard-4", "n1-standard-8", "n1-standard-16", "n1-standard-32",
      "n2-standard-4", "n2-standard-8", "n2-standard-16", "n2-standard-32",
      "c2-standard-4", "c2-standard-8", "c2-standard-16", "c2-standard-30"
    ], var.machine_type)
    error_message = "Machine type must be a valid Google Compute Engine machine type suitable for ML workloads."
  }
}

variable "instance_image_family" {
  description = "OS image family for the compute instance"
  type        = string
  default     = "debian-11"
}

variable "instance_image_project" {
  description = "Project containing the OS image"
  type        = string
  default     = "debian-cloud"
}

# ML Model Configuration
variable "model_display_name" {
  description = "Display name for the ML model in Vertex AI Model Registry"
  type        = string
  default     = "governance-demo-model"
}

variable "model_description" {
  description = "Description for the ML model"
  type        = string
  default     = "ML model with automated governance tracking and compliance validation"
}

variable "model_container_image_uri" {
  description = "Container image URI for model serving"
  type        = string
  default     = "gcr.io/cloud-aiplatform/prediction/sklearn-cpu.1-0:latest"
}

# Storage Configuration
variable "storage_class" {
  description = "Storage class for training data bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_versioning_enabled" {
  description = "Enable versioning on the training data bucket"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age_days" {
  description = "Number of days after which to transition objects to nearline storage"
  type        = number
  default     = 30
  validation {
    condition     = var.bucket_lifecycle_age_days > 0 && var.bucket_lifecycle_age_days <= 365
    error_message = "Bucket lifecycle age must be between 1 and 365 days."
  }
}

# Monitoring Configuration
variable "monitoring_notification_channels" {
  description = "List of notification channel IDs for monitoring alerts"
  type        = list(string)
  default     = []
}

variable "enable_advanced_monitoring" {
  description = "Enable advanced monitoring and custom metrics"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_private_google_access" {
  description = "Enable private Google access for compute instances"
  type        = bool
  default     = true
}

variable "enable_ip_forwarding" {
  description = "Enable IP forwarding on compute instances"
  type        = bool
  default     = false
}

variable "allowed_source_ranges" {
  description = "Source IP ranges allowed to access compute instances"
  type        = list(string)
  default     = ["10.0.0.0/8"]
  validation {
    condition = alltrue([
      for range in var.allowed_source_ranges : can(cidrhost(range, 0))
    ])
    error_message = "All source ranges must be valid CIDR blocks."
  }
}

# Tags and Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "ml-governance"
    managed-by  = "terraform"
    component   = "ml-pipeline"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]{1,63}$", k))
    ])
    error_message = "Label keys must contain only lowercase letters, numbers, underscores, and hyphens, and be 1-63 characters long."
  }
}

variable "network_tags" {
  description = "Network tags to apply to compute instances"
  type        = list(string)
  default     = ["ml-training", "governance-enabled"]
  validation {
    condition = alltrue([
      for tag in var.network_tags : can(regex("^[a-z0-9-]{1,63}$", tag))
    ])
    error_message = "Network tags must contain only lowercase letters, numbers, and hyphens, and be 1-63 characters long."
  }
}

# Workflow Configuration
variable "workflow_schedule" {
  description = "Cron schedule for automated governance workflow execution"
  type        = string
  default     = "0 9 * * 1" # Monday at 9 AM
  validation {
    condition     = can(regex("^[0-9*/-]+ [0-9*/-]+ [0-9*/-]+ [0-9*/-]+ [0-9*/-]+$", var.workflow_schedule))
    error_message = "Workflow schedule must be a valid cron expression."
  }
}

variable "enable_workflow_scheduling" {
  description = "Enable scheduled execution of governance workflow"
  type        = bool
  default     = false
}