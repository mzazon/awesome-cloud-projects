# Variables for License Compliance Scanner Infrastructure
# This file defines all configurable parameters for the Terraform deployment

# Core GCP Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The GCP zone for resource deployment"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., us-central1-a)."
  }
}

# Environment and Naming Configuration
variable "environment" {
  description = "Environment name for resource labeling and naming"
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
  default     = "license-scanner"
  
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{2,15}$", var.resource_prefix))
    error_message = "Resource prefix must be 3-16 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

# Cloud Storage Configuration
variable "bucket_location" {
  description = "Location for the Cloud Storage bucket (regional or multi-regional)"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "ASIA",
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.bucket_location)
    error_message = "Bucket location must be a valid GCP location."
  }
}

variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the Cloud Storage bucket for audit compliance"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age" {
  description = "Age in days after which to delete old report versions"
  type        = number
  default     = 365
  
  validation {
    condition     = var.bucket_lifecycle_age >= 30 && var.bucket_lifecycle_age <= 3650
    error_message = "Bucket lifecycle age must be between 30 and 3650 days."
  }
}

# Cloud Source Repository Configuration
variable "repository_name" {
  description = "Name for the Cloud Source Repository"
  type        = string
  default     = "sample-app"
  
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{2,30}$", var.repository_name))
    error_message = "Repository name must be 3-31 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

# Cloud Function Configuration
variable "function_name" {
  description = "Name for the license scanner Cloud Function"
  type        = string
  default     = "license-scanner"
  
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{2,30}$", var.function_name))
    error_message = "Function name must be 3-31 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "python312"
  
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312",
      "nodejs18", "nodejs20", "go121", "java17", "java21"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 512
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 120
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Function max instances must be between 1 and 3000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Function min instances must be between 0 and 1000."
  }
}

# Cloud Scheduler Configuration
variable "daily_scan_schedule" {
  description = "Cron schedule for daily license scans (default: weekdays at 9 AM EST)"
  type        = string
  default     = "0 9 * * 1-5"
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/A-Z]+$", var.daily_scan_schedule))
    error_message = "Daily scan schedule must be a valid cron expression."
  }
}

variable "weekly_scan_schedule" {
  description = "Cron schedule for weekly comprehensive scans (default: Mondays at 6 AM EST)"
  type        = string
  default     = "0 6 * * 1"
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/A-Z]+$", var.weekly_scan_schedule))
    error_message = "Weekly scan schedule must be a valid cron expression."
  }
}

variable "scheduler_timezone" {
  description = "Timezone for Cloud Scheduler jobs"
  type        = string
  default     = "America/New_York"
  
  validation {
    condition = contains([
      "America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles",
      "Europe/London", "Europe/Paris", "Asia/Tokyo", "Asia/Singapore",
      "Australia/Sydney", "UTC"
    ], var.scheduler_timezone)
    error_message = "Scheduler timezone must be a valid IANA timezone."
  }
}

# Security and Access Configuration
variable "function_allow_unauthenticated" {
  description = "Allow unauthenticated access to the Cloud Function (should be false for production)"
  type        = bool
  default     = false
}

variable "create_service_account" {
  description = "Create a dedicated service account for the Cloud Function"
  type        = bool
  default     = true
}

variable "service_account_roles" {
  description = "IAM roles to assign to the Cloud Function service account"
  type        = list(string)
  default = [
    "roles/storage.objectAdmin",
    "roles/source.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ]
}

# API Services Configuration
variable "enable_apis" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "sourcerepo.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "appengine.googleapis.com"  # Required for Cloud Scheduler
  ]
}

# Sample Application Configuration
variable "create_sample_repo_content" {
  description = "Create sample application files in the repository"
  type        = bool
  default     = true
}

variable "sample_dependencies" {
  description = "Sample dependencies to include in the demo application"
  type = object({
    python = list(string)
    nodejs = list(string)
  })
  default = {
    python = [
      "Flask==3.0.3",
      "requests==2.32.3",
      "numpy==1.26.4",
      "click==8.1.7",
      "Jinja2==3.1.4",
      "scancode-toolkit==32.4.0",
      "license-expression==30.4.0"
    ]
    nodejs = [
      "express@^4.21.1",
      "lodash@^4.17.21",
      "moment@^2.30.1",
      "axios@^1.7.9"
    ]
  }
}

# Monitoring and Alerting Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for function metrics"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain Cloud Function logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653."
  }
}

# Networking Configuration
variable "vpc_connector_name" {
  description = "VPC connector name for Cloud Function (optional, for VPC access)"
  type        = string
  default     = ""
}

variable "ingress_settings" {
  description = "Ingress settings for the Cloud Function"
  type        = string
  default     = "ALLOW_ALL"
  
  validation {
    condition     = contains(["ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"], var.ingress_settings)
    error_message = "Ingress settings must be one of: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  }
}

variable "egress_settings" {
  description = "Egress settings for the Cloud Function"
  type        = string
  default     = "PRIVATE_RANGES_ONLY"
  
  validation {
    condition     = contains(["PRIVATE_RANGES_ONLY", "ALL"], var.egress_settings)
    error_message = "Egress settings must be one of: PRIVATE_RANGES_ONLY, ALL."
  }
}

# Cost Optimization
variable "function_cpu" {
  description = "CPU allocation for the Cloud Function (0.083, 0.167, 0.333, 0.583, 1)"
  type        = string
  default     = "0.167"
  
  validation {
    condition     = contains(["0.083", "0.167", "0.333", "0.583", "1"], var.function_cpu)
    error_message = "Function CPU must be one of: 0.083, 0.167, 0.333, 0.583, 1."
  }
}

# Tags and Labels
variable "resource_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default = {
    component = "license-compliance"
    owner     = "devops-team"
    purpose   = "security-scanning"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.resource_labels : can(regex("^[a-z][-_a-z0-9]*$", k)) && can(regex("^[-_a-z0-9]*$", v))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, hyphens, and underscores."
  }
}