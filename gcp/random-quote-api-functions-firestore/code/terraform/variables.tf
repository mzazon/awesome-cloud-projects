# =============================================================================
# Variables for Random Quote API with Cloud Functions and Firestore
# =============================================================================
# This file defines all input variables for the Terraform configuration.
# Variables are organized by resource type and include validation rules,
# descriptions, and sensible defaults following GCP best practices.

# -----------------------------------------------------------------------------
# Project Configuration Variables
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created. Must be globally unique across all GCP projects."
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "project_name" {
  description = "Descriptive name for the project used in resource naming and labeling. Should be short and descriptive."
  type        = string
  default     = "quote-api"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}[a-z0-9]$", var.project_name))
    error_message = "Project name must be 4-17 characters, start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "The deployment environment (development, staging, production). Used for resource naming and configuration."
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# -----------------------------------------------------------------------------
# Regional Configuration Variables
# -----------------------------------------------------------------------------

variable "region" {
  description = "The Google Cloud region where regional resources will be created. Choose a region close to your users for optimal latency."
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1, europe-west1)."
  }
}

# -----------------------------------------------------------------------------
# Firestore Database Configuration Variables
# -----------------------------------------------------------------------------

variable "firestore_database_id" {
  description = "The ID of the Firestore database. Use 'default' for the default database or specify a custom name for additional databases."
  type        = string
  default     = "quotes-db"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,61}[a-z0-9]$", var.firestore_database_id)) || var.firestore_database_id == "default"
    error_message = "Database ID must be 4-63 characters, start with a letter, contain only lowercase letters, numbers, and hyphens, or be 'default'."
  }
}

variable "firestore_deletion_policy" {
  description = "The deletion policy for the Firestore database. Use 'DELETE_PROTECTION_ENABLED' for production environments."
  type        = string
  default     = "ABANDON"
  
  validation {
    condition     = contains(["DELETE_PROTECTION_ENABLED", "ABANDON"], var.firestore_deletion_policy)
    error_message = "Deletion policy must be either 'DELETE_PROTECTION_ENABLED' or 'ABANDON'."
  }
}

# -----------------------------------------------------------------------------
# Cloud Function Configuration Variables
# -----------------------------------------------------------------------------

variable "function_name" {
  description = "The name of the Cloud Function. Must be unique within the project and region."
  type        = string
  default     = "random-quote-api"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,61}[a-z0-9]$", var.function_name))
    error_message = "Function name must be 4-63 characters, start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_memory_mb" {
  description = "The amount of memory allocated to the Cloud Function in MB. Higher memory allocation may improve performance but increases costs."
  type        = number
  default     = 256
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "The maximum execution time for the Cloud Function in seconds. Maximum is 540 seconds (9 minutes)."
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "The maximum number of concurrent function instances. Helps control costs and resource usage."
  type        = number
  default     = 100
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Maximum instances must be between 1 and 3000."
  }
}

variable "function_runtime" {
  description = "The runtime environment for the Cloud Function. Use the latest stable Node.js version for best performance and security."
  type        = string
  default     = "nodejs20"
  
  validation {
    condition     = contains(["nodejs16", "nodejs18", "nodejs20"], var.function_runtime)
    error_message = "Runtime must be one of the supported Node.js versions: nodejs16, nodejs18, nodejs20."
  }
}

# -----------------------------------------------------------------------------
# Security and Access Configuration Variables
# -----------------------------------------------------------------------------

variable "allow_public_access" {
  description = "Whether to allow public (unauthenticated) access to the Cloud Function. Set to false for internal APIs requiring authentication."
  type        = bool
  default     = true
}

variable "cors_allow_origins" {
  description = "List of allowed origins for CORS requests. Use ['*'] for development, specific domains for production."
  type        = list(string)
  default     = ["*"]
  
  validation {
    condition     = length(var.cors_allow_origins) > 0
    error_message = "At least one CORS origin must be specified."
  }
}

# -----------------------------------------------------------------------------
# Data Management Configuration Variables
# -----------------------------------------------------------------------------

variable "populate_sample_data" {
  description = "Whether to populate the Firestore database with sample quote data during deployment. Useful for testing and development."
  type        = bool
  default     = true
}

variable "sample_quotes_count" {
  description = "The number of sample quotes to add to the database. Only applies when populate_sample_data is true."
  type        = number
  default     = 5
  
  validation {
    condition     = var.sample_quotes_count >= 1 && var.sample_quotes_count <= 100
    error_message = "Sample quotes count must be between 1 and 100."
  }
}

# -----------------------------------------------------------------------------
# Deployment Configuration Variables
# -----------------------------------------------------------------------------

variable "cleanup_local_files" {
  description = "Whether to clean up local temporary files after deployment. Recommended for CI/CD environments."
  type        = bool
  default     = false
}

variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring and Logging for the deployed resources. Recommended for production environments."
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Whether to enable versioning for the Cloud Storage bucket containing function source code."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Cost Optimization Configuration Variables
# -----------------------------------------------------------------------------

variable "storage_lifecycle_age_days" {
  description = "The number of days after which objects in the function source storage bucket will be deleted. Helps manage storage costs."
  type        = number
  default     = 30
  
  validation {
    condition     = var.storage_lifecycle_age_days >= 1 && var.storage_lifecycle_age_days <= 365
    error_message = "Storage lifecycle age must be between 1 and 365 days."
  }
}

# -----------------------------------------------------------------------------
# Networking Configuration Variables
# -----------------------------------------------------------------------------

variable "vpc_connector" {
  description = "The VPC connector to use for the Cloud Function. Leave empty to use the default network configuration."
  type        = string
  default     = ""
}

variable "ingress_settings" {
  description = "The ingress settings for the Cloud Function. Controls which networks can invoke the function."
  type        = string
  default     = "ALLOW_ALL"
  
  validation {
    condition     = contains(["ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"], var.ingress_settings)
    error_message = "Ingress settings must be one of: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  }
}

# -----------------------------------------------------------------------------
# Tagging and Labeling Variables
# -----------------------------------------------------------------------------

variable "additional_labels" {
  description = "Additional labels to apply to all resources. Useful for cost tracking, compliance, and resource management."
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.additional_labels : 
      can(regex("^[a-z][a-z0-9_-]{0,62}$", key)) && 
      can(regex("^[a-z0-9_-]{0,63}$", value))
    ])
    error_message = "Label keys must start with a letter and be 1-63 characters of lowercase letters, numbers, underscores, and hyphens. Values must be 0-63 characters of lowercase letters, numbers, underscores, and hyphens."
  }
}

# -----------------------------------------------------------------------------
# Advanced Configuration Variables
# -----------------------------------------------------------------------------

variable "service_account_email" {
  description = "Custom service account email for the Cloud Function. Leave empty to use the default App Engine service account."
  type        = string
  default     = ""
  
  validation {
    condition     = var.service_account_email == "" || can(regex("^[a-z0-9.-]+@[a-z0-9.-]+\\.[a-z]{2,}$", var.service_account_email))
    error_message = "Service account email must be a valid email address or empty."
  }
}

variable "environment_variables" {
  description = "Additional environment variables to set for the Cloud Function. Useful for feature flags and configuration."
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.environment_variables : 
      can(regex("^[A-Z][A-Z0-9_]*$", key))
    ])
    error_message = "Environment variable keys must start with an uppercase letter and contain only uppercase letters, numbers, and underscores."
  }
}

variable "build_environment_variables" {
  description = "Environment variables available during the build process for the Cloud Function."
  type        = map(string)
  default     = {}
}