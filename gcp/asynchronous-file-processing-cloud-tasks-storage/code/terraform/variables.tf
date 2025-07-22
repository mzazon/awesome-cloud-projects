# Project configuration variables
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The GCP region where resources will be created"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone where resources will be created"
  type        = string
  default     = "us-central1-a"
}

# Resource naming variables
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "application_name" {
  description = "Name of the application for resource naming"
  type        = string
  default     = "file-processing"
}

# Cloud Storage configuration
variable "upload_bucket_location" {
  description = "Location for the file upload bucket"
  type        = string
  default     = "US"
}

variable "results_bucket_location" {
  description = "Location for the results bucket"
  type        = string
  default     = "US"
}

variable "bucket_storage_class" {
  description = "Storage class for buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD",
      "NEARLINE",
      "COLDLINE",
      "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning for storage buckets"
  type        = bool
  default     = true
}

variable "enable_bucket_autoclass" {
  description = "Enable autoclass for automatic storage class transitions"
  type        = bool
  default     = true
}

# Cloud Tasks configuration
variable "task_queue_max_dispatches_per_second" {
  description = "Maximum number of dispatches per second for the task queue"
  type        = number
  default     = 10
}

variable "task_queue_max_concurrent_dispatches" {
  description = "Maximum number of concurrent dispatches for the task queue"
  type        = number
  default     = 100
}

variable "task_queue_max_attempts" {
  description = "Maximum number of retry attempts for failed tasks"
  type        = number
  default     = 3
}

variable "task_queue_min_backoff" {
  description = "Minimum backoff time between retries"
  type        = string
  default     = "2s"
}

variable "task_queue_max_backoff" {
  description = "Maximum backoff time between retries"
  type        = string
  default     = "300s"
}

# Cloud Run configuration
variable "upload_service_image" {
  description = "Container image for the upload service"
  type        = string
  default     = "gcr.io/cloudrun/hello" # Placeholder - will be replaced after build
}

variable "processing_service_image" {
  description = "Container image for the processing service"
  type        = string
  default     = "gcr.io/cloudrun/hello" # Placeholder - will be replaced after build
}

variable "upload_service_memory" {
  description = "Memory allocation for upload service"
  type        = string
  default     = "1Gi"
}

variable "upload_service_cpu" {
  description = "CPU allocation for upload service"
  type        = string
  default     = "1"
}

variable "processing_service_memory" {
  description = "Memory allocation for processing service"
  type        = string
  default     = "2Gi"
}

variable "processing_service_cpu" {
  description = "CPU allocation for processing service"
  type        = string
  default     = "2"
}

variable "upload_service_concurrency" {
  description = "Maximum concurrent requests per instance for upload service"
  type        = number
  default     = 100
}

variable "processing_service_concurrency" {
  description = "Maximum concurrent requests per instance for processing service"
  type        = number
  default     = 50
}

variable "upload_service_max_instances" {
  description = "Maximum number of instances for upload service"
  type        = number
  default     = 10
}

variable "processing_service_max_instances" {
  description = "Maximum number of instances for processing service"
  type        = number
  default     = 20
}

# Pub/Sub configuration
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub subscription"
  type        = string
  default     = "7d"
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub messages"
  type        = number
  default     = 60
}

# IAM configuration
variable "enable_workload_identity" {
  description = "Enable workload identity for service accounts"
  type        = bool
  default     = true
}

# Monitoring and logging configuration
variable "enable_monitoring" {
  description = "Enable monitoring and logging for all resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
}

# Security configuration
variable "enable_vulnerability_scanning" {
  description = "Enable vulnerability scanning for container images"
  type        = bool
  default     = true
}

variable "allow_unauthenticated_upload" {
  description = "Allow unauthenticated access to upload service"
  type        = bool
  default     = true
}

# Resource tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "file-processing"
    environment = "dev"
    managed_by  = "terraform"
  }
}