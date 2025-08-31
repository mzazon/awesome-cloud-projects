# Variables for GCP Privilege Escalation Monitoring Infrastructure

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
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., us-central1-a)."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "privilege-monitor"
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with alphanumeric character."
  }
}

variable "enable_apis" {
  description = "Enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "required_apis" {
  description = "List of required Google Cloud APIs"
  type        = list(string)
  default = [
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
    "privilegedaccessmanager.googleapis.com"
  ]
}

# Pub/Sub Configuration
variable "pubsub_topic_name" {
  description = "Name for the Pub/Sub topic (will be prefixed with resource_prefix)"
  type        = string
  default     = "privilege-escalation-alerts"
}

variable "pubsub_subscription_name" {
  description = "Name for the Pub/Sub subscription (will be prefixed with resource_prefix)"
  type        = string
  default     = "privilege-monitor-sub"
}

variable "pubsub_ack_deadline_seconds" {
  description = "Acknowledgment deadline for Pub/Sub subscription in seconds"
  type        = number
  default     = 60
  validation {
    condition = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub subscription"
  type        = string
  default     = "604800s" # 7 days
}

# Cloud Function Configuration
variable "function_name" {
  description = "Name for the Cloud Function (will be prefixed with resource_prefix)"
  type        = string
  default     = "privilege-alert-processor"
}

variable "function_runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "python39"
  validation {
    condition = contains(["python39", "python310", "python311"], var.function_runtime)
    error_message = "Function runtime must be one of: python39, python310, python311."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 256
  validation {
    condition = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 60
  validation {
    condition = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Maximum instances must be between 1 and 3000."
  }
}

# Cloud Storage Configuration
variable "storage_bucket_name" {
  description = "Name for the Cloud Storage bucket (will be prefixed with project_id and resource_prefix)"
  type        = string
  default     = "privilege-audit-logs"
}

variable "storage_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
  validation {
    condition = contains(["US", "EU", "ASIA"], var.storage_location) || can(regex("^[a-z]+-[a-z]+[0-9]$", var.storage_location))
    error_message = "Storage location must be a valid multi-region (US, EU, ASIA) or region."
  }
}

variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the Cloud Storage bucket"
  type        = bool
  default     = true
}

# Log Sink Configuration
variable "log_sink_name" {
  description = "Name for the log sink (will be prefixed with resource_prefix)"
  type        = string
  default     = "privilege-escalation-sink"
}

variable "log_sink_filter" {
  description = "Filter for the log sink to capture privilege escalation events"
  type        = string
  default     = <<-EOT
    protoPayload.serviceName="iam.googleapis.com" OR
    protoPayload.serviceName="cloudresourcemanager.googleapis.com" OR
    protoPayload.serviceName="serviceusage.googleapis.com" OR
    protoPayload.serviceName="privilegedaccessmanager.googleapis.com" OR
    (protoPayload.methodName=~"setIamPolicy" OR
     protoPayload.methodName=~"CreateRole" OR
     protoPayload.methodName=~"UpdateRole" OR
     protoPayload.methodName=~"CreateServiceAccount" OR
     protoPayload.methodName=~"SetIamPolicy" OR
     protoPayload.methodName=~"createGrant" OR
     protoPayload.methodName=~"CreateGrant" OR
     protoPayload.methodName=~"searchEntitlements")
  EOT
}

# Monitoring Configuration
variable "enable_monitoring_alerts" {
  description = "Enable Cloud Monitoring alert policies"
  type        = bool
  default     = true
}

variable "alert_threshold_value" {
  description = "Threshold value for privilege escalation alerts"
  type        = number
  default     = 2
  validation {
    condition = var.alert_threshold_value > 0
    error_message = "Alert threshold value must be greater than 0."
  }
}

variable "alert_duration" {
  description = "Duration for alert threshold evaluation"
  type        = string
  default     = "300s"
  validation {
    condition = can(regex("^[0-9]+s$", var.alert_duration))
    error_message = "Alert duration must be in seconds format (e.g., 300s)."
  }
}

# Lifecycle Configuration
variable "coldline_age_days" {
  description = "Age in days after which objects are moved to COLDLINE storage class"
  type        = number
  default     = 30
  validation {
    condition = var.coldline_age_days > 0
    error_message = "Coldline age days must be greater than 0."
  }
}

variable "archive_age_days" {
  description = "Age in days after which objects are moved to ARCHIVE storage class"
  type        = number
  default     = 365
  validation {
    condition = var.archive_age_days > var.coldline_age_days
    error_message = "Archive age days must be greater than coldline age days."
  }
}

# IAM Configuration
variable "create_service_accounts" {
  description = "Create dedicated service accounts for resources"
  type        = bool
  default     = true
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "privilege-escalation-monitoring"
    managed-by  = "terraform"
    purpose     = "security-monitoring"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain the same characters."
  }
}