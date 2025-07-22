# Variables for GCP data privacy compliance infrastructure
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
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
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "privacy-compliance"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "notification_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address format."
  }
}

variable "dlp_scan_schedule" {
  description = "Cron schedule for DLP scans (UTC timezone)"
  type        = string
  default     = "0 2 * * *" # Daily at 2 AM UTC
}

variable "dlp_min_likelihood" {
  description = "Minimum likelihood threshold for DLP findings"
  type        = string
  default     = "POSSIBLE"
  validation {
    condition = contains([
      "VERY_UNLIKELY", "UNLIKELY", "POSSIBLE", "LIKELY", "VERY_LIKELY"
    ], var.dlp_min_likelihood)
    error_message = "DLP minimum likelihood must be one of: VERY_UNLIKELY, UNLIKELY, POSSIBLE, LIKELY, VERY_LIKELY."
  }
}

variable "dlp_max_findings_per_request" {
  description = "Maximum number of DLP findings per scan request"
  type        = number
  default     = 100
  validation {
    condition     = var.dlp_max_findings_per_request > 0 && var.dlp_max_findings_per_request <= 3000
    error_message = "DLP max findings per request must be between 1 and 3000."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function (e.g., 256Mi, 512Mi, 1Gi)"
  type        = string
  default     = "512Mi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi", "16Gi", "32Gi"
    ], var.function_memory)
    error_message = "Function memory must be a valid Cloud Function memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function execution in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout > 0 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

variable "pubsub_message_retention_duration" {
  description = "Duration to retain Pub/Sub messages (in seconds)"
  type        = string
  default     = "604800s" # 7 days
}

variable "pubsub_ack_deadline" {
  description = "Acknowledgment deadline for Pub/Sub subscriptions in seconds"
  type        = number
  default     = 600
  validation {
    condition     = var.pubsub_ack_deadline >= 10 && var.pubsub_ack_deadline <= 600
    error_message = "Pub/Sub acknowledgment deadline must be between 10 and 600 seconds."
  }
}

variable "storage_lifecycle_age_days" {
  description = "Number of days after which to delete objects in Cloud Storage"
  type        = number
  default     = 90
  validation {
    condition     = var.storage_lifecycle_age_days > 0
    error_message = "Storage lifecycle age must be greater than 0 days."
  }
}

variable "monitoring_alert_threshold" {
  description = "Threshold for high-severity DLP findings alert"
  type        = number
  default     = 5
  validation {
    condition     = var.monitoring_alert_threshold > 0
    error_message = "Monitoring alert threshold must be greater than 0."
  }
}

variable "enable_security_command_center" {
  description = "Whether to enable Security Command Center integration"
  type        = bool
  default     = true
}

variable "enable_monitoring_alerts" {
  description = "Whether to enable monitoring alerts"
  type        = bool
  default     = true
}

variable "enable_audit_logging" {
  description = "Whether to enable audit logging for DLP operations"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to be applied to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "data-privacy-compliance"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "sensitive_info_types" {
  description = "List of sensitive information types to detect with DLP"
  type        = list(string)
  default = [
    "US_SOCIAL_SECURITY_NUMBER",
    "CREDIT_CARD_NUMBER",
    "EMAIL_ADDRESS",
    "PHONE_NUMBER",
    "PERSON_NAME",
    "US_HEALTHCARE_NPI",
    "DATE_OF_BIRTH"
  ]
}