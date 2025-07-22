# Project Configuration
variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+(-[a-z]+)*-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "Google Cloud zone for resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z]+(-[a-z]+)*-[a-z]+[0-9]+-[a-z]+$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "batch-processing"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
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

# Artifact Registry Configuration
variable "registry_repository_id" {
  description = "Artifact Registry repository ID for container images"
  type        = string
  default     = "batch-registry"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.registry_repository_id))
    error_message = "Repository ID must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "registry_format" {
  description = "Artifact Registry repository format"
  type        = string
  default     = "DOCKER"
  
  validation {
    condition     = contains(["DOCKER", "MAVEN", "NPM", "PYTHON", "APT", "YUM", "GENERIC"], var.registry_format)
    error_message = "Repository format must be one of: DOCKER, MAVEN, NPM, PYTHON, APT, YUM, GENERIC."
  }
}

# Cloud Storage Configuration
variable "bucket_name" {
  description = "Cloud Storage bucket name for batch processing data"
  type        = string
  default     = ""
  
  validation {
    condition     = var.bucket_name == "" || can(regex("^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$", var.bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, dots, dashes, and underscores."
  }
}

variable "bucket_location" {
  description = "Cloud Storage bucket location"
  type        = string
  default     = "US"
  
  validation {
    condition     = contains(["US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", "europe-west1", "asia-east1"], var.bucket_location)
    error_message = "Bucket location must be a valid Google Cloud Storage location."
  }
}

variable "bucket_storage_class" {
  description = "Cloud Storage bucket storage class"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# Cloud Run Job Configuration
variable "job_name" {
  description = "Cloud Run Job name"
  type        = string
  default     = "data-processor"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.job_name))
    error_message = "Job name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "job_task_count" {
  description = "Number of tasks to run in parallel"
  type        = number
  default     = 1
  
  validation {
    condition     = var.job_task_count >= 1 && var.job_task_count <= 10000
    error_message = "Task count must be between 1 and 10000."
  }
}

variable "job_parallelism" {
  description = "Number of tasks to run simultaneously"
  type        = number
  default     = 1
  
  validation {
    condition     = var.job_parallelism >= 1 && var.job_parallelism <= 1000
    error_message = "Parallelism must be between 1 and 1000."
  }
}

variable "job_task_timeout" {
  description = "Maximum execution time for each task in seconds"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.job_task_timeout >= 1 && var.job_task_timeout <= 86400
    error_message = "Task timeout must be between 1 and 86400 seconds (24 hours)."
  }
}

variable "job_max_retries" {
  description = "Maximum number of retry attempts for failed tasks"
  type        = number
  default     = 3
  
  validation {
    condition     = var.job_max_retries >= 0 && var.job_max_retries <= 10
    error_message = "Max retries must be between 0 and 10."
  }
}

variable "job_cpu" {
  description = "CPU allocation for each task"
  type        = string
  default     = "1"
  
  validation {
    condition     = contains(["0.25", "0.5", "1", "2", "4", "8"], var.job_cpu)
    error_message = "CPU must be one of: 0.25, 0.5, 1, 2, 4, 8."
  }
}

variable "job_memory" {
  description = "Memory allocation for each task"
  type        = string
  default     = "2Gi"
  
  validation {
    condition     = can(regex("^[1-9][0-9]*[GM]i$", var.job_memory))
    error_message = "Memory must be specified in Gi or Mi format (e.g., 2Gi, 512Mi)."
  }
}

variable "container_image" {
  description = "Container image for the batch processing job"
  type        = string
  default     = ""
  
  validation {
    condition     = var.container_image == "" || can(regex("^[a-z0-9.-]+/[a-z0-9-]+/[a-z0-9-]+:[a-z0-9.-]+$", var.container_image))
    error_message = "Container image must be in the format: registry/project/image:tag."
  }
}

# Cloud Scheduler Configuration
variable "scheduler_job_name" {
  description = "Cloud Scheduler job name"
  type        = string
  default     = "batch-schedule"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.scheduler_job_name))
    error_message = "Scheduler job name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "scheduler_cron_schedule" {
  description = "Cron schedule for the batch processing job"
  type        = string
  default     = "0 * * * *"
  
  validation {
    condition     = can(regex("^[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+$", var.scheduler_cron_schedule))
    error_message = "Schedule must be a valid cron expression (e.g., '0 * * * *')."
  }
}

variable "scheduler_timezone" {
  description = "Timezone for the scheduler"
  type        = string
  default     = "America/New_York"
  
  validation {
    condition     = can(regex("^[A-Z][a-z]+/[A-Z][a-z_]+$", var.scheduler_timezone))
    error_message = "Timezone must be in the format: Continent/City (e.g., America/New_York)."
  }
}

variable "scheduler_description" {
  description = "Description for the Cloud Scheduler job"
  type        = string
  default     = "Automated batch processing job execution"
  
  validation {
    condition     = length(var.scheduler_description) <= 500
    error_message = "Description must be 500 characters or less."
  }
}

# Environment Variables for Batch Processing
variable "batch_environment_variables" {
  description = "Environment variables for the batch processing job"
  type        = map(string)
  default = {
    BATCH_SIZE = "10"
  }
  
  validation {
    condition     = can(keys(var.batch_environment_variables))
    error_message = "Environment variables must be a valid map of string key-value pairs."
  }
}

# Service Account Configuration
variable "service_account_id" {
  description = "Service account ID for the batch processing job"
  type        = string
  default     = "batch-processor-sa"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.service_account_id))
    error_message = "Service account ID must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "service_account_display_name" {
  description = "Display name for the service account"
  type        = string
  default     = "Batch Processor Service Account"
  
  validation {
    condition     = length(var.service_account_display_name) <= 100
    error_message = "Display name must be 100 characters or less."
  }
}

variable "service_account_description" {
  description = "Description for the service account"
  type        = string
  default     = "Service account for batch processing Cloud Run jobs"
  
  validation {
    condition     = length(var.service_account_description) <= 256
    error_message = "Description must be 256 characters or less."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable monitoring and alerting for batch processing"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653 (10 years)."
  }
}

# API Services Configuration
variable "enable_apis" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]
  
  validation {
    condition     = length(var.enable_apis) > 0
    error_message = "At least one API must be enabled."
  }
}

# Tags and Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    project     = "batch-processing"
    managed-by  = "terraform"
  }
  
  validation {
    condition     = can(keys(var.labels))
    error_message = "Labels must be a valid map of string key-value pairs."
  }
}

# Network Configuration (Optional)
variable "network_name" {
  description = "VPC network name (optional, uses default if not specified)"
  type        = string
  default     = "default"
}

variable "subnet_name" {
  description = "Subnet name (optional, uses default if not specified)"
  type        = string
  default     = "default"
}

# Build Configuration
variable "build_timeout" {
  description = "Build timeout in seconds"
  type        = number
  default     = 600
  
  validation {
    condition     = var.build_timeout >= 60 && var.build_timeout <= 7200
    error_message = "Build timeout must be between 60 and 7200 seconds."
  }
}

variable "build_machine_type" {
  description = "Machine type for Cloud Build"
  type        = string
  default     = "E2_STANDARD_2"
  
  validation {
    condition     = contains(["E2_STANDARD_2", "E2_STANDARD_4", "E2_STANDARD_8", "E2_STANDARD_16", "E2_STANDARD_32"], var.build_machine_type)
    error_message = "Machine type must be one of: E2_STANDARD_2, E2_STANDARD_4, E2_STANDARD_8, E2_STANDARD_16, E2_STANDARD_32."
  }
}