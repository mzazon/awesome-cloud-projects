# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Variables for Data Quality Monitoring with Dataform and Cloud Scheduler
# This file defines all configurable parameters for the solution

# Project Configuration
variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Environment Configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# BigQuery Configuration
variable "dataset_name" {
  description = "Name of the BigQuery dataset for sample data"
  type        = string
  default     = "sample_ecommerce"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.dataset_name))
    error_message = "Dataset name must contain only letters, numbers, and underscores."
  }
}

variable "dataset_location" {
  description = "Location for BigQuery datasets"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "asia-east1", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4"
    ], var.dataset_location)
    error_message = "Dataset location must be a valid BigQuery location."
  }
}

variable "assertion_dataset_name" {
  description = "Name of the BigQuery dataset for data quality assertions"
  type        = string
  default     = "dataform_assertions"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.assertion_dataset_name))
    error_message = "Assertion dataset name must contain only letters, numbers, and underscores."
  }
}

# Dataform Configuration
variable "dataform_repository_name" {
  description = "Name of the Dataform repository"
  type        = string
  default     = "data-quality-repo"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.dataform_repository_name))
    error_message = "Repository name must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "dataform_workspace_name" {
  description = "Name of the Dataform workspace"
  type        = string
  default     = "quality-workspace"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.dataform_workspace_name))
    error_message = "Workspace name must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "dataform_release_config_name" {
  description = "Name of the Dataform release configuration"
  type        = string
  default     = "quality-monitoring-release"
}

# Cloud Scheduler Configuration
variable "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job"
  type        = string
  default     = "dataform-quality-job"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.scheduler_job_name))
    error_message = "Scheduler job name must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "scheduler_frequency" {
  description = "Cron expression for scheduler frequency (default: every 6 hours)"
  type        = string
  default     = "0 */6 * * *"
  validation {
    condition     = can(regex("^[0-9*,-/ ]+$", var.scheduler_frequency))
    error_message = "Scheduler frequency must be a valid cron expression."
  }
}

variable "scheduler_timezone" {
  description = "Timezone for the scheduler job"
  type        = string
  default     = "UTC"
}

variable "scheduler_description" {
  description = "Description for the Cloud Scheduler job"
  type        = string
  default     = "Automated data quality monitoring using Dataform workflows"
}

# Service Account Configuration
variable "service_account_name" {
  description = "Name of the service account for Cloud Scheduler and Dataform"
  type        = string
  default     = "dataform-scheduler-sa"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_account_name))
    error_message = "Service account name must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "service_account_display_name" {
  description = "Display name for the service account"
  type        = string
  default     = "Dataform Scheduler Service Account"
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring integration for data quality alerts"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for data quality alert notifications"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "alert_threshold" {
  description = "Threshold for data quality failure alerts (number of failures per 5 minutes)"
  type        = number
  default     = 5
  validation {
    condition     = var.alert_threshold >= 0
    error_message = "Alert threshold must be a non-negative number."
  }
}

# Sample Data Configuration
variable "create_sample_data" {
  description = "Whether to create sample data for testing data quality assertions"
  type        = bool
  default     = true
}

variable "sample_customers_count" {
  description = "Number of sample customer records to create"
  type        = number
  default     = 5
  validation {
    condition     = var.sample_customers_count >= 0 && var.sample_customers_count <= 1000
    error_message = "Sample customers count must be between 0 and 1000."
  }
}

variable "sample_orders_count" {
  description = "Number of sample order records to create"
  type        = number
  default     = 5
  validation {
    condition     = var.sample_orders_count >= 0 && var.sample_orders_count <= 1000
    error_message = "Sample orders count must be between 0 and 1000."
  }
}

# Advanced Configuration
variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs automatically"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

# Retry Configuration
variable "scheduler_retry_count" {
  description = "Number of retry attempts for failed scheduler jobs"
  type        = number
  default     = 3
  validation {
    condition     = var.scheduler_retry_count >= 0 && var.scheduler_retry_count <= 5
    error_message = "Scheduler retry count must be between 0 and 5."
  }
}

variable "scheduler_attempt_deadline" {
  description = "Maximum duration for scheduler job attempts (in seconds)"
  type        = string
  default     = "320s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.scheduler_attempt_deadline))
    error_message = "Scheduler attempt deadline must be in format 'Ns' where N is a number."
  }
}