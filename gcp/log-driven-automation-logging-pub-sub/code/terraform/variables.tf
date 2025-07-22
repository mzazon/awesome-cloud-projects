# Variables for log-driven automation infrastructure

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
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

variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "log-automation"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

# Pub/Sub Configuration
variable "topic_name" {
  description = "Name of the Pub/Sub topic for incident automation"
  type        = string
  default     = "incident-automation"
}

variable "alert_subscription_name" {
  description = "Name of the Pub/Sub subscription for alerts"
  type        = string
  default     = "alert-subscription"
}

variable "remediation_subscription_name" {
  description = "Name of the Pub/Sub subscription for remediation"
  type        = string
  default     = "remediation-subscription"
}

variable "message_retention_duration" {
  description = "Message retention duration for Pub/Sub subscriptions"
  type        = string
  default     = "604800s" # 7 days
}

variable "ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscriptions in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.ack_deadline_seconds >= 10 && var.ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

variable "remediation_ack_deadline_seconds" {
  description = "Acknowledgment deadline for remediation subscription in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.remediation_ack_deadline_seconds >= 10 && var.remediation_ack_deadline_seconds <= 600
    error_message = "Remediation acknowledgment deadline must be between 10 and 600 seconds."
  }
}

# Cloud Logging Configuration
variable "log_sink_name" {
  description = "Name of the log sink for forwarding logs to Pub/Sub"
  type        = string
  default     = "automation-sink"
}

variable "log_filter" {
  description = "Log filter for capturing error logs"
  type        = string
  default     = "severity>=ERROR OR jsonPayload.level=\"ERROR\" OR textPayload:\"Exception\""
}

# Cloud Functions Configuration
variable "alert_function_name" {
  description = "Name of the alert processing Cloud Function"
  type        = string
  default     = "alert-processor"
}

variable "remediation_function_name" {
  description = "Name of the auto-remediation Cloud Function"
  type        = string
  default     = "auto-remediate"
}

variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "nodejs20"
  validation {
    condition = contains([
      "nodejs18", "nodejs20", "python39", "python310", "python311",
      "go116", "go119", "go120", "go121", "java11", "java17", "java21"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

variable "alert_function_memory" {
  description = "Memory allocation for alert processing function in MB"
  type        = number
  default     = 256
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.alert_function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "remediation_function_memory" {
  description = "Memory allocation for remediation function in MB"
  type        = number
  default     = 512
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.remediation_function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "remediation_function_timeout_seconds" {
  description = "Timeout for remediation function in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.remediation_function_timeout_seconds >= 1 && var.remediation_function_timeout_seconds <= 540
    error_message = "Remediation function timeout must be between 1 and 540 seconds."
  }
}

# Cloud Monitoring Configuration
variable "create_alerting_policies" {
  description = "Whether to create Cloud Monitoring alerting policies"
  type        = bool
  default     = true
}

variable "error_rate_threshold" {
  description = "Error rate threshold for alerting"
  type        = number
  default     = 10.0
}

variable "latency_threshold_ms" {
  description = "Latency threshold in milliseconds for alerting"
  type        = number
  default     = 5000.0
}

variable "alert_auto_close_duration" {
  description = "Duration after which alerts auto-close"
  type        = string
  default     = "1800s" # 30 minutes
}

# External Integration Configuration
variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "notification_email" {
  description = "Email address for notifications (optional)"
  type        = string
  default     = ""
}

# IAM Configuration
variable "create_service_accounts" {
  description = "Whether to create dedicated service accounts for functions"
  type        = bool
  default     = true
}

# Resource Labeling
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    "component"    = "log-automation"
    "managed-by"   = "terraform"
    "architecture" = "event-driven"
  }
}

# Log-based Metrics Configuration
variable "create_log_metrics" {
  description = "Whether to create log-based metrics"
  type        = bool
  default     = true
}

variable "error_rate_metric_name" {
  description = "Name of the error rate log-based metric"
  type        = string
  default     = "error_rate_metric"
}

variable "exception_pattern_metric_name" {
  description = "Name of the exception pattern log-based metric"
  type        = string
  default     = "exception_pattern_metric"
}

variable "latency_anomaly_metric_name" {
  description = "Name of the latency anomaly log-based metric"
  type        = string
  default     = "latency_anomaly_metric"
}

# Networking Configuration
variable "vpc_connector_name" {
  description = "Name of the VPC connector for Cloud Functions (if needed)"
  type        = string
  default     = ""
}

variable "enable_vpc_connector" {
  description = "Whether to create and use a VPC connector for Cloud Functions"
  type        = bool
  default     = false
}