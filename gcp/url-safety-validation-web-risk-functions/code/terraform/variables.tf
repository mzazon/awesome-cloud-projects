# Variables for URL Safety Validation Infrastructure
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
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

variable "function_name" {
  description = "Name of the Cloud Function for URL validation"
  type        = string
  default     = "url-validator"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{1,63}$", var.function_name))
    error_message = "Function name must be 1-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 256
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 100
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

variable "cache_retention_days" {
  description = "Number of days to retain cached URL validation results"
  type        = number
  default     = 30
  
  validation {
    condition     = var.cache_retention_days >= 1 && var.cache_retention_days <= 365
    error_message = "Cache retention must be between 1 and 365 days."
  }
}

variable "audit_log_retention_days" {
  description = "Number of days to retain audit logs (0 = indefinite)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.audit_log_retention_days >= 0 && var.audit_log_retention_days <= 3650
    error_message = "Audit log retention must be between 0 and 3650 days."
  }
}

variable "enable_cors" {
  description = "Enable CORS for web client access"
  type        = bool
  default     = true
}

variable "allowed_origins" {
  description = "List of allowed origins for CORS (only used if enable_cors is true)"
  type        = list(string)
  default     = ["*"]
  
  validation {
    condition     = length(var.allowed_origins) > 0
    error_message = "At least one allowed origin must be specified."
  }
}

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

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "url-safety-validation"
    managed-by  = "terraform"
    component   = "security"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]{1,63}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label keys and values must be lowercase alphanumeric characters, underscores, or hyphens, and be 1-63 characters long."
  }
}

variable "enable_public_access" {
  description = "Allow unauthenticated access to the Cloud Function"
  type        = bool
  default     = true
}