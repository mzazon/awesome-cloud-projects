# Variables for Document Intelligence Workflows with Agentspace and Sensitive Data Protection
# This file defines all configurable parameters for the Terraform deployment

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-southeast1", "asia-northeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Document AI and DLP services."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
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
}

# Document AI Configuration
variable "document_processor_type" {
  description = "Type of Document AI processor to create"
  type        = string
  default     = "FORM_PARSER_PROCESSOR"
  validation {
    condition = contains([
      "FORM_PARSER_PROCESSOR",
      "OCR_PROCESSOR",
      "INVOICE_PROCESSOR",
      "RECEIPT_PROCESSOR",
      "IDENTITY_PROCESSOR"
    ], var.document_processor_type)
    error_message = "Document processor type must be a valid Document AI processor type."
  }
}

variable "document_processor_display_name" {
  description = "Display name for the Document AI processor"
  type        = string
  default     = "Enterprise Document Processor"
}

# Storage Configuration
variable "storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_versioning_enabled" {
  description = "Enable versioning for Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age_days" {
  description = "Age in days after which objects are deleted (0 to disable)"
  type        = number
  default     = 365
  validation {
    condition     = var.bucket_lifecycle_age_days >= 0
    error_message = "Bucket lifecycle age must be a non-negative number."
  }
}

# DLP Configuration
variable "dlp_min_likelihood" {
  description = "Minimum likelihood for DLP findings"
  type        = string
  default     = "POSSIBLE"
  validation {
    condition = contains([
      "VERY_UNLIKELY", "UNLIKELY", "POSSIBLE", "LIKELY", "VERY_LIKELY"
    ], var.dlp_min_likelihood)
    error_message = "DLP minimum likelihood must be a valid likelihood value."
  }
}

variable "dlp_max_findings_per_request" {
  description = "Maximum number of findings per DLP request"
  type        = number
  default     = 1000
  validation {
    condition     = var.dlp_max_findings_per_request > 0 && var.dlp_max_findings_per_request <= 3000
    error_message = "DLP max findings per request must be between 1 and 3000."
  }
}

variable "dlp_info_types" {
  description = "List of information types for DLP scanning"
  type        = list(string)
  default = [
    "EMAIL_ADDRESS",
    "PERSON_NAME",
    "PHONE_NUMBER",
    "CREDIT_CARD_NUMBER",
    "US_SOCIAL_SECURITY_NUMBER",
    "IBAN_CODE",
    "DATE_OF_BIRTH",
    "PASSPORT",
    "MEDICAL_RECORD_NUMBER",
    "US_BANK_ROUTING_MICR"
  ]
}

# Monitoring and Logging Configuration
variable "log_retention_days" {
  description = "Number of days to retain audit logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653 (10 years)."
  }
}

variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts for the document processing pipeline"
  type        = bool
  default     = true
}

# BigQuery Configuration
variable "bigquery_dataset_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "asia-east1"
    ], var.bigquery_dataset_location)
    error_message = "BigQuery dataset location must be a valid location."
  }
}

variable "bigquery_table_expiration_days" {
  description = "Number of days after which BigQuery tables expire (0 for no expiration)"
  type        = number
  default     = 0
  validation {
    condition     = var.bigquery_table_expiration_days >= 0
    error_message = "BigQuery table expiration days must be non-negative."
  }
}

# Workflow Configuration
variable "workflow_timeout" {
  description = "Timeout for Cloud Workflows execution in seconds"
  type        = number
  default     = 3600
  validation {
    condition     = var.workflow_timeout >= 60 && var.workflow_timeout <= 31536000
    error_message = "Workflow timeout must be between 60 seconds and 1 year."
  }
}

# Security Configuration
variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "enable_bucket_public_access_prevention" {
  description = "Enable public access prevention for Cloud Storage buckets"
  type        = bool
  default     = true
}

# Agentspace Configuration
variable "agentspace_service_account_display_name" {
  description = "Display name for the Agentspace service account"
  type        = string
  default     = "Agentspace Document Processor"
}

variable "agentspace_service_account_description" {
  description = "Description for the Agentspace service account"
  type        = string
  default     = "Service account for Agentspace document processing integration"
}

# Networking Configuration
variable "enable_private_google_access" {
  description = "Enable Private Google Access for secure service communication"
  type        = bool
  default     = true
}

# Tagging and Labeling
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "document-intelligence"
    managed-by  = "terraform"
    component   = "agentspace-dlp-workflow"
  }
}