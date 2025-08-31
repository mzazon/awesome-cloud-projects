# =============================================================================
# Weather API with Cloud Functions - Terraform Variables
# =============================================================================
# This file defines all configurable variables for the weather API deployment
# including project settings, function configuration, and resource parameters.
# =============================================================================

# =============================================================================
# PROJECT CONFIGURATION
# =============================================================================

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for deploying resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Cloud Functions."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and organization"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# =============================================================================
# CLOUD FUNCTION CONFIGURATION
# =============================================================================

variable "function_name" {
  description = "Name of the Cloud Function for the weather API"
  type        = string
  default     = "weather-api"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, be 1-63 characters long, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_runtime" {
  description = "Runtime environment for the Cloud Function"
  type        = string
  default     = "python313"
  
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312", "python313",
      "nodejs18", "nodejs20", "nodejs22",
      "go119", "go120", "go121", "go122",
      "java11", "java17", "java21",
      "dotnet6", "dotnet8"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime version."
  }
}

variable "function_entry_point" {
  description = "The name of the function to execute when the Cloud Function is triggered"
  type        = string
  default     = "weather_api"
  
  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.function_entry_point))
    error_message = "Entry point must be a valid Python function name (start with letter/underscore, contain only letters/numbers/underscores)."
  }
}

# =============================================================================
# PERFORMANCE AND SCALING CONFIGURATION
# =============================================================================

variable "memory_mb" {
  description = "Amount of memory allocated to the Cloud Function (in MB)"
  type        = string
  default     = "256M"
  
  validation {
    condition = contains([
      "128M", "256M", "512M", "1024M", "2048M", "4096M", "8192M", "16384M", "32768M"
    ], var.memory_mb)
    error_message = "Memory must be one of: 128M, 256M, 512M, 1024M, 2048M, 4096M, 8192M, 16384M, 32768M."
  }
}

variable "timeout_seconds" {
  description = "Maximum execution time for the Cloud Function (in seconds)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds (1 hour)."
  }
}

variable "max_instance_count" {
  description = "Maximum number of function instances that can run concurrently"
  type        = number
  default     = 100
  
  validation {
    condition     = var.max_instance_count >= 1 && var.max_instance_count <= 3000
    error_message = "Max instance count must be between 1 and 3000."
  }
}

variable "min_instance_count" {
  description = "Minimum number of function instances to keep warm (0 for serverless)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instance_count >= 0 && var.min_instance_count <= 1000
    error_message = "Min instance count must be between 0 and 1000."
  }
}

# =============================================================================
# ENVIRONMENT AND CONFIGURATION
# =============================================================================

variable "environment_variables" {
  description = "Environment variables to pass to the Cloud Function"
  type        = map(string)
  default = {
    FUNCTION_SIGNATURE_TYPE = "http"
    FUNCTION_TARGET         = "weather_api"
  }
  
  validation {
    condition = alltrue([
      for key, value in var.environment_variables : 
      can(regex("^[A-Z_][A-Z0-9_]*$", key)) && length(value) <= 32768
    ])
    error_message = "Environment variable keys must be uppercase with underscores, and values must be under 32KB."
  }
}

variable "weather_api_key" {
  description = "API key for external weather service (leave empty for mock data)"
  type        = string
  default     = ""
  sensitive   = true
}

# =============================================================================
# MONITORING AND OBSERVABILITY
# =============================================================================

variable "enable_monitoring" {
  description = "Enable monitoring and log-based metrics for the function"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Logging level for the Cloud Function"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the Cloud Function"
  type        = bool
  default     = true
}

variable "cors_origins" {
  description = "List of allowed origins for CORS (Cross-Origin Resource Sharing)"
  type        = list(string)
  default     = ["*"]
  
  validation {
    condition = alltrue([
      for origin in var.cors_origins :
      origin == "*" || can(regex("^https?://", origin))
    ])
    error_message = "CORS origins must be '*' or valid HTTP/HTTPS URLs."
  }
}

# =============================================================================
# RESOURCE TAGGING AND ORGANIZATION
# =============================================================================

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.labels :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", key)) && 
      can(regex("^[a-z0-9_-]{0,63}$", value))
    ])
    error_message = "Labels must have keys starting with lowercase letter and values containing only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "cost_center" {
  description = "Cost center identifier for billing and resource tracking"
  type        = string
  default     = ""
}

variable "owner" {
  description = "Owner or team responsible for this deployment"
  type        = string
  default     = ""
}

# =============================================================================
# ADVANCED CONFIGURATION
# =============================================================================

variable "vpc_connector" {
  description = "VPC connector name for private network access (optional)"
  type        = string
  default     = ""
}

variable "ingress_settings" {
  description = "Ingress settings for the Cloud Function"
  type        = string
  default     = "ALLOW_ALL"
  
  validation {
    condition     = contains(["ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"], var.ingress_settings)
    error_message = "Ingress settings must be one of: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  }
}

variable "service_account_email" {
  description = "Custom service account email (if not provided, one will be created)"
  type        = string
  default     = ""
}

# =============================================================================
# STORAGE CONFIGURATION
# =============================================================================

variable "source_bucket_name" {
  description = "Custom name for the source code storage bucket (if not provided, will be auto-generated)"
  type        = string
  default     = ""
  
  validation {
    condition = var.source_bucket_name == "" || can(regex("^[a-z0-9][a-z0-9-_]*[a-z0-9]$", var.source_bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, hyphens, and underscores, and must start and end with a letter or number."
  }
}

variable "source_archive_retention_days" {
  description = "Number of days to retain source code archives in Cloud Storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.source_archive_retention_days >= 1 && var.source_archive_retention_days <= 365
    error_message = "Source archive retention must be between 1 and 365 days."
  }
}