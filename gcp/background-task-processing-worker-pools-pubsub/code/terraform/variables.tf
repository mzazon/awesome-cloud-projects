# Project configuration variables
variable "project_id" {
  description = "The Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "The Google Cloud region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The Google Cloud zone"
  type        = string
  default     = "us-central1-a"
}

# Resource naming variables
variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "bg-task"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Pub/Sub configuration
variable "topic_name" {
  description = "Name of the Pub/Sub topic for task queue"
  type        = string
  default     = ""
}

variable "subscription_name" {
  description = "Name of the Pub/Sub subscription"
  type        = string
  default     = ""
}

variable "message_retention_duration" {
  description = "How long to retain unacknowledged messages (in seconds)"
  type        = string
  default     = "604800s" # 7 days
}

variable "ack_deadline_seconds" {
  description = "Maximum time for a subscriber to acknowledge a message"
  type        = number
  default     = 600
}

variable "max_delivery_attempts" {
  description = "Maximum number of delivery attempts for messages"
  type        = number
  default     = 5
}

# Cloud Storage configuration
variable "bucket_name" {
  description = "Name of the Cloud Storage bucket for file processing"
  type        = string
  default     = ""
}

variable "storage_class" {
  description = "Cloud Storage bucket storage class"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "bucket_lifecycle_age" {
  description = "Number of days after which to delete objects"
  type        = number
  default     = 30
}

# Cloud Run Job configuration
variable "job_name" {
  description = "Name of the Cloud Run Job for background processing"
  type        = string
  default     = ""
}

variable "job_cpu" {
  description = "CPU allocation for Cloud Run Job tasks"
  type        = string
  default     = "1"
  
  validation {
    condition = contains([
      "0.08", "0.17", "0.25", "0.33", "0.5", "0.58", "0.67", "0.75", "0.83", "1", "2", "4", "6", "8"
    ], var.job_cpu)
    error_message = "CPU must be a valid Cloud Run CPU value."
  }
}

variable "job_memory" {
  description = "Memory allocation for Cloud Run Job tasks"
  type        = string
  default     = "1Gi"
  
  validation {
    condition = can(regex("^[0-9]+(Mi|Gi)$", var.job_memory))
    error_message = "Memory must be specified in Mi or Gi format (e.g., 512Mi, 1Gi)."
  }
}

variable "job_max_retries" {
  description = "Maximum number of retries for failed job executions"
  type        = number
  default     = 3
  
  validation {
    condition     = var.job_max_retries >= 0 && var.job_max_retries <= 10
    error_message = "Max retries must be between 0 and 10."
  }
}

variable "job_parallelism" {
  description = "Number of tasks to run in parallel"
  type        = number
  default     = 1
  
  validation {
    condition     = var.job_parallelism >= 1 && var.job_parallelism <= 1000
    error_message = "Parallelism must be between 1 and 1000."
  }
}

variable "job_task_count" {
  description = "Number of tasks to run"
  type        = number
  default     = 1
  
  validation {
    condition     = var.job_task_count >= 1 && var.job_task_count <= 10000
    error_message = "Task count must be between 1 and 10000."
  }
}

# Cloud Run API Service configuration
variable "api_service_name" {
  description = "Name of the Cloud Run API service"
  type        = string
  default     = ""
}

variable "api_cpu" {
  description = "CPU allocation for Cloud Run API service"
  type        = string
  default     = "1"
  
  validation {
    condition = contains([
      "0.08", "0.17", "0.25", "0.33", "0.5", "0.58", "0.67", "0.75", "0.83", "1", "2", "4", "6", "8"
    ], var.api_cpu)
    error_message = "CPU must be a valid Cloud Run CPU value."
  }
}

variable "api_memory" {
  description = "Memory allocation for Cloud Run API service"
  type        = string
  default     = "512Mi"
  
  validation {
    condition = can(regex("^[0-9]+(Mi|Gi)$", var.api_memory))
    error_message = "Memory must be specified in Mi or Gi format (e.g., 512Mi, 1Gi)."
  }
}

variable "api_min_instances" {
  description = "Minimum number of API service instances"
  type        = number
  default     = 0
  
  validation {
    condition     = var.api_min_instances >= 0 && var.api_min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "api_max_instances" {
  description = "Maximum number of API service instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.api_max_instances >= 1 && var.api_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the API service"
  type        = bool
  default     = true
}

# Container image configuration
variable "container_registry" {
  description = "Container registry to use for images"
  type        = string
  default     = "gcr.io"
  
  validation {
    condition = contains([
      "gcr.io", "us.gcr.io", "eu.gcr.io", "asia.gcr.io"
    ], var.container_registry)
    error_message = "Container registry must be gcr.io, us.gcr.io, eu.gcr.io, or asia.gcr.io."
  }
}

# IAM configuration
variable "create_service_accounts" {
  description = "Whether to create new service accounts or use existing ones"
  type        = bool
  default     = true
}

variable "existing_worker_service_account" {
  description = "Email of existing service account for worker job (if not creating new ones)"
  type        = string
  default     = ""
}

variable "existing_api_service_account" {
  description = "Email of existing service account for API service (if not creating new ones)"
  type        = string
  default     = ""
}

# Monitoring and logging
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

# Labels and tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "recipe"     = "background-task-processing"
  }
}