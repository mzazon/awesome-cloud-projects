# Variables for smart contract security auditing infrastructure

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
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
    error_message = "Region must be a valid GCP region that supports Document AI and Vertex AI."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (random suffix will be added)"
  type        = string
  default     = "contract-audit"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_name" {
  description = "Name for the Cloud Function that analyzes smart contracts"
  type        = string
  default     = "contract-security-analyzer"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "processor_display_name" {
  description = "Display name for the Document AI processor"
  type        = string
  default     = "Smart Contract Security Parser"
}

variable "processor_type" {
  description = "Type of Document AI processor to create"
  type        = string
  default     = "FORM_PARSER_PROCESSOR"
  
  validation {
    condition = contains([
      "FORM_PARSER_PROCESSOR",
      "OCR_PROCESSOR",
      "DOCUMENT_OCR_PROCESSOR"
    ], var.processor_type)
    error_message = "Processor type must be a valid Document AI processor type."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 MB and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 540
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "bucket_lifecycle_age_days" {
  description = "Number of days after which objects transition to Nearline storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.bucket_lifecycle_age_days > 0
    error_message = "Lifecycle age must be a positive number."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    purpose     = "smart-contract-security"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "vertex_ai_model" {
  description = "Vertex AI model to use for contract analysis"
  type        = string
  default     = "gemini-1.5-pro"
  
  validation {
    condition = contains([
      "gemini-1.5-pro",
      "gemini-1.5-flash",
      "gemini-pro"
    ], var.vertex_ai_model)
    error_message = "Must be a valid Vertex AI generative model."
  }
}

variable "notification_email" {
  description = "Email address for audit completion notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}