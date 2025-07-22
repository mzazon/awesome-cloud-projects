# =============================================================================
# Variables for Edge-to-Cloud Video Analytics Infrastructure
# =============================================================================

# Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
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
      "asia-east1", "asia-east2", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone within the region"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

# Storage Configuration
variable "bucket_prefix" {
  description = "Prefix for all Cloud Storage bucket names (must be globally unique)"
  type        = string
  default     = "video-analytics"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_]{1,61}[a-z0-9]$", var.bucket_prefix))
    error_message = "Bucket prefix must be 3-63 characters, start and end with alphanumeric, and contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

variable "storage_class" {
  description = "Default storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable object versioning on storage buckets"
  type        = bool
  default     = true
}

variable "lifecycle_management" {
  description = "Enable lifecycle management policies for cost optimization"
  type        = bool
  default     = true
}

# Cloud Functions Configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions (python39, python310, python311)"
  type        = string
  default     = "python39"
  validation {
    condition = contains([
      "python39", "python310", "python311", "nodejs16", "nodejs18", "nodejs20"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Google Cloud Functions runtime."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "1Gi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi", "16Gi", "32Gi"
    ], var.function_memory)
    error_message = "Function memory must be a valid allocation (128Mi to 32Gi)."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds (1-540)"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

variable "min_instances" {
  description = "Minimum number of function instances"
  type        = number
  default     = 0
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

# Vertex AI Configuration
variable "vertex_ai_region" {
  description = "Region for Vertex AI operations (may differ from main region)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.vertex_ai_region)
    error_message = "Vertex AI region must support Vertex AI services."
  }
}

variable "enable_automl" {
  description = "Enable AutoML capabilities for custom model training"
  type        = bool
  default     = false
}

variable "video_analysis_features" {
  description = "List of video analysis features to enable"
  type        = list(string)
  default = [
    "OBJECT_TRACKING",
    "LABEL_DETECTION", 
    "SHOT_CHANGE_DETECTION",
    "TEXT_DETECTION"
  ]
  validation {
    condition = alltrue([
      for feature in var.video_analysis_features : contains([
        "OBJECT_TRACKING",
        "LABEL_DETECTION",
        "SHOT_CHANGE_DETECTION", 
        "TEXT_DETECTION",
        "FACE_DETECTION",
        "PERSON_DETECTION",
        "LOGO_RECOGNITION",
        "SPEECH_TRANSCRIPTION"
      ], feature)
    ])
    error_message = "All video analysis features must be valid Vertex AI Video Intelligence features."
  }
}

# Media CDN Configuration
variable "enable_cdn" {
  description = "Enable Media CDN for video content delivery"
  type        = bool
  default     = true
}

variable "cdn_domain_name" {
  description = "Custom domain name for Media CDN (required if enable_cdn is true)"
  type        = string
  default     = "video-cdn.example.com"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", var.cdn_domain_name))
    error_message = "CDN domain name must be a valid domain format."
  }
}

variable "cdn_cache_ttl" {
  description = "Default cache TTL for CDN in seconds"
  type        = number
  default     = 3600
  validation {
    condition     = var.cdn_cache_ttl >= 0 && var.cdn_cache_ttl <= 2592000
    error_message = "CDN cache TTL must be between 0 and 2592000 seconds (30 days)."
  }
}

variable "cdn_max_ttl" {
  description = "Maximum cache TTL for CDN in seconds"
  type        = number
  default     = 86400
  validation {
    condition     = var.cdn_max_ttl >= 0 && var.cdn_max_ttl <= 2592000
    error_message = "CDN max TTL must be between 0 and 2592000 seconds (30 days)."
  }
}

variable "enable_compression" {
  description = "Enable automatic compression for CDN responses"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_public_access_prevention" {
  description = "Enable public access prevention on storage buckets"
  type        = bool
  default     = true
}

variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access for storage buckets"
  type        = bool
  default     = true
}

variable "allowed_cors_origins" {
  description = "List of allowed CORS origins for storage buckets"
  type        = list(string)
  default     = ["*"]
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (optional, uses Google-managed keys if not specified)"
  type        = string
  default     = ""
}

# Monitoring and Alerting
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "storage_alert_threshold_gb" {
  description = "Storage usage threshold in GB for alerts"
  type        = number
  default     = 100
  validation {
    condition     = var.storage_alert_threshold_gb > 0
    error_message = "Storage alert threshold must be greater than 0."
  }
}

variable "function_error_threshold" {
  description = "Number of function errors to trigger alert"
  type        = number
  default     = 5
  validation {
    condition     = var.function_error_threshold > 0
    error_message = "Function error threshold must be greater than 0."
  }
}

# Environment and Tagging
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition = contains([
      "dev", "development", "staging", "stage", "prod", "production", "test"
    ], var.environment)
    error_message = "Environment must be one of: dev, development, staging, stage, prod, production, test."
  }
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for key, value in var.labels : can(regex("^[a-z0-9_-]{1,63}$", key))
    ])
    error_message = "Label keys must be 1-63 characters and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "cost_center" {
  description = "Cost center for billing attribution"
  type        = string
  default     = "engineering"
}

variable "team" {
  description = "Team responsible for the infrastructure"
  type        = string
  default     = "data-platform"
}

# Advanced Configuration
variable "enable_private_google_access" {
  description = "Enable Private Google Access for VPC resources"
  type        = bool
  default     = true
}

variable "network_tier" {
  description = "Network service tier for external IP addresses"
  type        = string
  default     = "PREMIUM"
  validation {
    condition = contains([
      "PREMIUM", "STANDARD"
    ], var.network_tier)
    error_message = "Network tier must be PREMIUM or STANDARD."
  }
}

variable "enable_audit_logs" {
  description = "Enable audit logging for all services"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days (10 years)."
  }
}

# Performance Configuration
variable "video_processing_concurrency" {
  description = "Maximum concurrent video processing operations"
  type        = number
  default     = 5
  validation {
    condition     = var.video_processing_concurrency >= 1 && var.video_processing_concurrency <= 100
    error_message = "Video processing concurrency must be between 1 and 100."
  }
}

variable "enable_preemptible_instances" {
  description = "Use preemptible instances for cost optimization (where applicable)"
  type        = bool
  default     = false
}

variable "auto_scaling_target_cpu" {
  description = "Target CPU utilization for auto-scaling (0.0-1.0)"
  type        = number
  default     = 0.7
  validation {
    condition     = var.auto_scaling_target_cpu > 0.0 && var.auto_scaling_target_cpu <= 1.0
    error_message = "Auto-scaling target CPU must be between 0.0 and 1.0."
  }
}

# Data Processing Configuration
variable "batch_size" {
  description = "Batch size for video processing operations"
  type        = number
  default     = 10
  validation {
    condition     = var.batch_size >= 1 && var.batch_size <= 1000
    error_message = "Batch size must be between 1 and 1000."
  }
}

variable "enable_streaming_analytics" {
  description = "Enable real-time streaming analytics capabilities"
  type        = bool
  default     = false
}

variable "analytics_output_format" {
  description = "Output format for analytics results"
  type        = string
  default     = "json"
  validation {
    condition = contains([
      "json", "csv", "parquet", "avro"
    ], var.analytics_output_format)
    error_message = "Analytics output format must be one of: json, csv, parquet, avro."
  }
}