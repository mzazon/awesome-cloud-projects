# Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

# Resource Naming
variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "conv-ai-training"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name_prefix))
    error_message = "Name prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# Storage Configuration
variable "bucket_location" {
  description = "Location for the Cloud Storage bucket"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "ASIA", 
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
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
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "bucket_versioning_enabled" {
  description = "Enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age_days" {
  description = "Number of days after which to transition objects to a lower storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.bucket_lifecycle_age_days > 0
    error_message = "Lifecycle age must be greater than 0."
  }
}

# Cloud Functions Configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python312"
  
  validation {
    condition     = contains(["python39", "python310", "python311", "python312"], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (in seconds)"
  type        = number
  default     = 540
  
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
    error_message = "Max instances must be between 1 and 3000."
  }
}

# Vertex AI Configuration
variable "vertex_ai_region" {
  description = "Region for Vertex AI services (may differ from main region)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-northeast1", "asia-east1", "asia-southeast1"
    ], var.vertex_ai_region)
    error_message = "Vertex AI region must support Gemini models."
  }
}

variable "gemini_model" {
  description = "Gemini model to use for conversation generation"
  type        = string
  default     = "gemini-1.5-flash-001"
  
  validation {
    condition = contains([
      "gemini-1.5-flash-001", "gemini-1.5-pro-001", "gemini-1.0-pro-001"
    ], var.gemini_model)
    error_message = "Must be a valid Gemini model version."
  }
}

# Service Configuration
variable "enable_apis" {
  description = "List of APIs to enable"
  type        = list(string)
  default = [
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "eventarc.googleapis.com"
  ]
}

# IAM Configuration
variable "create_service_accounts" {
  description = "Whether to create dedicated service accounts for functions"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable monitoring and alerting resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Conversation Generation Configuration
variable "conversation_templates" {
  description = "Default conversation templates for training data generation"
  type = object({
    templates = list(object({
      scenario            = string
      context            = string
      user_intents       = list(string)
      conversation_length = string
      tone               = string
    }))
  })
  default = {
    templates = [
      {
        scenario            = "customer_support"
        context            = "Technical support for a software application"
        user_intents       = ["bug_report", "feature_request", "account_issue"]
        conversation_length = "3-5 exchanges"
        tone               = "professional, helpful"
      },
      {
        scenario            = "e_commerce"
        context            = "Online shopping assistance and product inquiries"
        user_intents       = ["product_search", "order_status", "return_request"]
        conversation_length = "2-4 exchanges"
        tone               = "friendly, sales-oriented"
      },
      {
        scenario            = "healthcare"
        context            = "General health information and appointment scheduling"
        user_intents       = ["symptom_inquiry", "appointment_booking", "medication_info"]
        conversation_length = "4-6 exchanges"
        tone               = "empathetic, professional"
      }
    ]
  }
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    "managed-by"   = "terraform"
    "project-type" = "conversational-ai-training"
    "cost-center"  = "ml-research"
  }
}