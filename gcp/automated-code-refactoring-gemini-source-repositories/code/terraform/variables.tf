# Variables for automated code refactoring infrastructure
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 6
    error_message = "Project ID must be at least 6 characters long."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "repository_name" {
  description = "Name of the Source Repository for code storage"
  type        = string
  default     = "automated-refactoring-demo"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.repository_name))
    error_message = "Repository name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "build_trigger_name" {
  description = "Name of the Cloud Build trigger for automated refactoring"
  type        = string
  default     = "refactor-trigger"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.build_trigger_name))
    error_message = "Build trigger name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "service_account_name" {
  description = "Name of the service account for Cloud Build operations"
  type        = string
  default     = "refactor-service-account"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.service_account_name))
    error_message = "Service account name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "branch_pattern" {
  description = "Git branch pattern to trigger builds (regex)"
  type        = string
  default     = "^main$"
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    purpose     = "automated-refactoring"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*[a-z0-9]$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must follow GCP labeling conventions."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "build_timeout" {
  description = "Timeout for Cloud Build operations (in seconds)"
  type        = number
  default     = 1200
  
  validation {
    condition     = var.build_timeout >= 60 && var.build_timeout <= 7200
    error_message = "Build timeout must be between 60 and 7200 seconds."
  }
}

variable "build_machine_type" {
  description = "Machine type for Cloud Build workers"
  type        = string
  default     = "E2_HIGHCPU_8"
  
  validation {
    condition = contains([
      "E2_HIGHCPU_8", "E2_HIGHCPU_32", "E2_HIGHMEM_2", "E2_HIGHMEM_4",
      "E2_MEDIUM", "N1_HIGHCPU_8", "N1_HIGHCPU_32"
    ], var.build_machine_type)
    error_message = "Machine type must be a valid Cloud Build machine type."
  }
}

variable "log_bucket" {
  description = "Cloud Storage bucket for build logs (optional)"
  type        = string
  default     = ""
}

variable "substitutions" {
  description = "Build substitution variables"
  type        = map(string)
  default = {
    _REFACTOR_MODE = "auto"
    _AI_MODEL      = "gemini-1.5-pro"
  }
}