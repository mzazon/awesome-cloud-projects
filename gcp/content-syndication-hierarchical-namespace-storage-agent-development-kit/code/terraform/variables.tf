# Input Variables for Content Syndication Platform
# These variables allow customization of the infrastructure deployment
# while maintaining security and best practices

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region for regional resources (workflows, functions, etc.)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports all required services."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone cannot be empty."
  }
}

variable "storage_location" {
  description = "Location for Cloud Storage bucket (US, EU, ASIA, or specific region)"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west4", "asia-east1", "asia-southeast1"
    ], var.storage_location)
    error_message = "Storage location must be a valid multi-region or regional location."
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

variable "content_bucket_name" {
  description = "Name for the hierarchical namespace storage bucket (must be globally unique)"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_]{1,61}[a-z0-9]$", var.content_bucket_name)) || var.content_bucket_name == ""
    error_message = "Bucket name must be 3-63 characters, start and end with lowercase letter or number, and contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

variable "enable_content_lifecycle" {
  description = "Enable automatic content lifecycle management (archiving and deletion)"
  type        = bool
  default     = true
}

variable "content_retention_days" {
  description = "Number of days to retain content before moving to nearline storage"
  type        = number
  default     = 30
  validation {
    condition     = var.content_retention_days >= 1 && var.content_retention_days <= 365
    error_message = "Content retention days must be between 1 and 365."
  }
}

variable "enable_cors" {
  description = "Enable CORS on the content bucket for web distribution"
  type        = bool
  default     = true
}

variable "allowed_cors_origins" {
  description = "List of allowed CORS origins for content distribution"
  type        = list(string)
  default     = ["*"]
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (512MB, 1GB, 2GB, 4GB, 8GB)"
  type        = string
  default     = "1GB"
  validation {
    condition     = contains(["512MB", "1GB", "2GB", "4GB", "8GB"], var.function_memory)
    error_message = "Function memory must be one of: 512MB, 1GB, 2GB, 4GB, 8GB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds (max 540 for 2nd gen)"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances for auto-scaling"
  type        = number
  default     = 100
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

variable "enable_vertex_ai" {
  description = "Enable Vertex AI components for agent development kit"
  type        = bool
  default     = true
}

variable "vertex_ai_location" {
  description = "Location for Vertex AI resources (us-central1, us-east1, europe-west4, asia-northeast1)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west4",
      "asia-northeast1", "asia-southeast1"
    ], var.vertex_ai_location)
    error_message = "Vertex AI location must be a supported region for AI/ML services."
  }
}

variable "workflow_call_log_level" {
  description = "Log level for Cloud Workflows (LOG_ALL_CALLS, LOG_ERRORS_ONLY, LOG_NONE)"
  type        = string
  default     = "LOG_ERRORS_ONLY"
  validation {
    condition     = contains(["LOG_ALL_CALLS", "LOG_ERRORS_ONLY", "LOG_NONE"], var.workflow_call_log_level)
    error_message = "Workflow log level must be one of: LOG_ALL_CALLS, LOG_ERRORS_ONLY, LOG_NONE."
  }
}

variable "enable_monitoring" {
  description = "Enable monitoring and alerting for the platform"
  type        = bool
  default     = true
}

variable "enable_security_scanning" {
  description = "Enable security scanning for content processing"
  type        = bool
  default     = false
}

variable "content_categories" {
  description = "List of content categories for folder organization"
  type        = list(string)
  default     = ["video", "image", "audio", "document"]
  validation {
    condition     = length(var.content_categories) > 0
    error_message = "At least one content category must be specified."
  }
}

variable "distribution_channels" {
  description = "Map of content types to their distribution channels"
  type        = map(list(string))
  default = {
    video    = ["youtube", "tiktok", "instagram", "facebook"]
    image    = ["instagram", "pinterest", "twitter", "facebook"]
    audio    = ["spotify", "apple_music", "podcast", "youtube"]
    document = ["medium", "linkedin", "blog", "website"]
  }
}

variable "quality_thresholds" {
  description = "Quality assessment thresholds for content approval"
  type = object({
    minimum_score        = number
    enable_auto_approval = bool
    require_human_review = bool
  })
  default = {
    minimum_score        = 0.75
    enable_auto_approval = true
    require_human_review = false
  }
  validation {
    condition     = var.quality_thresholds.minimum_score >= 0.0 && var.quality_thresholds.minimum_score <= 1.0
    error_message = "Quality threshold minimum score must be between 0.0 and 1.0."
  }
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    project     = "content-syndication"
    managed_by  = "terraform"
    environment = "dev"
  }
}