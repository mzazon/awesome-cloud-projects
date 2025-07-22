# Core project configuration
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
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid GCP region (e.g., us-central1, europe-west1)."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone (e.g., us-central1-a, europe-west1-b)."
  }
}

# Resource naming configuration
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "datastore-sync"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Pub/Sub configuration
variable "pubsub_topic_name" {
  description = "Name of the main Pub/Sub topic for data synchronization events"
  type        = string
  default     = "data-sync-events"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-_.~+%]*$", var.pubsub_topic_name))
    error_message = "Topic name must start with a letter and contain only letters, numbers, and the characters -_.~+%."
  }
}

variable "sync_subscription_name" {
  description = "Name of the subscription for data synchronization processing"
  type        = string
  default     = "sync-processor"
}

variable "audit_subscription_name" {
  description = "Name of the subscription for audit logging"
  type        = string
  default     = "audit-logger"
}

variable "dlq_topic_name" {
  description = "Name of the dead letter queue topic"
  type        = string
  default     = "sync-dead-letters"
}

variable "message_retention_duration" {
  description = "Message retention duration for subscriptions"
  type        = string
  default     = "604800s" # 7 days
  validation {
    condition     = can(regex("^[0-9]+s$", var.message_retention_duration))
    error_message = "Message retention duration must be specified in seconds (e.g., 604800s for 7 days)."
  }
}

variable "audit_retention_duration" {
  description = "Message retention duration for audit subscription"
  type        = string
  default     = "1209600s" # 14 days
}

variable "dlq_retention_duration" {
  description = "Message retention duration for dead letter queue"
  type        = string
  default     = "2592000s" # 30 days
}

variable "ack_deadline_seconds" {
  description = "Acknowledgment deadline for sync subscription in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.ack_deadline_seconds >= 10 && var.ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

variable "audit_ack_deadline_seconds" {
  description = "Acknowledgment deadline for audit subscription in seconds"
  type        = number
  default     = 30
}

variable "max_delivery_attempts" {
  description = "Maximum delivery attempts before sending to dead letter queue"
  type        = number
  default     = 5
  validation {
    condition     = var.max_delivery_attempts >= 1 && var.max_delivery_attempts <= 100
    error_message = "Maximum delivery attempts must be between 1 and 100."
  }
}

# Cloud Functions configuration
variable "sync_function_name" {
  description = "Name of the data synchronization Cloud Function"
  type        = string
  default     = "data-sync-processor"
}

variable "audit_function_name" {
  description = "Name of the audit logging Cloud Function"
  type        = string
  default     = "audit-logger"
}

variable "conflict_function_name" {
  description = "Name of the conflict resolution Cloud Function"
  type        = string
  default     = "conflict-resolver"
}

variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python39"
  validation {
    condition     = contains(["python39", "python310", "python311"], var.function_runtime)
    error_message = "Function runtime must be one of: python39, python310, python311."
  }
}

variable "sync_function_memory" {
  description = "Memory allocation for sync function in MB"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.sync_function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "audit_function_memory" {
  description = "Memory allocation for audit function in MB"
  type        = number
  default     = 128
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "audit_function_timeout" {
  description = "Timeout for audit function in seconds"
  type        = number
  default     = 30
}

variable "max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 1000
    error_message = "Maximum instances must be between 1 and 1000."
  }
}

variable "audit_max_instances" {
  description = "Maximum number of audit function instances"
  type        = number
  default     = 5
}

# Datastore configuration
variable "datastore_location" {
  description = "Location for Cloud Datastore (must be compatible with project region)"
  type        = string
  default     = "us-central"
  validation {
    condition = contains([
      "us-central", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1",
      "europe-central2", "europe-north1", "europe-west1", "europe-west2", "europe-west3",
      "europe-west4", "europe-west6", "northamerica-northeast1", "southamerica-east1"
    ], var.datastore_location)
    error_message = "Datastore location must be a valid multi-region or region location."
  }
}

# IAM and Security configuration
variable "enable_audit_logging" {
  description = "Enable comprehensive audit logging for all resources"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for all resources"
  type        = bool
  default     = true
}

variable "function_service_account_email" {
  description = "Email of existing service account for Cloud Functions (if not provided, will create new one)"
  type        = string
  default     = null
}

# Monitoring configuration
variable "create_monitoring_dashboard" {
  description = "Create a monitoring dashboard for the sync system"
  type        = bool
  default     = true
}

variable "dashboard_display_name" {
  description = "Display name for the monitoring dashboard"
  type        = string
  default     = "Datastore Sync Monitoring"
}

# Notification configuration
variable "notification_email" {
  description = "Email address for alerting notifications (optional)"
  type        = string
  default     = null
  validation {
    condition     = var.notification_email == null || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

# Resource labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "event-driven-sync"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens. Keys must start with a letter."
  }
}

# Feature flags
variable "enable_dead_letter_queue" {
  description = "Enable dead letter queue for failed message processing"
  type        = bool
  default     = true
}

variable "enable_external_sync" {
  description = "Enable external system synchronization topics"
  type        = bool
  default     = false
}

variable "enable_conflict_resolution" {
  description = "Enable advanced conflict resolution function"
  type        = bool
  default     = true
}