# =============================================================================
# Variables for Training Data Quality Assessment Infrastructure
# =============================================================================

# -----------------------------------------------------------------------------
# Project and Location Variables
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports Cloud Functions and Vertex AI."
  }
}

variable "zone" {
  description = "The GCP zone within the region"
  type        = string
  default     = "us-central1-a"
}

# -----------------------------------------------------------------------------
# Environment and Resource Naming Variables
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Environment name for resource labeling (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (will be suffixed with random string)"
  type        = string
  default     = "training-data-quality"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens, and must start and end with a letter or number."
  }
}

variable "function_name_prefix" {
  description = "Prefix for the Cloud Function name (will be suffixed with random string)"
  type        = string
  default     = "data-quality-analyzer"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.function_name_prefix))
    error_message = "Function name prefix must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "service_account_prefix" {
  description = "Prefix for the service account name (will be suffixed with random string)"
  type        = string
  default     = "data-quality-function-sa"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.service_account_prefix))
    error_message = "Service account prefix must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "pubsub_topic_prefix" {
  description = "Prefix for the Pub/Sub topic name (will be suffixed with random string)"
  type        = string
  default     = "data-upload-notifications"
  validation {
    condition     = can(regex("^[a-zA-Z]([a-zA-Z0-9-]*[a-zA-Z0-9])?$", var.pubsub_topic_prefix))
    error_message = "Pub/Sub topic prefix must start with a letter and contain only letters, numbers, and hyphens."
  }
}

# -----------------------------------------------------------------------------
# Cloud Function Configuration Variables
# -----------------------------------------------------------------------------

variable "function_memory_mb" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 1024
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime environment for the Cloud Function"
  type        = string
  default     = "python312"
  validation {
    condition     = contains(["python39", "python310", "python311", "python312"], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

# -----------------------------------------------------------------------------
# Security and Access Control Variables
# -----------------------------------------------------------------------------

variable "allow_unauthenticated" {
  description = "Whether to allow unauthenticated access to the Cloud Function (for testing only)"
  type        = bool
  default     = true
}

variable "force_destroy_bucket" {
  description = "Whether to force destroy the bucket even if it contains objects (use with caution)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Feature Toggle Variables
# -----------------------------------------------------------------------------

variable "enable_automatic_analysis" {
  description = "Enable automatic analysis when new data is uploaded to the bucket"
  type        = bool
  default     = false
}

variable "create_monitoring_dashboard" {
  description = "Whether to create a Cloud Monitoring dashboard for the solution"
  type        = bool
  default     = true
}

variable "enable_cloud_logging" {
  description = "Enable enhanced Cloud Logging for the Cloud Function"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Vertex AI Configuration Variables
# -----------------------------------------------------------------------------

variable "vertex_ai_model" {
  description = "Vertex AI model to use for content analysis"
  type        = string
  default     = "gemini-1.5-flash"
  validation {
    condition = contains([
      "gemini-1.5-flash",
      "gemini-1.5-pro",
      "gemini-1.0-pro"
    ], var.vertex_ai_model)
    error_message = "Vertex AI model must be a supported Gemini model."
  }
}

variable "max_api_calls_per_analysis" {
  description = "Maximum number of Vertex AI API calls per analysis session"
  type        = number
  default     = 10
  validation {
    condition     = var.max_api_calls_per_analysis >= 1 && var.max_api_calls_per_analysis <= 100
    error_message = "Max API calls must be between 1 and 100."
  }
}

# -----------------------------------------------------------------------------
# Data Quality Analysis Configuration Variables
# -----------------------------------------------------------------------------

variable "bias_detection_threshold" {
  description = "Threshold for bias detection (0.0 to 1.0, where 0.1 = 10% difference)"
  type        = number
  default     = 0.1
  validation {
    condition     = var.bias_detection_threshold >= 0.0 && var.bias_detection_threshold <= 1.0
    error_message = "Bias detection threshold must be between 0.0 and 1.0."
  }
}

variable "vocabulary_diversity_threshold" {
  description = "Minimum vocabulary diversity threshold (0.0 to 1.0)"
  type        = number
  default     = 0.3
  validation {
    condition     = var.vocabulary_diversity_threshold >= 0.0 && var.vocabulary_diversity_threshold <= 1.0
    error_message = "Vocabulary diversity threshold must be between 0.0 and 1.0."
  }
}

variable "sample_size_for_analysis" {
  description = "Number of samples to analyze with Gemini (to control costs)"
  type        = number
  default     = 5
  validation {
    condition     = var.sample_size_for_analysis >= 1 && var.sample_size_for_analysis <= 50
    error_message = "Sample size for analysis must be between 1 and 50."
  }
}

# -----------------------------------------------------------------------------
# Cost Control Variables
# -----------------------------------------------------------------------------

variable "daily_api_call_limit" {
  description = "Daily limit for Vertex AI API calls to control costs"
  type        = number
  default     = 100
  validation {
    condition     = var.daily_api_call_limit >= 10 && var.daily_api_call_limit <= 1000
    error_message = "Daily API call limit must be between 10 and 1000."
  }
}

variable "bucket_lifecycle_days" {
  description = "Number of days after which objects in the bucket are automatically deleted"
  type        = number
  default     = 30
  validation {
    condition     = var.bucket_lifecycle_days >= 1 && var.bucket_lifecycle_days <= 365
    error_message = "Bucket lifecycle days must be between 1 and 365."
  }
}

# -----------------------------------------------------------------------------
# Notification and Alerting Variables
# -----------------------------------------------------------------------------

variable "notification_email" {
  description = "Email address for receiving analysis completion notifications"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_failure_alerts" {
  description = "Enable Cloud Monitoring alerts for function failures"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Custom Labels and Tags
# -----------------------------------------------------------------------------

variable "custom_labels" {
  description = "Custom labels to apply to all resources"
  type        = map(string)
  default = {
    application = "training-data-quality"
    owner      = "ml-team"
    cost-center = "research-and-development"
  }
  validation {
    condition = alltrue([
      for k, v in var.custom_labels : can(regex("^[a-z]([a-z0-9_-]*[a-z0-9])?$", k))
    ])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# -----------------------------------------------------------------------------
# Network Configuration Variables (Advanced)
# -----------------------------------------------------------------------------

variable "vpc_network" {
  description = "VPC network for the Cloud Function (leave empty for default network)"
  type        = string
  default     = ""
}

variable "subnet" {
  description = "Subnet for the Cloud Function (leave empty for default subnet)"
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