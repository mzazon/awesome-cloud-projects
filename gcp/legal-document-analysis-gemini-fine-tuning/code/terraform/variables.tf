# Variables for Legal Document Analysis with Gemini Fine-Tuning Infrastructure
# This file defines all configurable parameters for the deployment

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
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
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region with Vertex AI support."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "legal-analysis"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
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

variable "enable_versioning" {
  description = "Enable versioning on Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (MB)"
  type        = number
  default     = 512
  validation {
    condition     = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 MB and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "document_ai_processor_type" {
  description = "Type of Document AI processor to create"
  type        = string
  default     = "FORM_PARSER_PROCESSOR"
  validation {
    condition = contains([
      "FORM_PARSER_PROCESSOR",
      "OCR_PROCESSOR",
      "INVOICE_PROCESSOR",
      "CONTRACT_PROCESSOR"
    ], var.document_ai_processor_type)
    error_message = "Document AI processor type must be a valid processor type."
  }
}

variable "enable_public_access" {
  description = "Allow public access to Cloud Functions (for demo purposes)"
  type        = bool
  default     = false
}

variable "retention_days" {
  description = "Number of days to retain processed documents and results"
  type        = number
  default     = 90
  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 3650
    error_message = "Retention days must be between 1 and 3650 days."
  }
}

variable "gemini_model_base" {
  description = "Base Gemini model for fine-tuning"
  type        = string
  default     = "gemini-2.5-flash"
  validation {
    condition = contains([
      "gemini-2.5-flash",
      "gemini-1.5-flash",
      "gemini-1.5-pro"
    ], var.gemini_model_base)
    error_message = "Gemini model must be a valid tunable model."
  }
}

variable "tuning_epochs" {
  description = "Number of epochs for model fine-tuning"
  type        = number
  default     = 5
  validation {
    condition     = var.tuning_epochs >= 1 && var.tuning_epochs <= 20
    error_message = "Tuning epochs must be between 1 and 20."
  }
}

variable "learning_rate_multiplier" {
  description = "Learning rate multiplier for fine-tuning"
  type        = number
  default     = 1.0
  validation {
    condition     = var.learning_rate_multiplier >= 0.1 && var.learning_rate_multiplier <= 10.0
    error_message = "Learning rate multiplier must be between 0.1 and 10.0."
  }
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "legal-document-analysis"
    managed-by  = "terraform"
  }
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Cannot specify more than 64 labels."
  }
}