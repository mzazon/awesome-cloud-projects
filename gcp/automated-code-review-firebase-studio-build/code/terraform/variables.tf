# Variable definitions for the Automated Code Review Pipeline
# This file defines all customizable parameters for the infrastructure deployment

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for resource deployment"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone (e.g., us-central1-a)."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "resource_prefix" {
  description = "Prefix to add to all resource names for uniqueness"
  type        = string
  default     = "code-review"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

# Cloud Source Repositories Configuration
variable "repository_name" {
  description = "Name of the Cloud Source Repository"
  type        = string
  default     = ""
  validation {
    condition     = var.repository_name == "" || can(regex("^[a-zA-Z][a-zA-Z0-9-_]*$", var.repository_name))
    error_message = "Repository name must start with a letter and contain only letters, numbers, hyphens, and underscores."
  }
}

# Cloud Build Configuration
variable "build_timeout" {
  description = "Cloud Build timeout in seconds"
  type        = string
  default     = "1200s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.build_timeout))
    error_message = "Build timeout must be in seconds format (e.g., 1200s)."
  }
}

variable "build_machine_type" {
  description = "Machine type for Cloud Build"
  type        = string
  default     = "E2_MEDIUM"
  validation {
    condition = contains([
      "E2_MEDIUM", "E2_HIGHCPU_8", "E2_HIGHCPU_32", "E2_HIGHMEM_2", "E2_HIGHMEM_4", "E2_HIGHMEM_8"
    ], var.build_machine_type)
    error_message = "Build machine type must be a valid Cloud Build machine type."
  }
}

variable "trigger_branches" {
  description = "List of branch patterns that should trigger builds"
  type        = list(string)
  default     = ["^main$", "^feature/.*$", "^develop$"]
  validation {
    condition     = length(var.trigger_branches) > 0
    error_message = "At least one trigger branch pattern must be specified."
  }
}

# Cloud Tasks Configuration
variable "task_queue_max_concurrent_dispatches" {
  description = "Maximum number of concurrent dispatches for the task queue"
  type        = number
  default     = 10
  validation {
    condition     = var.task_queue_max_concurrent_dispatches >= 1 && var.task_queue_max_concurrent_dispatches <= 500
    error_message = "Max concurrent dispatches must be between 1 and 500."
  }
}

variable "task_queue_max_attempts" {
  description = "Maximum number of retry attempts for failed tasks"
  type        = number
  default     = 3
  validation {
    condition     = var.task_queue_max_attempts >= 1 && var.task_queue_max_attempts <= 100
    error_message = "Max attempts must be between 1 and 100."
  }
}

variable "task_queue_max_retry_duration" {
  description = "Maximum retry duration for tasks"
  type        = string
  default     = "300s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.task_queue_max_retry_duration))
    error_message = "Max retry duration must be in seconds format (e.g., 300s)."
  }
}

# Cloud Functions Configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = number
  default     = 1024
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312",
      "nodejs16", "nodejs18", "nodejs20", "go119", "go120", "go121"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

# AI/ML Configuration
variable "enable_gemini_integration" {
  description = "Enable Gemini AI integration for code review"
  type        = bool
  default     = true
}

variable "gemini_model" {
  description = "Gemini model to use for code analysis"
  type        = string
  default     = "gemini-1.5-pro"
  validation {
    condition = contains([
      "gemini-1.5-pro", "gemini-1.5-flash", "gemini-pro"
    ], var.gemini_model)
    error_message = "Gemini model must be a supported model version."
  }
}

# Firebase Configuration
variable "firebase_project_id" {
  description = "Firebase project ID (if different from Google Cloud project)"
  type        = string
  default     = ""
  validation {
    condition     = var.firebase_project_id == "" || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.firebase_project_id))
    error_message = "Firebase project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_firebase_studio" {
  description = "Enable Firebase Studio workspace configuration"
  type        = bool
  default     = true
}

# Storage Configuration
variable "storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "storage_location" {
  description = "Location for Cloud Storage buckets"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", "europe-west1", "asia-east1"
    ], var.storage_location)
    error_message = "Storage location must be a valid Cloud Storage location."
  }
}

# Monitoring and Observability
variable "enable_cloud_monitoring" {
  description = "Enable Cloud Monitoring for the pipeline"
  type        = bool
  default     = true
}

variable "enable_cloud_logging" {
  description = "Enable Cloud Logging for detailed logging"
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

# Security Configuration
variable "enable_private_google_access" {
  description = "Enable Private Google Access for compute resources"
  type        = bool
  default     = true
}

variable "enable_cloud_armor" {
  description = "Enable Cloud Armor for DDoS protection"
  type        = bool
  default     = false
}

# Cost Management
variable "enable_budget_alerts" {
  description = "Enable budget alerts for cost management"
  type        = bool
  default     = true
}

variable "monthly_budget_amount" {
  description = "Monthly budget amount in USD for alerts"
  type        = number
  default     = 50
  validation {
    condition     = var.monthly_budget_amount > 0
    error_message = "Monthly budget amount must be greater than 0."
  }
}

# Tags and Labels
variable "additional_labels" {
  description = "Additional labels to apply to resources"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : can(regex("^[a-z][a-z0-9_-]*$", k))
    ])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Development Configuration
variable "enable_debug_mode" {
  description = "Enable debug mode for development and troubleshooting"
  type        = bool
  default     = false
}

variable "force_destroy_buckets" {
  description = "Allow Terraform to destroy buckets with objects (use with caution)"
  type        = bool
  default     = false
}