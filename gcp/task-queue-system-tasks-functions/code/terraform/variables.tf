# Core project configuration variables
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
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

# Task queue configuration variables
variable "queue_name" {
  description = "Name of the Cloud Tasks queue"
  type        = string
  default     = "background-tasks"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.queue_name))
    error_message = "Queue name must start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "queue_max_attempts" {
  description = "Maximum number of retry attempts for failed tasks"
  type        = number
  default     = 3
  validation {
    condition     = var.queue_max_attempts >= 1 && var.queue_max_attempts <= 100
    error_message = "Max attempts must be between 1 and 100."
  }
}

variable "queue_max_retry_duration" {
  description = "Maximum retry duration in seconds"
  type        = string
  default     = "300s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.queue_max_retry_duration))
    error_message = "Max retry duration must be in format 'Xs' where X is a number."
  }
}

variable "queue_max_doublings" {
  description = "Maximum number of times to double the interval between retries"
  type        = number
  default     = 5
  validation {
    condition     = var.queue_max_doublings >= 0 && var.queue_max_doublings <= 16
    error_message = "Max doublings must be between 0 and 16."
  }
}

# Cloud Function configuration variables
variable "function_name" {
  description = "Name of the Cloud Function that processes tasks"
  type        = string
  default     = "task-processor"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = string
  default     = "256M"
  validation {
    condition = contains([
      "128M", "256M", "512M", "1024M", "2048M", "4096M", "8192M"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128M, 256M, 512M, 1024M, 2048M, 4096M, 8192M."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime environment for the Cloud Function"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312",
      "nodejs18", "nodejs20", "go119", "go120", "go121",
      "java11", "java17", "dotnet6", "ruby30", "ruby32"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

# Storage configuration variables
variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (full name will be {prefix}-task-results)"
  type        = string
  default     = ""
  validation {
    condition     = var.bucket_name_prefix == "" || can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens, and cannot start or end with a hyphen."
  }
}

variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_lifecycle_age" {
  description = "Number of days after which objects in the bucket will be deleted (0 to disable)"
  type        = number
  default     = 30
  validation {
    condition     = var.bucket_lifecycle_age >= 0 && var.bucket_lifecycle_age <= 365
    error_message = "Bucket lifecycle age must be between 0 and 365 days."
  }
}

# IAM and security variables
variable "allow_unauthenticated_function_invocation" {
  description = "Whether to allow unauthenticated invocation of the Cloud Function"
  type        = bool
  default     = true
}

variable "enable_audit_logs" {
  description = "Whether to enable audit logs for the task queue system"
  type        = bool
  default     = true
}

# Monitoring and alerting variables
variable "enable_monitoring" {
  description = "Whether to create monitoring resources (dashboards, alerts)"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring alerts (optional)"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Resource labeling variables
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    project     = "task-queue-system"
    managed_by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain lowercase letters, numbers, underscores, and hyphens."
  }
}

# Feature flags for optional components
variable "create_sample_tasks" {
  description = "Whether to create sample task creation resources"
  type        = bool
  default     = true
}

variable "enable_dead_letter_queue" {
  description = "Whether to create a dead letter queue for failed tasks"
  type        = bool
  default     = false
}