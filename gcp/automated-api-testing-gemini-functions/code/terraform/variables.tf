# Input variables for GCP automated API testing infrastructure
# This file defines all configurable parameters for the solution

# ==============================================================================
# PROJECT CONFIGURATION
# ==============================================================================

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for deploying resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-central2", "europe-north1", "europe-southwest1", "europe-west1", "europe-west2", 
      "europe-west3", "europe-west4", "europe-west6", "europe-west8", "europe-west9",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-south2", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid GCP region with Vertex AI support."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
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

# ==============================================================================
# RESOURCE NAMING
# ==============================================================================

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "api-testing"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 8
    error_message = "Random suffix length must be between 4 and 8 characters."
  }
}

# ==============================================================================
# CLOUD STORAGE CONFIGURATION
# ==============================================================================

variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "versioning_enabled" {
  description = "Enable versioning for the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "lifecycle_rules_enabled" {
  description = "Enable lifecycle rules for the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "test_results_retention_days" {
  description = "Number of days to retain test results before deletion"
  type        = number
  default     = 90
  
  validation {
    condition     = var.test_results_retention_days >= 30 && var.test_results_retention_days <= 365
    error_message = "Test results retention must be between 30 and 365 days."
  }
}

# ==============================================================================
# CLOUD FUNCTIONS CONFIGURATION
# ==============================================================================

variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python312"
  
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (MB)"
  type        = string
  default     = "1Gi"
  
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi", "16Gi", "32Gi"
    ], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions memory size."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 60 and 3600 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 100
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function max instances must be between 1 and 1000."
  }
}

# ==============================================================================
# CLOUD RUN CONFIGURATION
# ==============================================================================

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "2Gi"
  
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi", "16Gi", "32Gi"
    ], var.cloud_run_memory)
    error_message = "Cloud Run memory must be a valid memory size."
  }
}

variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "2"
  
  validation {
    condition = contains([
      "0.25", "0.5", "1", "2", "4", "6", "8"
    ], var.cloud_run_cpu)
    error_message = "Cloud Run CPU must be a valid CPU allocation."
  }
}

variable "cloud_run_timeout" {
  description = "Timeout for Cloud Run service (seconds)"
  type        = number
  default     = 900
  
  validation {
    condition     = var.cloud_run_timeout >= 300 && var.cloud_run_timeout <= 3600
    error_message = "Cloud Run timeout must be between 300 and 3600 seconds."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 100
    error_message = "Cloud Run max instances must be between 1 and 100."
  }
}

variable "cloud_run_concurrency" {
  description = "Maximum number of concurrent requests per Cloud Run instance"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cloud_run_concurrency >= 1 && var.cloud_run_concurrency <= 1000
    error_message = "Cloud Run concurrency must be between 1 and 1000."
  }
}

# ==============================================================================
# VERTEX AI CONFIGURATION
# ==============================================================================

variable "gemini_model" {
  description = "Vertex AI Gemini model to use for test generation"
  type        = string
  default     = "gemini-2.0-flash"
  
  validation {
    condition = contains([
      "gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"
    ], var.gemini_model)
    error_message = "Gemini model must be a supported Vertex AI model."
  }
}

variable "vertex_ai_location" {
  description = "Location for Vertex AI resources (may differ from main region)"
  type        = string
  default     = ""  # Will default to main region if not specified
}

# ==============================================================================
# SECURITY AND ACCESS CONTROL
# ==============================================================================

variable "allow_unauthenticated_access" {
  description = "Allow unauthenticated access to Cloud Functions and Cloud Run"
  type        = bool
  default     = false
}

variable "enable_audit_logs" {
  description = "Enable audit logging for all services"
  type        = bool
  default     = true
}

variable "cors_origins" {
  description = "CORS origins for Cloud Run service"
  type        = list(string)
  default     = ["*"]
}

# ==============================================================================
# MONITORING AND LOGGING
# ==============================================================================

variable "enable_cloud_monitoring" {
  description = "Enable Cloud Monitoring for all resources"
  type        = bool
  default     = true
}

variable "enable_cloud_logging" {
  description = "Enable Cloud Logging for all resources"
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

# ==============================================================================
# NETWORKING
# ==============================================================================

variable "enable_vpc_connector" {
  description = "Enable VPC connector for private networking"
  type        = bool
  default     = false
}

variable "vpc_connector_name" {
  description = "Name of existing VPC connector (if enable_vpc_connector is true)"
  type        = string
  default     = ""
}

# ==============================================================================
# COST OPTIMIZATION
# ==============================================================================

variable "enable_cost_optimization" {
  description = "Enable cost optimization features (minimum instances, etc.)"
  type        = bool
  default     = true
}

variable "function_min_instances" {
  description = "Minimum number of function instances (0 for cost optimization)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 100
    error_message = "Function min instances must be between 0 and 100."
  }
}

variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances (0 for cost optimization)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.cloud_run_min_instances >= 0 && var.cloud_run_min_instances <= 10
    error_message = "Cloud Run min instances must be between 0 and 10."
  }
}

# ==============================================================================
# ADDITIONAL FEATURES
# ==============================================================================

variable "enable_secret_manager" {
  description = "Enable Secret Manager for storing sensitive configuration"
  type        = bool
  default     = true
}

variable "enable_error_reporting" {
  description = "Enable Error Reporting for application errors"
  type        = bool
  default     = true
}

variable "enable_cloud_trace" {
  description = "Enable Cloud Trace for distributed tracing"
  type        = bool
  default     = false
}

variable "enable_cloud_profiler" {
  description = "Enable Cloud Profiler for performance analysis"
  type        = bool
  default     = false
}

# ==============================================================================
# CUSTOM LABELS
# ==============================================================================

variable "custom_labels" {
  description = "Custom labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.custom_labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}