# ================================================================
# Variables for Content Quality Scoring System
# ================================================================
# This file defines all configurable parameters for the content
# quality scoring infrastructure deployment.
# ================================================================

# ================================================================
# PROJECT AND LOCATION VARIABLES
# ================================================================

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region where resources will be deployed"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Vertex AI."
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

# ================================================================
# CLOUD STORAGE VARIABLES
# ================================================================

variable "content_bucket_prefix" {
  description = "Prefix for the content upload bucket name"
  type        = string
  default     = "content-analysis"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.content_bucket_prefix))
    error_message = "Bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "results_bucket_prefix" {
  description = "Prefix for the analysis results bucket name"
  type        = string
  default     = "quality-results"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.results_bucket_prefix))
    error_message = "Bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "content_retention_days" {
  description = "Number of days to retain content files before deletion"
  type        = number
  default     = 365
  validation {
    condition     = var.content_retention_days > 0 && var.content_retention_days <= 3650
    error_message = "Content retention days must be between 1 and 3650 (10 years)."
  }
}

variable "results_retention_days" {
  description = "Number of days to retain analysis results before deletion"
  type        = number
  default     = 730
  validation {
    condition     = var.results_retention_days > 0 && var.results_retention_days <= 3650
    error_message = "Results retention days must be between 1 and 3650 (10 years)."
  }
}

# ================================================================
# CLOUD FUNCTION VARIABLES
# ================================================================

variable "function_name" {
  description = "Name of the Cloud Function"
  type        = string
  default     = "analyze-content-quality"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_runtime" {
  description = "Runtime environment for the Cloud Function"
  type        = string
  default     = "python311"
  validation {
    condition     = contains(["python38", "python39", "python310", "python311", "python312"], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "function_entry_point" {
  description = "Entry point function name in the Cloud Function code"
  type        = string
  default     = "analyze_content_quality"
  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.function_entry_point))
    error_message = "Entry point must be a valid Python function name."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function"
  type        = string
  default     = "512Mi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi", "16Gi", "32Gi"
    ], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout > 0 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.function_max_instances > 0 && var.function_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 100
    error_message = "Min instances must be between 0 and 100."
  }
}

variable "function_concurrency" {
  description = "Maximum number of concurrent requests per function instance"
  type        = number
  default     = 1
  validation {
    condition     = var.function_concurrency > 0 && var.function_concurrency <= 1000
    error_message = "Function concurrency must be between 1 and 1000."
  }
}

variable "function_cpu" {
  description = "CPU allocation for the Cloud Function"
  type        = string
  default     = "1"
  validation {
    condition     = contains(["0.08", "0.17", "0.33", "0.5", "1", "2", "4", "6", "8"], var.function_cpu)
    error_message = "Function CPU must be a valid Cloud Functions CPU allocation."
  }
}

# ================================================================
# PYTHON PACKAGE VERSIONS
# ================================================================

variable "functions_framework_version" {
  description = "Version of the Google Cloud Functions Framework"
  type        = string
  default     = "3.8.2"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.functions_framework_version))
    error_message = "Functions framework version must be in semver format (x.y.z)."
  }
}

variable "google_cloud_storage_version" {
  description = "Version of the Google Cloud Storage Python client"
  type        = string
  default     = "2.18.0"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.google_cloud_storage_version))
    error_message = "Storage client version must be in semver format (x.y.z)."
  }
}

variable "google_cloud_aiplatform_version" {
  description = "Version of the Google Cloud AI Platform Python client"
  type        = string
  default     = "1.60.0"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.google_cloud_aiplatform_version))
    error_message = "AI Platform client version must be in semver format (x.y.z)."
  }
}

variable "google_cloud_logging_version" {
  description = "Version of the Google Cloud Logging Python client"
  type        = string
  default     = "3.11.0"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.google_cloud_logging_version))
    error_message = "Logging client version must be in semver format (x.y.z)."
  }
}

# ================================================================
# VERTEX AI CONFIGURATION
# ================================================================

variable "vertex_ai_model" {
  description = "Vertex AI model to use for content analysis"
  type        = string
  default     = "gemini-1.5-flash"
  validation {
    condition = contains([
      "gemini-1.5-flash", "gemini-1.5-pro", "gemini-1.0-pro"
    ], var.vertex_ai_model)
    error_message = "Model must be a supported Vertex AI Gemini model."
  }
}

variable "vertex_ai_temperature" {
  description = "Temperature setting for Vertex AI model (controls randomness)"
  type        = number
  default     = 0.2
  validation {
    condition     = var.vertex_ai_temperature >= 0 && var.vertex_ai_temperature <= 2
    error_message = "Temperature must be between 0 and 2."
  }
}

variable "vertex_ai_max_tokens" {
  description = "Maximum output tokens for Vertex AI model"
  type        = number
  default     = 2048
  validation {
    condition     = var.vertex_ai_max_tokens > 0 && var.vertex_ai_max_tokens <= 8192
    error_message = "Max tokens must be between 1 and 8192."
  }
}

variable "vertex_ai_top_p" {
  description = "Top-p (nucleus sampling) parameter for Vertex AI model"
  type        = number
  default     = 0.8
  validation {
    condition     = var.vertex_ai_top_p > 0 && var.vertex_ai_top_p <= 1
    error_message = "Top-p must be between 0 and 1."
  }
}

variable "vertex_ai_top_k" {
  description = "Top-k parameter for Vertex AI model"
  type        = number
  default     = 40
  validation {
    condition     = var.vertex_ai_top_k > 0 && var.vertex_ai_top_k <= 100
    error_message = "Top-k must be between 1 and 100."
  }
}

# ================================================================
# MONITORING AND ALERTING
# ================================================================

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring alerts and notifications"
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = ""
  validation {
    condition     = var.alert_email == "" || can(regex("^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address or empty string."
  }
}

variable "error_rate_threshold" {
  description = "Error rate threshold for alerting (percentage)"
  type        = number
  default     = 10
  validation {
    condition     = var.error_rate_threshold > 0 && var.error_rate_threshold <= 100
    error_message = "Error rate threshold must be between 1 and 100 percent."
  }
}

variable "latency_threshold_seconds" {
  description = "Latency threshold for alerting in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.latency_threshold_seconds > 0 && var.latency_threshold_seconds <= 3600
    error_message = "Latency threshold must be between 1 and 3600 seconds."
  }
}

# ================================================================
# RESOURCE LABELING
# ================================================================

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain lowercase letters, numbers, underscores, and hyphens."
  }
}

# ================================================================
# FEATURE FLAGS
# ================================================================

variable "enable_function_insights" {
  description = "Enable Cloud Functions insights for better observability"
  type        = bool
  default     = true
}

variable "enable_bucket_notifications" {
  description = "Enable bucket notifications for debugging"
  type        = bool
  default     = false
}

variable "enable_access_logging" {
  description = "Enable access logging for Cloud Storage buckets"
  type        = bool
  default     = false
}

# ================================================================
# SECURITY CONFIGURATION
# ================================================================

variable "allowed_cors_origins" {
  description = "List of allowed CORS origins for Cloud Storage buckets"
  type        = list(string)
  default     = ["*"]
  validation {
    condition     = length(var.allowed_cors_origins) > 0
    error_message = "At least one CORS origin must be specified."
  }
}

variable "function_ingress_settings" {
  description = "Ingress settings for Cloud Function"
  type        = string
  default     = "ALLOW_INTERNAL_ONLY"
  validation {
    condition     = contains(["ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"], var.function_ingress_settings)
    error_message = "Ingress settings must be one of: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  }
}

variable "require_https" {
  description = "Require HTTPS for all traffic to Cloud Storage buckets"
  type        = bool
  default     = true
}

# ================================================================
# DEVELOPMENT AND TESTING
# ================================================================

variable "create_sample_content" {
  description = "Create sample content files for testing (development only)"
  type        = bool
  default     = false
}

variable "debug_mode" {
  description = "Enable debug mode with additional logging"
  type        = bool
  default     = false
}