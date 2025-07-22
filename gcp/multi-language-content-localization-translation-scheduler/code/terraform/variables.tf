# Variables for Multi-Language Content Localization Pipeline
# These variables allow customization of the translation infrastructure
# for different environments and requirements

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resources deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3",
      "asia-northeast1", "asia-southeast1", "asia-east1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Cloud Translation API."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and configuration"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "force_destroy" {
  description = "Allow Terraform to destroy storage buckets with content (use with caution)"
  type        = bool
  default     = false
}

# Cloud Function Configuration
variable "function_max_instances" {
  description = "Maximum number of Cloud Function instances for scaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function max instances must be between 1 and 1000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of Cloud Function instances to keep warm"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 100
    error_message = "Function min instances must be between 0 and 100."
  }
}

variable "log_level" {
  description = "Logging level for the translation function"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

# Scheduler Configuration
variable "batch_schedule" {
  description = "Cron schedule for batch translation processing (daily at 2 AM UTC by default)"
  type        = string
  default     = "0 2 * * *"
  
  validation {
    condition     = can(regex("^([0-9*,-/]+\\s+){4}[0-9*,-/]+$", var.batch_schedule))
    error_message = "Batch schedule must be a valid cron expression (5 fields)."
  }
}

variable "time_zone" {
  description = "Time zone for scheduled jobs"
  type        = string
  default     = "UTC"
}

# Storage Configuration
variable "source_file_prefix" {
  description = "File prefix filter for automatic translation triggers (empty for all files)"
  type        = string
  default     = ""
}

variable "storage_lifecycle_age_coldline" {
  description = "Age in days after which objects move to Coldline storage class"
  type        = number
  default     = 90
  
  validation {
    condition     = var.storage_lifecycle_age_coldline >= 30
    error_message = "Coldline storage age must be at least 30 days."
  }
}

variable "storage_lifecycle_age_delete" {
  description = "Age in days after which objects are deleted (0 to disable deletion)"
  type        = number
  default     = 365
  
  validation {
    condition     = var.storage_lifecycle_age_delete == 0 || var.storage_lifecycle_age_delete >= 30
    error_message = "Storage deletion age must be 0 (disabled) or at least 30 days."
  }
}

# Network Configuration
variable "vpc_connector" {
  description = "VPC Connector for Cloud Functions (optional, for enhanced security)"
  type        = string
  default     = null
}

# Translation Configuration
variable "custom_target_languages" {
  description = "Custom list of target languages for translation (ISO 639-1 codes)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for lang in var.custom_target_languages : 
      length(lang) == 2 && can(regex("^[a-z]{2}$", lang))
    ])
    error_message = "Target languages must be valid ISO 639-1 language codes (2 lowercase letters)."
  }
}

variable "supported_file_types" {
  description = "List of supported file extensions for translation"
  type        = list(string)
  default     = [".txt", ".md", ".html", ".json", ".csv"]
  
  validation {
    condition = alltrue([
      for ext in var.supported_file_types : 
      startswith(ext, ".")
    ])
    error_message = "File extensions must start with a dot (e.g., '.txt')."
  }
}

# Monitoring Configuration
variable "enable_monitoring_dashboard" {
  description = "Enable creation of Cloud Monitoring dashboard for the translation pipeline"
  type        = bool
  default     = true
}

variable "enable_alerting" {
  description = "Enable alerting for translation pipeline errors and performance issues"
  type        = bool
  default     = false
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for alerts (requires enable_alerting = true)"
  type        = list(string)
  default     = []
}

# Security Configuration
variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access for enhanced security"
  type        = bool
  default     = true
}

variable "enable_public_access_prevention" {
  description = "Prevent public access to storage buckets"
  type        = bool
  default     = true
}

variable "bucket_encryption_key" {
  description = "Customer-managed encryption key for bucket encryption (optional)"
  type        = string
  default     = null
}

# Cost Optimization
variable "enable_autoclass" {
  description = "Enable Autoclass for automatic storage class transitions based on access patterns"
  type        = bool
  default     = false
}

variable "enable_requestor_pays" {
  description = "Enable Requestor Pays billing for storage buckets"
  type        = bool
  default     = false
}

# Advanced Configuration
variable "pubsub_message_retention_days" {
  description = "Number of days to retain Pub/Sub messages"
  type        = number
  default     = 7
  
  validation {
    condition     = var.pubsub_message_retention_days >= 1 && var.pubsub_message_retention_days <= 31
    error_message = "Message retention must be between 1 and 31 days."
  }
}

variable "function_timeout_seconds" {
  description = "Cloud Function timeout in seconds"
  type        = number
  default     = 540
  
  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function"
  type        = string
  default     = "512M"
  
  validation {
    condition = contains([
      "128M", "256M", "512M", "1G", "2G", "4G", "8G"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128M, 256M, 512M, 1G, 2G, 4G, 8G."
  }
}

variable "function_cpu" {
  description = "CPU allocation for Cloud Function"
  type        = string
  default     = "1"
  
  validation {
    condition = contains([
      "0.08", "0.17", "0.33", "0.58", "1", "2", "4", "6", "8"
    ], var.function_cpu)
    error_message = "Function CPU must be one of the supported values."
  }
}

# Translation API Configuration
variable "translation_model" {
  description = "Translation model to use (nmt for Neural Machine Translation, base for older model)"
  type        = string
  default     = "nmt"
  
  validation {
    condition     = contains(["nmt", "base"], var.translation_model)
    error_message = "Translation model must be 'nmt' or 'base'."
  }
}

variable "enable_translation_glossary" {
  description = "Enable custom glossary for consistent translation of specific terms"
  type        = bool
  default     = false
}

variable "glossary_source_language" {
  description = "Source language for translation glossary (ISO 639-1 code)"
  type        = string
  default     = "en"
  
  validation {
    condition     = length(var.glossary_source_language) == 2
    error_message = "Glossary source language must be a valid ISO 639-1 language code."
  }
}

# Additional Features
variable "enable_content_classification" {
  description = "Enable automatic content classification before translation"
  type        = bool
  default     = false
}

variable "enable_quality_scoring" {
  description = "Enable translation quality scoring and validation"
  type        = bool
  default     = false
}

variable "enable_human_review_workflow" {
  description = "Enable human review workflow for high-priority content"
  type        = bool
  default     = false
}

variable "batch_processing_concurrency" {
  description = "Maximum concurrent translations during batch processing"
  type        = number
  default     = 5
  
  validation {
    condition     = var.batch_processing_concurrency >= 1 && var.batch_processing_concurrency <= 20
    error_message = "Batch processing concurrency must be between 1 and 20."
  }
}

# Resource Tagging
variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : 
      can(regex("^[a-z0-9_-]{1,63}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and dashes, and be 63 characters or less."
  }
}