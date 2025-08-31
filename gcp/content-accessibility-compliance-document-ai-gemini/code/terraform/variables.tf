# Project Configuration
variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region with Document AI support."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Naming Configuration
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "accessibility"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with alphanumeric character."
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

# Storage Configuration
variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_lifecycle_enabled" {
  description = "Enable lifecycle management for the storage bucket"
  type        = bool
  default     = true
}

variable "bucket_versioning_enabled" {
  description = "Enable versioning for the storage bucket"
  type        = bool
  default     = true
}

# Document AI Configuration
variable "document_ai_processor_type" {
  description = "Type of Document AI processor to create"
  type        = string
  default     = "OCR_PROCESSOR"
  validation {
    condition = contains([
      "OCR_PROCESSOR", "FORM_PARSER_PROCESSOR", "INVOICE_PROCESSOR",
      "DOCUMENT_QUALITY_PROCESSOR", "ENTITY_EXTRACTION_PROCESSOR"
    ], var.document_ai_processor_type)
    error_message = "Document AI processor type must be a valid processor type."
  }
}

variable "document_ai_location" {
  description = "Location for Document AI processor (must support the processor type)"
  type        = string
  default     = "us"
  validation {
    condition     = contains(["us", "eu", "asia"], var.document_ai_location)
    error_message = "Document AI location must be one of: us, eu, asia."
  }
}

# Cloud Function Configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = string
  default     = "1024M"
  validation {
    condition = contains([
      "128M", "256M", "512M", "1024M", "2048M", "4096M", "8192M", "16384M", "32768M"
    ], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 60 and 3600 seconds."
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
  description = "Minimum number of function instances"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Function min instances must be between 0 and 1000."
  }
}

# Vertex AI Configuration
variable "vertex_ai_location" {
  description = "Location for Vertex AI resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.vertex_ai_location)
    error_message = "Vertex AI location must be a valid region with Vertex AI support."
  }
}

variable "gemini_model" {
  description = "Gemini model to use for accessibility analysis"
  type        = string
  default     = "gemini-1.5-pro"
  validation {
    condition = contains([
      "gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"
    ], var.gemini_model)
    error_message = "Gemini model must be a valid available model."
  }
}

# IAM and Security Configuration
variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_public_access_prevention" {
  description = "Enable public access prevention for Cloud Storage bucket"
  type        = bool
  default     = true
}

# Monitoring and Logging Configuration
variable "enable_cloud_logging" {
  description = "Enable Cloud Logging for Cloud Function"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653."
  }
}

# Cost Management
variable "labels" {
  description = "Labels to apply to all resources for cost tracking and organization"
  type        = map(string)
  default = {
    application = "accessibility-compliance"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels :
      can(regex("^[a-z][a-z0-9_-]*[a-z0-9]$", k)) && length(k) <= 63 &&
      can(regex("^[a-z0-9_-]*$", v)) && length(v) <= 63
    ])
    error_message = "Label keys and values must follow Google Cloud labeling conventions."
  }
}

# API Services to Enable
variable "enable_apis" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "documentai.googleapis.com",
    "aiplatform.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}