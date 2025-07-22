# Input Variables for Enterprise ML Model Lifecycle Management
# This file defines all configurable parameters for the infrastructure deployment

# Core Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports AI/ML services."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "enterprise-ml"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.resource_prefix))
    error_message = "Resource prefix must be 3-21 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
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

# Cloud Workstations Configuration
variable "workstation_machine_type" {
  description = "Machine type for Cloud Workstations"
  type        = string
  default     = "n1-standard-8"
  
  validation {
    condition = contains([
      "n1-standard-4", "n1-standard-8", "n1-standard-16", "n1-standard-32",
      "n1-highmem-8", "n1-highmem-16", "n1-highcpu-16", "n1-highcpu-32"
    ], var.workstation_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type suitable for ML workloads."
  }
}

variable "workstation_disk_size" {
  description = "Persistent disk size for Cloud Workstations in GB"
  type        = number
  default     = 200
  
  validation {
    condition     = var.workstation_disk_size >= 100 && var.workstation_disk_size <= 10000
    error_message = "Workstation disk size must be between 100 and 10000 GB."
  }
}

variable "workstation_disk_type" {
  description = "Persistent disk type for Cloud Workstations"
  type        = string
  default     = "pd-ssd"
  
  validation {
    condition     = contains(["pd-standard", "pd-ssd", "pd-balanced"], var.workstation_disk_type)
    error_message = "Disk type must be one of: pd-standard, pd-ssd, pd-balanced."
  }
}

# AI Hypercomputer Configuration
variable "enable_tpu_training" {
  description = "Enable TPU resources for training workloads"
  type        = bool
  default     = true
}

variable "tpu_accelerator_type" {
  description = "TPU accelerator type for training"
  type        = string
  default     = "v5litepod-4"
  
  validation {
    condition = contains([
      "v5litepod-4", "v5litepod-8", "v5litepod-16", "v4-8", "v4-16", "v4-32"
    ], var.tpu_accelerator_type)
    error_message = "TPU accelerator type must be a valid Google Cloud TPU type."
  }
}

variable "enable_gpu_training" {
  description = "Enable GPU resources for training workloads"
  type        = bool
  default     = true
}

variable "gpu_machine_type" {
  description = "Machine type for GPU training instances"
  type        = string
  default     = "a3-highgpu-8g"
  
  validation {
    condition = contains([
      "a3-highgpu-8g", "a3-highgpu-16g", "a3-megagpu-8g", "n1-standard-16-k80x4",
      "n1-standard-32-v100x4", "n1-standard-96-v100x8"
    ], var.gpu_machine_type)
    error_message = "GPU machine type must be a valid Google Cloud GPU-enabled machine type."
  }
}

variable "gpu_accelerator_type" {
  description = "GPU accelerator type for training"
  type        = string
  default     = "nvidia-h100-80gb"
  
  validation {
    condition = contains([
      "nvidia-h100-80gb", "nvidia-a100-80gb", "nvidia-v100", "nvidia-k80", "nvidia-p4", "nvidia-t4"
    ], var.gpu_accelerator_type)
    error_message = "GPU accelerator type must be a valid Google Cloud GPU type."
  }
}

variable "gpu_accelerator_count" {
  description = "Number of GPU accelerators per training instance"
  type        = number
  default     = 8
  
  validation {
    condition     = var.gpu_accelerator_count >= 1 && var.gpu_accelerator_count <= 16
    error_message = "GPU accelerator count must be between 1 and 16."
  }
}

# Storage Configuration
variable "storage_class" {
  description = "Storage class for ML artifacts bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_storage_versioning" {
  description = "Enable versioning for ML artifacts bucket"
  type        = bool
  default     = true
}

variable "storage_lifecycle_age_days" {
  description = "Number of days after which to transition objects to cheaper storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.storage_lifecycle_age_days >= 1 && var.storage_lifecycle_age_days <= 365
    error_message = "Storage lifecycle age must be between 1 and 365 days."
  }
}

# BigQuery Configuration
variable "bigquery_dataset_location" {
  description = "Location for BigQuery dataset (should match region)"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west4", "asia-east1", "asia-northeast1"
    ], var.bigquery_dataset_location)
    error_message = "BigQuery dataset location must be a valid Google Cloud location."
  }
}

variable "bigquery_table_expiration_days" {
  description = "Number of days after which BigQuery tables expire"
  type        = number
  default     = 90
  
  validation {
    condition     = var.bigquery_table_expiration_days >= 1 && var.bigquery_table_expiration_days <= 365
    error_message = "BigQuery table expiration must be between 1 and 365 days."
  }
}

# Vertex AI Configuration
variable "vertex_ai_region" {
  description = "Region for Vertex AI resources (must support Vertex AI)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west4", "asia-east1", "asia-northeast1"
    ], var.vertex_ai_region)
    error_message = "Vertex AI region must support Vertex AI services."
  }
}

variable "vertex_ai_staging_bucket" {
  description = "Name of the staging bucket for Vertex AI pipelines (will be created if not exists)"
  type        = string
  default     = ""
}

# Artifact Registry Configuration
variable "artifact_registry_format" {
  description = "Format of the Artifact Registry repository"
  type        = string
  default     = "DOCKER"
  
  validation {
    condition     = contains(["DOCKER", "MAVEN", "NPM", "PYTHON", "APT", "YUM"], var.artifact_registry_format)
    error_message = "Artifact Registry format must be one of: DOCKER, MAVEN, NPM, PYTHON, APT, YUM."
  }
}

# Networking Configuration
variable "enable_private_google_access" {
  description = "Enable private Google access for the subnet"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs for network monitoring"
  type        = bool
  default     = true
}

# IAM Configuration
variable "workstation_service_account_roles" {
  description = "Additional IAM roles for the workstation service account"
  type        = list(string)
  default = [
    "roles/storage.objectAdmin",
    "roles/bigquery.dataEditor",
    "roles/aiplatform.user"
  ]
}

variable "training_service_account_roles" {
  description = "Additional IAM roles for the training service account"
  type        = list(string)
  default = [
    "roles/storage.objectAdmin",
    "roles/bigquery.dataEditor",
    "roles/aiplatform.user",
    "roles/artifactregistry.reader"
  ]
}

# Security Configuration
variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for container security"
  type        = bool
  default     = true
}

variable "enable_vulnerability_scanning" {
  description = "Enable vulnerability scanning for container images"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for ML infrastructure"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Cloud Logging for ML infrastructure"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Cost Management Configuration
variable "enable_budget_alerts" {
  description = "Enable budget alerts for cost management"
  type        = bool
  default     = true
}

variable "billing_account_name" {
  description = "Name of the billing account to use for budget alerts"
  type        = string
  default     = ""
}

variable "budget_amount" {
  description = "Budget amount in USD for cost monitoring"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.budget_amount >= 10 && var.budget_amount <= 100000
    error_message = "Budget amount must be between 10 and 100000 USD."
  }
}

variable "budget_alert_thresholds" {
  description = "Budget alert thresholds as percentages"
  type        = list(number)
  default     = [50, 75, 90, 100]
  
  validation {
    condition     = alltrue([for threshold in var.budget_alert_thresholds : threshold >= 1 && threshold <= 100])
    error_message = "Budget alert thresholds must be between 1 and 100 percent."
  }
}

# Tags and Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    "project"     = "enterprise-ml-lifecycle"
    "managed-by"  = "terraform"
    "cost-center" = "ml-engineering"
  }
  
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))])
    error_message = "Label keys must be 1-63 characters, start with a letter, and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Feature Flags
variable "enable_experimental_features" {
  description = "Enable experimental features (may incur additional costs)"
  type        = bool
  default     = false
}

variable "enable_multi_region_deployment" {
  description = "Enable multi-region deployment for high availability"
  type        = bool
  default     = false
}

variable "enable_disaster_recovery" {
  description = "Enable disaster recovery configuration"
  type        = bool
  default     = false
}