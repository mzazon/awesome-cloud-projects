# Variables for Custom Music Generation with Vertex AI and Storage
# These variables provide customization options for the deployment

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "The project_id value must be a non-empty string."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "The region value must be a valid Google Cloud region format."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "The zone value must be a valid Google Cloud zone format."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_suffix" {
  description = "Optional suffix to append to resource names for uniqueness"
  type        = string
  default     = ""
}

# Storage Configuration
variable "input_bucket_name" {
  description = "Name for the input prompts Cloud Storage bucket (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "output_bucket_name" {
  description = "Name for the generated music Cloud Storage bucket (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "storage_class" {
  description = "Storage class for the Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on Cloud Storage buckets for data protection"
  type        = bool
  default     = true
}

variable "lifecycle_age_nearline" {
  description = "Number of days after which objects transition to NEARLINE storage"
  type        = number
  default     = 30
  validation {
    condition     = var.lifecycle_age_nearline > 0
    error_message = "Lifecycle age for NEARLINE must be a positive number."
  }
}

variable "lifecycle_age_coldline" {
  description = "Number of days after which objects transition to COLDLINE storage"
  type        = number
  default     = 90
  validation {
    condition     = var.lifecycle_age_coldline > var.lifecycle_age_nearline
    error_message = "Lifecycle age for COLDLINE must be greater than NEARLINE age."
  }
}

# Cloud Functions Configuration
variable "generator_function_name" {
  description = "Name for the music generator Cloud Function (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "api_function_name" {
  description = "Name for the API Cloud Function (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "function_memory" {
  description = "Memory allocation for the music generator Cloud Function in MB"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768], var.function_memory)
    error_message = "Function memory must be one of the allowed values: 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768."
  }
}

variable "api_function_memory" {
  description = "Memory allocation for the API Cloud Function in MB"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768], var.api_function_memory)
    error_message = "Function memory must be one of the allowed values: 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768."
  }
}

variable "function_timeout" {
  description = "Timeout for the music generator Cloud Function in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 60 and 3600 seconds."
  }
}

variable "api_function_timeout" {
  description = "Timeout for the API Cloud Function in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.api_function_timeout >= 60 && var.api_function_timeout <= 3600
    error_message = "Function timeout must be between 60 and 3600 seconds."
  }
}

variable "python_runtime" {
  description = "Python runtime version for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition     = contains(["python39", "python310", "python311", "python312"], var.python_runtime)
    error_message = "Python runtime must be one of: python39, python310, python311, python312."
  }
}

# IAM and Security Configuration
variable "enable_public_access" {
  description = "Enable public access to the API Cloud Function (set to false for private use)"
  type        = bool
  default     = false
}

variable "allowed_members" {
  description = "List of members allowed to invoke the API function when public access is disabled"
  type        = list(string)
  default     = []
}

# Vertex AI Configuration
variable "enable_vertex_ai_apis" {
  description = "Enable Vertex AI APIs automatically (requires appropriate permissions)"
  type        = bool
  default     = true
}

# Monitoring and Logging
variable "enable_cloud_logging" {
  description = "Enable Cloud Logging for Cloud Functions"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain Cloud Function logs"
  type        = number
  default     = 7
  validation {
    condition     = var.log_retention_days > 0 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653."
  }
}

# Resource Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "music-generation"
    solution    = "vertex-ai-lyria"
    managed-by  = "terraform"
  }
}