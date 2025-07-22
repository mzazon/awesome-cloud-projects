# Project and region configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must be specified."
  }
}

variable "region" {
  description = "The Google Cloud region where resources will be created"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone where zonal resources will be created"
  type        = string
  default     = "us-central1-a"
}

variable "organization_id" {
  description = "The Google Cloud organization ID for Security Command Center"
  type        = string
  default     = ""
}

# Naming and resource configuration
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "security-compliance"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
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

# Pub/Sub configuration
variable "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for security findings"
  type        = string
  default     = ""
}

variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topic"
  type        = string
  default     = "86400s" # 1 day
}

# Cloud Functions configuration
variable "function_name" {
  description = "Name of the Cloud Function for processing security findings"
  type        = string
  default     = ""
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "512M"
  validation {
    condition = contains([
      "128M", "256M", "512M", "1024M", "2048M", "4096M", "8192M"
    ], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python311", "python312", "nodejs18", "nodejs20", "go121", "java17"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

# Cloud Workflows configuration
variable "workflow_names" {
  description = "Names of the security workflows"
  type = object({
    high_severity   = string
    medium_severity = string
    low_severity    = string
  })
  default = {
    high_severity   = ""
    medium_severity = ""
    low_severity    = ""
  }
}

# Security Command Center configuration
variable "scc_notification_name" {
  description = "Name of the Security Command Center notification configuration"
  type        = string
  default     = ""
}

variable "scc_notification_filter" {
  description = "Filter for Security Command Center notifications"
  type        = string
  default     = "state=\"ACTIVE\""
}

# Monitoring configuration
variable "enable_monitoring" {
  description = "Enable monitoring and alerting"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for security notifications"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "alert_threshold_high_severity" {
  description = "Threshold for high severity findings alert"
  type        = number
  default     = 5
  validation {
    condition     = var.alert_threshold_high_severity > 0
    error_message = "Alert threshold must be greater than 0."
  }
}

# Resource labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "security-compliance"
    managed-by  = "terraform"
    environment = "dev"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Service account configuration
variable "create_service_accounts" {
  description = "Whether to create service accounts for the security system"
  type        = bool
  default     = true
}

variable "service_account_names" {
  description = "Names of service accounts to create"
  type = object({
    function_sa = string
    workflow_sa = string
  })
  default = {
    function_sa = ""
    workflow_sa = ""
  }
}

# API enablement
variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "required_apis" {
  description = "List of required Google Cloud APIs"
  type        = list(string)
  default = [
    "securitycenter.googleapis.com",
    "pubsub.googleapis.com",
    "workflows.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

# Dashboard configuration
variable "create_dashboard" {
  description = "Whether to create a compliance monitoring dashboard"
  type        = bool
  default     = true
}

variable "dashboard_name" {
  description = "Name of the compliance monitoring dashboard"
  type        = string
  default     = ""
}