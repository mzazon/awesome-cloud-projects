# Project Configuration
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
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Organization Configuration
variable "organization_id" {
  description = "The GCP organization ID for Security Command Center"
  type        = string
  default     = ""
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "accessibility-compliance"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
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

# Document AI Configuration
variable "document_ai_processor_display_name" {
  description = "Display name for the Document AI processor"
  type        = string
  default     = "accessibility-content-processor"
}

variable "document_ai_processor_type" {
  description = "Type of Document AI processor to create"
  type        = string
  default     = "OCR_PROCESSOR"
  validation {
    condition = contains([
      "OCR_PROCESSOR", "FORM_PARSER_PROCESSOR", "DOCUMENT_OCR_PROCESSOR"
    ], var.document_ai_processor_type)
    error_message = "Processor type must be a valid Document AI processor type."
  }
}

# Cloud Build Configuration
variable "github_repo_owner" {
  description = "GitHub repository owner for build triggers"
  type        = string
  default     = ""
}

variable "github_repo_name" {
  description = "GitHub repository name for build triggers"
  type        = string
  default     = ""
}

variable "build_trigger_branch_pattern" {
  description = "Branch pattern for build triggers"
  type        = string
  default     = "^main$"
}

variable "build_config_filename" {
  description = "Filename of the Cloud Build configuration"
  type        = string
  default     = "cloudbuild.yaml"
}

# Storage Configuration
variable "storage_bucket_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "storage_bucket_storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_bucket_storage_class)
    error_message = "Storage class must be a valid Cloud Storage class."
  }
}

variable "storage_lifecycle_age" {
  description = "Age in days after which objects are deleted"
  type        = number
  default     = 90
  validation {
    condition     = var.storage_lifecycle_age > 0 && var.storage_lifecycle_age <= 365
    error_message = "Storage lifecycle age must be between 1 and 365 days."
  }
}

# Security Command Center Configuration
variable "scc_source_display_name" {
  description = "Display name for Security Command Center source"
  type        = string
  default     = "Accessibility Compliance Scanner"
}

variable "scc_source_description" {
  description = "Description for Security Command Center source"
  type        = string
  default     = "Automated WCAG compliance monitoring"
}

variable "scc_notification_description" {
  description = "Description for Security Command Center notifications"
  type        = string
  default     = "Accessibility compliance alerts"
}

# Cloud Functions Configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python39"
  validation {
    condition = contains([
      "python39", "python310", "python311", "nodejs16", "nodejs18", "nodejs20"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = number
  default     = 256
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (in seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

# Resource Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "accessibility-compliance"
    managed-by  = "terraform"
    environment = "dev"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k))])
    error_message = "Label keys must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Notification Configuration
variable "enable_email_notifications" {
  description = "Enable email notifications for compliance alerts"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for compliance notifications"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

# API Services Configuration
variable "enable_apis" {
  description = "List of APIs to enable"
  type        = list(string)
  default = [
    "documentai.googleapis.com",
    "cloudbuild.googleapis.com",
    "securitycenter.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]
}

# Build Substitutions
variable "build_substitutions" {
  description = "Additional substitutions for Cloud Build"
  type        = map(string)
  default     = {}
}