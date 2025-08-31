# Variables for GCP Smart Invoice Processing Infrastructure
# These variables allow customization of the deployment while maintaining best practices

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Document AI."
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
  default     = "invoice-proc"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bucket_location" {
  description = "Location for Cloud Storage buckets (can be region, dual-region, or multi-region)"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA",
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.bucket_location)
    error_message = "Bucket location must be a valid Google Cloud Storage location."
  }
}

variable "bucket_storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on Cloud Storage buckets for audit trail"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age_days" {
  description = "Number of days after which to delete old bucket objects"
  type        = number
  default     = 365
  validation {
    condition     = var.bucket_lifecycle_age_days > 0
    error_message = "Lifecycle age must be greater than 0."
  }
}

variable "document_ai_processor_type" {
  description = "Type of Document AI processor to create"
  type        = string
  default     = "INVOICE_PROCESSOR"
  validation {
    condition     = contains(["INVOICE_PROCESSOR", "EXPENSE_PROCESSOR", "FORM_PARSER"], var.document_ai_processor_type)
    error_message = "Processor type must be a valid Document AI processor type."
  }
}

variable "workflow_timeout_seconds" {
  description = "Timeout for Cloud Workflows execution in seconds"
  type        = number
  default     = 600
  validation {
    condition     = var.workflow_timeout_seconds > 0 && var.workflow_timeout_seconds <= 31536000
    error_message = "Workflow timeout must be between 1 and 31536000 seconds (1 year)."
  }
}

variable "cloud_tasks_max_dispatches_per_second" {
  description = "Maximum number of tasks dispatched per second from Cloud Tasks queue"
  type        = number
  default     = 10
  validation {
    condition     = var.cloud_tasks_max_dispatches_per_second > 0 && var.cloud_tasks_max_dispatches_per_second <= 500
    error_message = "Max dispatches per second must be between 1 and 500."
  }
}

variable "cloud_tasks_max_concurrent_dispatches" {
  description = "Maximum number of concurrent task dispatches from Cloud Tasks queue"
  type        = number
  default     = 5
  validation {
    condition     = var.cloud_tasks_max_concurrent_dispatches > 0 && var.cloud_tasks_max_concurrent_dispatches <= 1000
    error_message = "Max concurrent dispatches must be between 1 and 1000."
  }
}

variable "cloud_tasks_max_retry_attempts" {
  description = "Maximum number of retry attempts for failed tasks"
  type        = number
  default     = 3
  validation {
    condition     = var.cloud_tasks_max_retry_attempts >= 0 && var.cloud_tasks_max_retry_attempts <= 100
    error_message = "Max retry attempts must be between 0 and 100."
  }
}

variable "cloud_function_memory_mb" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 256
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.cloud_function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "cloud_function_timeout_seconds" {
  description = "Timeout for Cloud Functions execution in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.cloud_function_timeout_seconds > 0 && var.cloud_function_timeout_seconds <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

variable "cloud_function_runtime" {
  description = "Runtime environment for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312",
      "nodejs16", "nodejs18", "nodejs20",
      "go119", "go120", "go121",
      "java11", "java17", "java21"
    ], var.cloud_function_runtime)
    error_message = "Runtime must be a supported Cloud Functions runtime."
  }
}

variable "notification_emails" {
  description = "List of email addresses for approval notifications"
  type        = list(string)
  default = [
    "manager@company.com",
    "director@company.com", 
    "cfo@company.com"
  ]
  validation {
    condition     = length(var.notification_emails) > 0
    error_message = "At least one notification email must be provided."
  }
}

variable "approval_amount_thresholds" {
  description = "Invoice amount thresholds for different approval levels"
  type = object({
    manager_threshold   = number
    director_threshold  = number
    executive_threshold = number
  })
  default = {
    manager_threshold   = 1000
    director_threshold  = 5000
    executive_threshold = 10000
  }
  validation {
    condition = (
      var.approval_amount_thresholds.manager_threshold > 0 &&
      var.approval_amount_thresholds.director_threshold > var.approval_amount_thresholds.manager_threshold &&
      var.approval_amount_thresholds.executive_threshold > var.approval_amount_thresholds.director_threshold
    )
    error_message = "Approval thresholds must be positive and in ascending order: manager < director < executive."
  }
}

variable "enable_audit_logging" {
  description = "Enable audit logging for the invoice processing system"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable monitoring and alerting for the system"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "invoice-processing"
    managed-by  = "terraform"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}