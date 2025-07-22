# Input Variables for Content Moderation Infrastructure
# This file defines all configurable parameters for the content moderation system

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid GCP region (e.g., us-central1, europe-west1)."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone (e.g., us-central1-a, europe-west1-b)."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "content-mod"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.resource_prefix))
    error_message = "Resource prefix must be 3-21 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_class" {
  description = "Default storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_location" {
  description = "Location for Cloud Storage buckets (region or multi-region)"
  type        = string
  default     = null # Will use var.region if not specified
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age_days" {
  description = "Number of days after which to transition quarantine bucket objects to Nearline storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.bucket_lifecycle_age_days >= 1 && var.bucket_lifecycle_age_days <= 365
    error_message = "Bucket lifecycle age must be between 1 and 365 days."
  }
}

variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topics (in seconds)"
  type        = string
  default     = "604800s" # 7 days
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., 604800s)."
  }
}

variable "pubsub_ack_deadline" {
  description = "Acknowledgment deadline for Pub/Sub subscriptions (in seconds)"
  type        = number
  default     = 600
  
  validation {
    condition     = var.pubsub_ack_deadline >= 10 && var.pubsub_ack_deadline <= 600
    error_message = "ACK deadline must be between 10 and 600 seconds."
  }
}

variable "pubsub_max_delivery_attempts" {
  description = "Maximum delivery attempts for Pub/Sub messages"
  type        = number
  default     = 3
  
  validation {
    condition     = var.pubsub_max_delivery_attempts >= 1 && var.pubsub_max_delivery_attempts <= 100
    error_message = "Max delivery attempts must be between 1 and 100."
  }
}

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = number
  default     = 1024
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (in seconds)"
  type        = number
  default     = 540
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of instances for Cloud Functions"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of instances for Cloud Functions"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "notification_function_memory_mb" {
  description = "Memory allocation for notification Cloud Function (in MB)"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.notification_function_memory_mb)
    error_message = "Notification function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "notification_function_timeout" {
  description = "Timeout for notification Cloud Function (in seconds)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.notification_function_timeout >= 1 && var.notification_function_timeout <= 540
    error_message = "Notification function timeout must be between 1 and 540 seconds."
  }
}

variable "vertex_ai_location" {
  description = "Location for Vertex AI resources (must support Gemini models)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.vertex_ai_location)
    error_message = "Vertex AI location must be a region that supports Gemini models."
  }
}

variable "enable_apis" {
  description = "List of GCP APIs to enable for the project"
  type        = list(string)
  default = [
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "aiplatform.googleapis.com",
    "eventarc.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "content-moderation"
    managed-by  = "terraform"
    cost-center = "ai-ml"
  }
}

variable "force_destroy_buckets" {
  description = "Force destroy Cloud Storage buckets even if they contain objects (use with caution)"
  type        = bool
  default     = false
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access on Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "enable_bucket_public_access_prevention" {
  description = "Enable public access prevention on Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "create_notification_function" {
  description = "Whether to create the notification function for quarantined content"
  type        = bool
  default     = true
}

variable "custom_service_account_email" {
  description = "Custom service account email to use (if not provided, one will be created)"
  type        = string
  default     = null
}

variable "enable_cloud_armor" {
  description = "Enable Cloud Armor for additional security (requires additional configuration)"
  type        = bool
  default     = false
}

variable "enable_private_google_access" {
  description = "Enable Private Google Access for enhanced security"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}