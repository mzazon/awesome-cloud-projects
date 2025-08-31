# Variables Configuration for Smart Form Processing Infrastructure
# This file defines all input variables for the Terraform configuration

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
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Document AI."
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

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "smart-form-processing"
    managed-by  = "terraform"
    component   = "document-ai-gemini"
  }
}

# Cloud Storage Configuration
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

variable "bucket_lifecycle_days" {
  description = "Number of days after which objects in buckets are deleted"
  type        = number
  default     = 30
  validation {
    condition     = var.bucket_lifecycle_days > 0 && var.bucket_lifecycle_days <= 365
    error_message = "Lifecycle days must be between 1 and 365."
  }
}

# Document AI Configuration
variable "document_ai_processor_type" {
  description = "Type of Document AI processor to create"
  type        = string
  default     = "FORM_PARSER_PROCESSOR"
  validation {
    condition = contains([
      "FORM_PARSER_PROCESSOR", "OCR_PROCESSOR", "DOCUMENT_QUALITY_PROCESSOR"
    ], var.document_ai_processor_type)
    error_message = "Processor type must be a valid Document AI processor type."
  }
}

variable "document_ai_processor_display_name" {
  description = "Display name for the Document AI processor"
  type        = string
  default     = "smart-form-processor"
}

# Cloud Function Configuration
variable "function_name" {
  description = "Name of the Cloud Function"
  type        = string
  default     = "process-form"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.function_name))
    error_message = "Function name must start with a letter and contain only letters, numbers, and hyphens."
  }
}

variable "function_runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "python312"
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Runtime must be a supported Python version."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function (in MB)"
  type        = number
  default     = 1024
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function (in seconds)"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

# Vertex AI Configuration
variable "vertex_ai_model" {
  description = "Vertex AI Gemini model to use"
  type        = string
  default     = "gemini-1.5-flash"
  validation {
    condition = contains([
      "gemini-1.5-flash", "gemini-1.5-pro", "gemini-1.0-pro"
    ], var.vertex_ai_model)
    error_message = "Model must be a valid Vertex AI Gemini model."
  }
}

# Security Configuration
variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "enable_public_access_prevention" {
  description = "Enable public access prevention for Cloud Storage buckets"
  type        = bool
  default     = true
}

# Monitoring and Logging
variable "enable_function_logging" {
  description = "Enable detailed logging for Cloud Functions"
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