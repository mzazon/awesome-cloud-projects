# ============================================================================
# Input Variables for Data Pipeline Recovery Infrastructure
# ============================================================================
#
# This file defines all configurable parameters for the data pipeline recovery
# solution. Variables are organized by functional area and include validation
# rules to ensure proper configuration.
#
# ============================================================================

# ============================================================================
# PROJECT AND LOCATION CONFIGURATION
# ============================================================================

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1, europe-west1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

# ============================================================================
# RESOURCE NAMING CONFIGURATION
# ============================================================================

variable "dataform_repository_name" {
  description = "Base name for the Dataform repository (suffix will be auto-generated)"
  type        = string
  default     = "pipeline-recovery-repo"
  
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{0,62}$", var.dataform_repository_name))
    error_message = "Dataform repository name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bigquery_dataset_name" {
  description = "Base name for BigQuery dataset (suffix will be auto-generated)"
  type        = string
  default     = "pipeline_monitoring"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,1023}$", var.bigquery_dataset_name))
    error_message = "BigQuery dataset name must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "task_queue_name" {
  description = "Base name for Cloud Tasks queue (suffix will be auto-generated)"
  type        = string
  default     = "pipeline-recovery-queue"
  
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{0,499}$", var.task_queue_name))
    error_message = "Task queue name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "controller_function_name" {
  description = "Base name for pipeline controller Cloud Function (suffix will be auto-generated)"
  type        = string
  default     = "pipeline-controller"
  
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{0,62}$", var.controller_function_name))
    error_message = "Function name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "worker_function_name" {
  description = "Base name for recovery worker Cloud Function (suffix will be auto-generated)"
  type        = string
  default     = "recovery-worker"
  
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{0,62}$", var.worker_function_name))
    error_message = "Function name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "notification_function_name" {
  description = "Base name for notification handler Cloud Function (suffix will be auto-generated)"
  type        = string
  default     = "notification-handler"
  
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{0,62}$", var.notification_function_name))
    error_message = "Function name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "pubsub_topic_name" {
  description = "Base name for Pub/Sub notification topic (suffix will be auto-generated)"
  type        = string
  default     = "pipeline-notifications"
  
  validation {
    condition     = can(regex("^[a-zA-Z][-._~%+a-zA-Z0-9]{2,254}$", var.pubsub_topic_name))
    error_message = "Pub/Sub topic name must be 3-255 characters and contain only letters, numbers, and specific symbols."
  }
}

# ============================================================================
# BIGQUERY CONFIGURATION
# ============================================================================

variable "bigquery_table_expiration_days" {
  description = "Number of days after which BigQuery tables will expire (0 = never expire)"
  type        = number
  default     = 90
  
  validation {
    condition     = var.bigquery_table_expiration_days >= 0 && var.bigquery_table_expiration_days <= 365
    error_message = "BigQuery table expiration must be between 0 and 365 days."
  }
}

# ============================================================================
# CLOUD TASKS CONFIGURATION
# ============================================================================

variable "task_queue_max_dispatches_per_second" {
  description = "Maximum rate at which tasks are dispatched from the queue per second"
  type        = number
  default     = 10
  
  validation {
    condition     = var.task_queue_max_dispatches_per_second >= 1 && var.task_queue_max_dispatches_per_second <= 500
    error_message = "Max dispatches per second must be between 1 and 500."
  }
}

variable "task_queue_max_concurrent_dispatches" {
  description = "Maximum number of concurrent tasks that can be dispatched"
  type        = number
  default     = 5
  
  validation {
    condition     = var.task_queue_max_concurrent_dispatches >= 1 && var.task_queue_max_concurrent_dispatches <= 1000
    error_message = "Max concurrent dispatches must be between 1 and 1000."
  }
}

variable "task_queue_max_attempts" {
  description = "Maximum number of retry attempts for failed tasks"
  type        = number
  default     = 5
  
  validation {
    condition     = var.task_queue_max_attempts >= 1 && var.task_queue_max_attempts <= 100
    error_message = "Max attempts must be between 1 and 100."
  }
}

variable "task_queue_max_retry_duration_hours" {
  description = "Maximum duration for retrying failed tasks (in hours)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.task_queue_max_retry_duration_hours >= 1 && var.task_queue_max_retry_duration_hours <= 24
    error_message = "Max retry duration must be between 1 and 24 hours."
  }
}

variable "task_queue_min_backoff_seconds" {
  description = "Minimum backoff time between task retry attempts (in seconds)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.task_queue_min_backoff_seconds >= 1 && var.task_queue_min_backoff_seconds <= 3600
    error_message = "Min backoff must be between 1 and 3600 seconds."
  }
}

variable "task_queue_max_backoff_seconds" {
  description = "Maximum backoff time between task retry attempts (in seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.task_queue_max_backoff_seconds >= 1 && var.task_queue_max_backoff_seconds <= 3600
    error_message = "Max backoff must be between 1 and 3600 seconds."
  }
}

variable "task_queue_max_doublings" {
  description = "Maximum number of times the retry interval can be doubled"
  type        = number
  default     = 3
  
  validation {
    condition     = var.task_queue_max_doublings >= 0 && var.task_queue_max_doublings <= 16
    error_message = "Max doublings must be between 0 and 16."
  }
}

variable "task_queue_logging_sampling_ratio" {
  description = "Fraction of operations to write to Cloud Logging (0.0 to 1.0)"
  type        = number
  default     = 0.1
  
  validation {
    condition     = var.task_queue_logging_sampling_ratio >= 0.0 && var.task_queue_logging_sampling_ratio <= 1.0
    error_message = "Logging sampling ratio must be between 0.0 and 1.0."
  }
}

# ============================================================================
# CLOUD FUNCTIONS CONFIGURATION
# ============================================================================

variable "function_max_instances" {
  description = "Maximum number of instances for Cloud Functions"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function max instances must be between 1 and 1000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of instances for Cloud Functions"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 100
    error_message = "Function min instances must be between 0 and 100."
  }
}

# ============================================================================
# MONITORING AND ALERTING CONFIGURATION
# ============================================================================

variable "enable_monitoring_alerts" {
  description = "Enable Cloud Monitoring alerts for pipeline failure detection"
  type        = bool
  default     = true
}

variable "notification_recipients" {
  description = "List of email addresses to receive pipeline recovery notifications"
  type        = list(string)
  default     = ["admin@company.com", "ops-team@company.com"]
  
  validation {
    condition = alltrue([
      for email in var.notification_recipients : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All notification recipients must be valid email addresses."
  }
}

# ============================================================================
# RESOURCE LABELING
# ============================================================================

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][-_a-z0-9]*$", k)) && length(k) <= 63
    ])
    error_message = "Label keys must start with lowercase letter, contain only lowercase letters, numbers, hyphens, and underscores, and be <= 63 characters."
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : length(v) <= 63
    ])
    error_message = "Label values must be <= 63 characters."
  }
}

# ============================================================================
# SECURITY CONFIGURATION
# ============================================================================

variable "enable_private_google_access" {
  description = "Enable Private Google Access for Cloud Functions"
  type        = bool
  default     = true
}

variable "enable_vpc_connector" {
  description = "Enable VPC Connector for Cloud Functions (requires VPC network)"
  type        = bool
  default     = false
}

variable "vpc_connector_name" {
  description = "Name of existing VPC Connector (required if enable_vpc_connector is true)"
  type        = string
  default     = ""
}

# ============================================================================
# COST OPTIMIZATION CONFIGURATION
# ============================================================================

variable "enable_function_source_bucket_lifecycle" {
  description = "Enable lifecycle management for Cloud Function source bucket"
  type        = bool
  default     = true
}

variable "function_source_retention_days" {
  description = "Number of days to retain Cloud Function source code in bucket"
  type        = number
  default     = 30
  
  validation {
    condition     = var.function_source_retention_days >= 1 && var.function_source_retention_days <= 365
    error_message = "Function source retention must be between 1 and 365 days."
  }
}

# ============================================================================
# ADVANCED CONFIGURATION
# ============================================================================

variable "enable_enhanced_logging" {
  description = "Enable enhanced logging for detailed debugging and monitoring"
  type        = bool
  default     = false
}

variable "custom_domain" {
  description = "Custom domain for webhook endpoints (optional)"
  type        = string
  default     = ""
}

variable "backup_region" {
  description = "Backup region for multi-region disaster recovery (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.backup_region == "" || can(regex("^[a-z]+-[a-z]+[0-9]$", var.backup_region))
    error_message = "Backup region must be empty or a valid Google Cloud region format."
  }
}