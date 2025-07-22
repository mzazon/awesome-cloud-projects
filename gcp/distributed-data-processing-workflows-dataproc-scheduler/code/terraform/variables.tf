# Variables for distributed data processing workflows infrastructure

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must be specified."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone."
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

variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.resource_suffix))
    error_message = "Resource suffix must contain only lowercase letters, numbers, and hyphens."
  }
}

# Storage variables
variable "storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "lifecycle_rules_enabled" {
  description = "Enable lifecycle management for Cloud Storage buckets"
  type        = bool
  default     = true
}

# Dataproc cluster variables
variable "cluster_name" {
  description = "Name for the Dataproc cluster template"
  type        = string
  default     = "sales-analytics-cluster"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.cluster_name))
    error_message = "Cluster name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "worker_count" {
  description = "Number of worker nodes in the Dataproc cluster"
  type        = number
  default     = 2
  validation {
    condition     = var.worker_count >= 0 && var.worker_count <= 100
    error_message = "Worker count must be between 0 and 100."
  }
}

variable "max_workers" {
  description = "Maximum number of worker nodes for autoscaling"
  type        = number
  default     = 4
  validation {
    condition     = var.max_workers >= var.worker_count && var.max_workers <= 100
    error_message = "Max workers must be greater than or equal to worker count and less than or equal to 100."
  }
}

variable "worker_machine_type" {
  description = "Machine type for Dataproc worker nodes"
  type        = string
  default     = "e2-standard-4"
}

variable "worker_disk_size" {
  description = "Disk size for worker nodes in GB"
  type        = number
  default     = 50
  validation {
    condition     = var.worker_disk_size >= 10 && var.worker_disk_size <= 65536
    error_message = "Worker disk size must be between 10 and 65536 GB."
  }
}

variable "master_machine_type" {
  description = "Machine type for Dataproc master node"
  type        = string
  default     = "e2-standard-2"
}

variable "master_disk_size" {
  description = "Disk size for master node in GB"
  type        = number
  default     = 50
  validation {
    condition     = var.master_disk_size >= 10 && var.master_disk_size <= 65536
    error_message = "Master disk size must be between 10 and 65536 GB."
  }
}

variable "dataproc_image_version" {
  description = "Dataproc image version"
  type        = string
  default     = "2.1-debian11"
}

variable "enable_autoscaling" {
  description = "Enable autoscaling for the Dataproc cluster"
  type        = bool
  default     = true
}

variable "enable_ip_alias" {
  description = "Enable IP alias for the Dataproc cluster"
  type        = bool
  default     = true
}

# BigQuery variables
variable "bigquery_dataset_name" {
  description = "Name for the BigQuery dataset"
  type        = string
  default     = "analytics_results"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.bigquery_dataset_name))
    error_message = "BigQuery dataset name must contain only letters, numbers, and underscores."
  }
}

variable "bigquery_table_name" {
  description = "Name for the BigQuery table"
  type        = string
  default     = "sales_summary"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.bigquery_table_name))
    error_message = "BigQuery table name must contain only letters, numbers, and underscores."
  }
}

variable "bigquery_dataset_description" {
  description = "Description for the BigQuery dataset"
  type        = string
  default     = "Sales analytics results from Dataproc processing"
}

# Cloud Scheduler variables
variable "workflow_name" {
  description = "Name for the Dataproc workflow template"
  type        = string
  default     = "sales-analytics-workflow"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.workflow_name))
    error_message = "Workflow name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "scheduler_job_name" {
  description = "Name for the Cloud Scheduler job"
  type        = string
  default     = "sales-analytics-daily"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.scheduler_job_name))
    error_message = "Scheduler job name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "schedule_expression" {
  description = "Cron expression for the Cloud Scheduler job"
  type        = string
  default     = "0 2 * * *"
  validation {
    condition     = can(regex("^[0-9*/-,]+ [0-9*/-,]+ [0-9*/-,]+ [0-9*/-,]+ [0-9*/-,]+$", var.schedule_expression))
    error_message = "Schedule expression must be a valid cron expression."
  }
}

variable "scheduler_timezone" {
  description = "Timezone for the Cloud Scheduler job"
  type        = string
  default     = "America/New_York"
}

variable "scheduler_description" {
  description = "Description for the Cloud Scheduler job"
  type        = string
  default     = "Daily sales analytics processing workflow"
}

# Service account variables
variable "service_account_name" {
  description = "Name for the Dataproc service account"
  type        = string
  default     = "dataproc-scheduler"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.service_account_name))
    error_message = "Service account name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "service_account_display_name" {
  description = "Display name for the Dataproc service account"
  type        = string
  default     = "Dataproc Workflow Scheduler"
}

# Labels and tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    project     = "dataproc-workflows"
    managed-by  = "terraform"
  }
}

# Network variables
variable "network" {
  description = "The VPC network to use for Dataproc cluster"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "The subnetwork to use for Dataproc cluster"
  type        = string
  default     = ""
}

# API enablement
variable "enable_apis" {
  description = "Enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "required_apis" {
  description = "List of required Google Cloud APIs"
  type        = list(string)
  default = [
    "dataproc.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com"
  ]
}