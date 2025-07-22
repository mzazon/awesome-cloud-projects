# Variables for GCP Compliance Violation Detection Terraform Configuration
# This file defines all configurable parameters for the compliance monitoring system

# Project and Location Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be deployed. If empty, uses the current project from gcloud configuration."
  type        = string
  default     = ""
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id)) || var.project_id == ""
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region where regional resources will be deployed. Choose a region close to your users for optimal performance."
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1, europe-west1)."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and configuration. Affects security settings and resource lifecycle policies."
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# Cloud Function Configuration
variable "function_max_instances" {
  description = "Maximum number of Cloud Function instances for auto-scaling. Higher values support more concurrent audit log processing but increase costs."
  type        = number
  default     = 100
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function max instances must be between 1 and 1000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of Cloud Function instances to keep warm. Setting to 0 reduces costs but may increase cold start latency for compliance detection."
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 100
    error_message = "Function min instances must be between 0 and 100."
  }
}

variable "function_timeout_seconds" {
  description = "Maximum execution time for Cloud Function in seconds. Increase for complex compliance rule processing or large audit log batches."
  type        = number
  default     = 540
  
  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB. Higher values improve performance for complex compliance analysis but increase costs."
  type        = string
  default     = "512Mi"
  
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
  }
}

# BigQuery Configuration
variable "dataset_owner_email" {
  description = "Email address of the BigQuery dataset owner. Required for setting up proper access controls on the compliance data warehouse."
  type        = string
  default     = ""
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.dataset_owner_email)) || var.dataset_owner_email == ""
    error_message = "Dataset owner email must be a valid email address."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain compliance violation logs in BigQuery. Longer retention supports historical analysis but increases storage costs."
  type        = number
  default     = 365
  
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 2555  # ~7 years max
    error_message = "Log retention must be between 30 and 2555 days."
  }
}

variable "bigquery_location" {
  description = "BigQuery dataset location. Can be a region or multi-region. For compliance, consider data residency requirements."
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "europe-west6", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid region or multi-region location."
  }
}

# Pub/Sub Configuration
variable "message_retention_duration" {
  description = "How long to retain unacknowledged Pub/Sub messages in seconds. Longer retention ensures no compliance alerts are lost during outages."
  type        = string
  default     = "1200s"  # 20 minutes
  
  validation {
    condition = can(regex("^[0-9]+s$", var.message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., '1200s')."
  }
}

variable "dead_letter_max_delivery_attempts" {
  description = "Maximum delivery attempts before sending messages to dead letter queue. Higher values increase reliability but may delay error detection."
  type        = number
  default     = 5
  
  validation {
    condition     = var.dead_letter_max_delivery_attempts >= 3 && var.dead_letter_max_delivery_attempts <= 100
    error_message = "Dead letter max delivery attempts must be between 3 and 100."
  }
}

# Compliance Rule Configuration
variable "enable_iam_monitoring" {
  description = "Enable monitoring of IAM policy changes and privilege escalations. Critical for security compliance frameworks."
  type        = bool
  default     = true
}

variable "enable_data_access_monitoring" {
  description = "Enable monitoring of data access patterns. Important for privacy compliance (GDPR, CCPA) but generates high volume of logs."
  type        = bool
  default     = false
}

variable "enable_admin_activity_monitoring" {
  description = "Enable monitoring of administrative activities like resource creation, deletion, and configuration changes."
  type        = bool
  default     = true
}

variable "high_severity_violation_types" {
  description = "List of violation types that trigger high-severity alerts. These should align with your organization's critical compliance requirements."
  type        = list(string)
  default = [
    "IAM_POLICY_CHANGE",
    "PRIVILEGE_ESCALATION",
    "UNAUTHORIZED_ACCESS",
    "DATA_EXFILTRATION"
  ]
  
  validation {
    condition     = length(var.high_severity_violation_types) > 0
    error_message = "At least one high severity violation type must be specified."
  }
}

# Monitoring and Alerting Configuration
variable "alert_notification_channels" {
  description = "List of Cloud Monitoring notification channel IDs for compliance alerts. Create these channels in the Cloud Console first."
  type        = list(string)
  default     = []
}

variable "enable_email_notifications" {
  description = "Enable email notifications for compliance violations. Requires setting up notification channels in Cloud Monitoring."
  type        = bool
  default     = false
}

variable "alert_auto_close_duration" {
  description = "Duration in seconds after which resolved alerts automatically close. Helps manage alert noise in monitoring systems."
  type        = string
  default     = "1800s"  # 30 minutes
  
  validation {
    condition = can(regex("^[0-9]+s$", var.alert_auto_close_duration))
    error_message = "Alert auto close duration must be in seconds format (e.g., '1800s')."
  }
}

variable "notification_rate_limit_period" {
  description = "Period in seconds to limit notification frequency. Prevents alert flooding during widespread compliance violations."
  type        = string
  default     = "300s"  # 5 minutes
  
  validation {
    condition = can(regex("^[0-9]+s$", var.notification_rate_limit_period))
    error_message = "Notification rate limit period must be in seconds format (e.g., '300s')."
  }
}

# Security and Access Control
variable "function_ingress_settings" {
  description = "Ingress settings for Cloud Function. ALLOW_INTERNAL_ONLY is recommended for security."
  type        = string
  default     = "ALLOW_INTERNAL_ONLY"
  
  validation {
    condition = contains([
      "ALLOW_ALL", "ALLOW_INTERNAL_ONLY", "ALLOW_INTERNAL_AND_GCLB"
    ], var.function_ingress_settings)
    error_message = "Function ingress settings must be one of: ALLOW_ALL, ALLOW_INTERNAL_ONLY, ALLOW_INTERNAL_AND_GCLB."
  }
}

variable "enable_vpc_connector" {
  description = "Enable VPC connector for Cloud Function. Required if accessing resources in a VPC network."
  type        = bool
  default     = false
}

variable "vpc_connector_name" {
  description = "Name of the VPC connector for Cloud Function. Only used if enable_vpc_connector is true."
  type        = string
  default     = ""
}

# Cost and Resource Optimization
variable "enable_log_exclusions" {
  description = "Enable log exclusions to reduce costs by filtering out low-value audit logs. Carefully review exclusion rules to avoid compliance gaps."
  type        = bool
  default     = false
}

variable "log_exclusion_filters" {
  description = "List of log exclusion filters to reduce logging costs. Use with caution to ensure compliance requirements are met."
  type        = list(string)
  default     = []
}

variable "enable_cold_start_optimization" {
  description = "Enable optimizations to reduce Cloud Function cold start times. May increase costs but improves compliance detection latency."
  type        = bool
  default     = false
}

# Custom Labels and Tagging
variable "additional_labels" {
  description = "Additional labels to apply to all resources for organization, billing, and governance purposes."
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens (max 63 chars)."
  }
}

# Advanced Configuration
variable "enable_custom_metrics" {
  description = "Enable creation of custom Cloud Monitoring metrics for advanced compliance analytics and dashboards."
  type        = bool
  default     = true
}

variable "enable_audit_log_sink" {
  description = "Enable audit log sink to BigQuery for long-term compliance analysis and reporting."
  type        = bool
  default     = true
}

variable "audit_log_filter" {
  description = "Custom filter for audit logs sent to BigQuery. Use to focus on specific services or activities relevant to your compliance requirements."
  type        = string
  default     = ""
}

variable "enable_dashboard" {
  description = "Enable creation of Cloud Monitoring dashboard for compliance metrics visualization."
  type        = bool
  default     = true
}

variable "dashboard_time_range" {
  description = "Default time range for dashboard widgets. Affects the initial view when opening the compliance dashboard."
  type        = string
  default     = "1h"
  
  validation {
    condition = contains(["1h", "6h", "12h", "1d", "7d", "30d"], var.dashboard_time_range)
    error_message = "Dashboard time range must be one of: 1h, 6h, 12h, 1d, 7d, 30d."
  }
}