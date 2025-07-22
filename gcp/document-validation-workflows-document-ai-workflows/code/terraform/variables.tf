# Input Variables for Document Validation Workflows Infrastructure
# This file defines all configurable parameters for the document validation
# solution, allowing for flexible deployments across different environments.

variable "project_id" {
  type        = string
  description = "The GCP project ID where resources will be created"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{4,28}[a-z0-9])$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  type        = string
  description = "The GCP region for regional resources"
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports Document AI."
  }
}

variable "zone" {
  type        = string
  description = "The GCP zone for zonal resources"
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., us-central1-a)."
  }
}

variable "resource_name_prefix" {
  type        = string
  description = "Prefix for all resource names to ensure uniqueness"
  default     = "doc-validation"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,20})$", var.resource_name_prefix))
    error_message = "Resource name prefix must start with a letter and contain only lowercase letters, numbers, and hyphens (max 21 characters)."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., dev, test, prod)"
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

# Document AI Configuration Variables
variable "document_ai_location" {
  type        = string
  description = "Location for Document AI processors (us, eu, asia)"
  default     = "us"
  
  validation {
    condition     = contains(["us", "eu", "asia"], var.document_ai_location)
    error_message = "Document AI location must be one of: us, eu, asia."
  }
}

variable "form_processor_display_name" {
  type        = string
  description = "Display name for the Form Parser processor"
  default     = "Form Parser"
  
  validation {
    condition     = length(var.form_processor_display_name) > 0 && length(var.form_processor_display_name) <= 100
    error_message = "Form processor display name must be between 1 and 100 characters."
  }
}

variable "invoice_processor_display_name" {
  type        = string
  description = "Display name for the Invoice Parser processor"
  default     = "Invoice Parser"
  
  validation {
    condition     = length(var.invoice_processor_display_name) > 0 && length(var.invoice_processor_display_name) <= 100
    error_message = "Invoice processor display name must be between 1 and 100 characters."
  }
}

# Cloud Storage Configuration Variables
variable "storage_class" {
  type        = string
  description = "Default storage class for buckets"
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  type        = bool
  description = "Enable versioning for storage buckets"
  default     = true
}

variable "lifecycle_age_days" {
  type        = number
  description = "Number of days after which objects are deleted (lifecycle rule)"
  default     = 30
  
  validation {
    condition     = var.lifecycle_age_days > 0 && var.lifecycle_age_days <= 365
    error_message = "Lifecycle age must be between 1 and 365 days."
  }
}

# BigQuery Configuration Variables
variable "bigquery_location" {
  type        = string
  description = "Location for BigQuery dataset"
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid location (US, EU, or specific region)."
  }
}

variable "dataset_description" {
  type        = string
  description = "Description for the BigQuery dataset"
  default     = "Document processing analytics and validation metrics"
}

variable "table_expiration_days" {
  type        = number
  description = "Number of days after which BigQuery tables expire (0 = never expire)"
  default     = 0
  
  validation {
    condition     = var.table_expiration_days >= 0
    error_message = "Table expiration days must be 0 or greater."
  }
}

# Workflow Configuration Variables
variable "workflow_description" {
  type        = string
  description = "Description for the Cloud Workflows workflow"
  default     = "Document validation workflow with AI processing and intelligent routing"
}

variable "workflow_call_log_level" {
  type        = string
  description = "Call log level for Cloud Workflows"
  default     = "LOG_ERRORS_ONLY"
  
  validation {
    condition     = contains(["LOG_ALL_CALLS", "LOG_ERRORS_ONLY", "LOG_NONE"], var.workflow_call_log_level)
    error_message = "Workflow call log level must be one of: LOG_ALL_CALLS, LOG_ERRORS_ONLY, LOG_NONE."
  }
}

variable "confidence_threshold" {
  type        = number
  description = "Confidence threshold for document validation (0.0 to 1.0)"
  default     = 0.8
  
  validation {
    condition     = var.confidence_threshold >= 0.0 && var.confidence_threshold <= 1.0
    error_message = "Confidence threshold must be between 0.0 and 1.0."
  }
}

variable "max_validation_errors" {
  type        = number
  description = "Maximum number of validation errors before marking document as invalid"
  default     = 2
  
  validation {
    condition     = var.max_validation_errors >= 0 && var.max_validation_errors <= 10
    error_message = "Maximum validation errors must be between 0 and 10."
  }
}

# IAM and Security Configuration Variables
variable "enable_uniform_bucket_level_access" {
  type        = bool
  description = "Enable uniform bucket-level access for enhanced security"
  default     = true
}

variable "public_access_prevention" {
  type        = string
  description = "Public access prevention setting for buckets"
  default     = "enforced"
  
  validation {
    condition     = contains(["inherited", "enforced"], var.public_access_prevention)
    error_message = "Public access prevention must be either 'inherited' or 'enforced'."
  }
}

variable "eventarc_service_account_description" {
  type        = string
  description = "Description for the Eventarc service account"
  default     = "Service account for Eventarc trigger to invoke Cloud Workflows"
}

# Tagging and Labeling Variables
variable "labels" {
  type        = map(string)
  description = "Labels to apply to all resources"
  default = {
    project     = "document-validation"
    managed_by  = "terraform"
    component   = "document-ai-workflows"
  }
  
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z]([a-z0-9_-]{0,62})$", k))])
    error_message = "All label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens (max 63 characters)."
  }
  
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "All label values must contain only lowercase letters, numbers, underscores, and hyphens (max 63 characters)."
  }
}

# Feature Flags
variable "enable_deletion_protection" {
  type        = bool
  description = "Enable deletion protection for critical resources"
  default     = true
}

variable "enable_monitoring" {
  type        = bool
  description = "Enable monitoring and logging for resources"
  default     = true
}

variable "enable_lifecycle_rules" {
  type        = bool
  description = "Enable lifecycle rules for storage buckets"
  default     = true
}