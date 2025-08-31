# Variables for Smart Survey Analysis Infrastructure
# Define all configurable values for the Terraform deployment

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
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
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
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
  description = "Base name for the Cloud Function (will be suffixed with environment)"
  type        = string
  default     = "survey-analyzer"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "firestore_database_name" {
  description = "Name of the Firestore database"
  type        = string
  default     = "survey-db"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.firestore_database_name))
    error_message = "Database name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "firestore_location" {
  description = "Location for Firestore database (must be a valid Firestore location)"
  type        = string
  default     = "us-central"
  
  validation {
    condition = contains([
      "us-central", "us-east1", "us-west2", "us-west3", "us-west4",
      "europe-west", "europe-west2", "europe-west3", "europe-west6",
      "asia-east2", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-regional or regional location."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function (MB)"
  type        = number
  default     = 1024
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function (seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
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
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "enable_public_access" {
  description = "Enable public HTTP access to the Cloud Function (disable for production)"
  type        = bool
  default     = true
}

variable "enable_vertex_ai" {
  description = "Enable Vertex AI API for Gemini model access"
  type        = bool
  default     = true
}

variable "gemini_model" {
  description = "Gemini model version to use"
  type        = string
  default     = "gemini-1.5-flash"
  
  validation {
    condition = contains([
      "gemini-1.5-flash", "gemini-1.5-pro", "gemini-1.0-pro"
    ], var.gemini_model)
    error_message = "Gemini model must be a supported version."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "survey-analysis"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can only contain lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for the Cloud Function"
  type        = bool
  default     = true
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

variable "min_instances" {
  description = "Minimum number of function instances (0 for serverless)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "ingress_settings" {
  description = "Ingress settings for the Cloud Function"
  type        = string
  default     = "ALLOW_ALL"
  
  validation {
    condition = contains([
      "ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"
    ], var.ingress_settings)
    error_message = "Ingress settings must be one of: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  }
}