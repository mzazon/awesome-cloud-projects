# Variable definitions for GCP Code Quality Automation Infrastructure

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "repo_name" {
  description = "Name for the Cloud Source Repository"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.repo_name)) || var.repo_name == ""
    error_message = "Repository name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "registry_name" {
  description = "Name for the Artifact Registry repository"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.registry_name)) || var.registry_name == ""
    error_message = "Registry name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "build_trigger_name" {
  description = "Name for the Cloud Build trigger"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-_]*[a-zA-Z0-9]$", var.build_trigger_name)) || var.build_trigger_name == ""
    error_message = "Build trigger name must start with a letter, contain only letters, numbers, hyphens, and underscores, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and organization"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "enable_vulnerability_scanning" {
  description = "Enable vulnerability scanning for Artifact Registry"
  type        = bool
  default     = true
}

variable "enable_container_analysis" {
  description = "Enable Container Analysis API for security scanning"
  type        = bool
  default     = true
}

variable "build_timeout" {
  description = "Timeout for Cloud Build jobs in seconds"
  type        = string
  default     = "1200s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.build_timeout))
    error_message = "Build timeout must be in seconds format (e.g., '1200s')."
  }
}

variable "machine_type" {
  description = "Machine type for Cloud Build workers"
  type        = string
  default     = "E2_HIGHCPU_8"
  validation {
    condition = contains([
      "E2_HIGHCPU_8", "E2_HIGHCPU_32", "E2_HIGHMEM_2", "E2_HIGHMEM_4", "E2_HIGHMEM_8", "E2_HIGHMEM_16",
      "N1_HIGHCPU_8", "N1_HIGHCPU_32", "N1_HIGHMEM_2", "N1_HIGHMEM_4", "N1_HIGHMEM_8", "N1_HIGHMEM_16"
    ], var.machine_type)
    error_message = "Machine type must be a valid Cloud Build machine type."
  }
}

variable "artifact_retention_days" {
  description = "Number of days to retain build artifacts in Cloud Storage"
  type        = number
  default     = 30
  validation {
    condition     = var.artifact_retention_days >= 1 && var.artifact_retention_days <= 365
    error_message = "Artifact retention days must be between 1 and 365."
  }
}

variable "branch_patterns" {
  description = "Git branch patterns that trigger the build pipeline"
  type        = list(string)
  default     = ["^(main|develop|feature/.*)$"]
  validation {
    condition     = length(var.branch_patterns) > 0
    error_message = "At least one branch pattern must be specified."
  }
}

variable "enable_monitoring" {
  description = "Enable monitoring and alerting for the quality pipeline"
  type        = bool
  default     = true
}

variable "notification_channel" {
  description = "Email address for build notifications (optional)"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_channel)) || var.notification_channel == ""
    error_message = "Notification channel must be a valid email address or empty."
  }
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "purpose"    = "code-quality-automation"
  }
}