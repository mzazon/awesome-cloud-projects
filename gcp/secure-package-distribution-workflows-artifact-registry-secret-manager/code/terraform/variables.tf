# Variables for Secure Package Distribution Workflows
# This file defines all configurable parameters for the infrastructure

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_id))
    error_message = "Project ID must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "secure-package-distribution"
  }
}

# Artifact Registry Variables
variable "repository_formats" {
  description = "List of repository formats to create (docker, npm, maven, python)"
  type        = list(string)
  default     = ["docker", "npm", "maven"]
  validation {
    condition = alltrue([
      for format in var.repository_formats :
      contains(["docker", "npm", "maven", "python", "apt", "yum", "go", "generic"], format)
    ])
    error_message = "Repository formats must be valid Artifact Registry formats."
  }
}

variable "cleanup_policy_enabled" {
  description = "Enable cleanup policies for repositories"
  type        = bool
  default     = true
}

variable "cleanup_policy_keep_count" {
  description = "Number of versions to keep for each package"
  type        = number
  default     = 10
  validation {
    condition     = var.cleanup_policy_keep_count > 0
    error_message = "Keep count must be a positive number."
  }
}

variable "cleanup_policy_older_than" {
  description = "Delete versions older than this duration (e.g., 30d, 2160h)"
  type        = string
  default     = "30d"
  validation {
    condition     = can(regex("^[0-9]+[dhms]$", var.cleanup_policy_older_than))
    error_message = "Duration must be in format like '30d', '720h', '43200m', or '2592000s'."
  }
}

# Secret Manager Variables
variable "secret_replication_policy" {
  description = "Replication policy for secrets (automatic or user-managed)"
  type        = string
  default     = "automatic"
  validation {
    condition     = contains(["automatic", "user-managed"], var.secret_replication_policy)
    error_message = "Secret replication policy must be 'automatic' or 'user-managed'."
  }
}

variable "secret_rotation_period" {
  description = "Secret rotation period in seconds (minimum 3600 seconds)"
  type        = number
  default     = 2592000 # 30 days
  validation {
    condition     = var.secret_rotation_period >= 3600
    error_message = "Secret rotation period must be at least 3600 seconds (1 hour)."
  }
}

# Cloud Function Variables
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python37", "python38", "python39", "python310", "python311", "python312",
      "nodejs16", "nodejs18", "nodejs20", "go116", "go118", "go119", "go120", "go121",
      "java11", "java17", "java21", "dotnet3", "dotnet6", "ruby27", "ruby30", "ruby32"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Google Cloud Functions runtime."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (MB)"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0
    error_message = "Minimum instances must be non-negative."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 100
  validation {
    condition     = var.function_max_instances >= 1
    error_message = "Maximum instances must be at least 1."
  }
}

# Cloud Scheduler Variables
variable "scheduler_timezone" {
  description = "Timezone for Cloud Scheduler jobs"
  type        = string
  default     = "America/New_York"
}

variable "scheduler_nightly_schedule" {
  description = "Cron schedule for nightly package distribution"
  type        = string
  default     = "0 2 * * *"
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.scheduler_nightly_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "scheduler_weekly_schedule" {
  description = "Cron schedule for weekly staging deployments"
  type        = string
  default     = "0 6 * * 1"
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.scheduler_weekly_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

# Cloud Tasks Variables
variable "task_queue_max_dispatches_per_second" {
  description = "Maximum dispatches per second for task queues"
  type        = number
  default     = 10
  validation {
    condition     = var.task_queue_max_dispatches_per_second > 0
    error_message = "Max dispatches per second must be positive."
  }
}

variable "task_queue_max_concurrent_dispatches" {
  description = "Maximum concurrent dispatches for task queues"
  type        = number
  default     = 5
  validation {
    condition     = var.task_queue_max_concurrent_dispatches > 0
    error_message = "Max concurrent dispatches must be positive."
  }
}

variable "task_queue_max_retry_duration" {
  description = "Maximum retry duration for task queues (seconds)"
  type        = number
  default     = 3600
  validation {
    condition     = var.task_queue_max_retry_duration >= 60
    error_message = "Max retry duration must be at least 60 seconds."
  }
}

# Monitoring Variables
variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "If provided, notification email must be a valid email address."
  }
}

variable "enable_monitoring" {
  description = "Enable monitoring and alerting"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days > 0
    error_message = "Log retention days must be positive."
  }
}

# Security Variables
variable "enable_audit_logging" {
  description = "Enable audit logging for all resources"
  type        = bool
  default     = true
}

variable "kms_key_rotation_period" {
  description = "KMS key rotation period in seconds (minimum 86400 seconds)"
  type        = number
  default     = 7776000 # 90 days
  validation {
    condition     = var.kms_key_rotation_period >= 86400
    error_message = "KMS key rotation period must be at least 86400 seconds (1 day)."
  }
}

variable "enable_vulnerability_scanning" {
  description = "Enable vulnerability scanning for container images"
  type        = bool
  default     = true
}