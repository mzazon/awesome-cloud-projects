# Variables for AI Model Bias Detection Infrastructure

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.region))
    error_message = "Region must be a valid Google Cloud region name."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and identification"
  type        = string
  default     = "development"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (random suffix will be added)"
  type        = string
  default     = "bias-detection-reports"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for model monitoring alerts"
  type        = string
  default     = "model-monitoring-alerts"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-_]+$", var.pubsub_topic_name))
    error_message = "Pub/Sub topic name must start with a letter and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "bias_detection_function_name" {
  description = "Name of the bias detection Cloud Function"
  type        = string
  default     = "bias-detection-processor"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.bias_detection_function_name))
    error_message = "Function name must start with a lowercase letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "alert_processing_function_name" {
  description = "Name of the alert processing Cloud Function"
  type        = string
  default     = "bias-alert-handler"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.alert_processing_function_name))
    error_message = "Function name must start with a lowercase letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "audit_function_name" {
  description = "Name of the audit report generation Cloud Function"
  type        = string
  default     = "bias-report-generator"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.audit_function_name))
    error_message = "Function name must start with a lowercase letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for bias audits"
  type        = string
  default     = "bias-audit-scheduler"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.scheduler_job_name))
    error_message = "Scheduler job name must start with a lowercase letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bias_thresholds" {
  description = "Thresholds for bias detection metrics"
  type = object({
    demographic_parity_threshold = number
    equalized_odds_threshold     = number
    calibration_threshold        = number
    overall_bias_threshold       = number
  })
  default = {
    demographic_parity_threshold = 0.1
    equalized_odds_threshold     = 0.1
    calibration_threshold        = 0.05
    overall_bias_threshold       = 0.1
  }
  validation {
    condition = alltrue([
      var.bias_thresholds.demographic_parity_threshold >= 0 && var.bias_thresholds.demographic_parity_threshold <= 1,
      var.bias_thresholds.equalized_odds_threshold >= 0 && var.bias_thresholds.equalized_odds_threshold <= 1,
      var.bias_thresholds.calibration_threshold >= 0 && var.bias_thresholds.calibration_threshold <= 1,
      var.bias_thresholds.overall_bias_threshold >= 0 && var.bias_thresholds.overall_bias_threshold <= 1
    ])
    error_message = "All bias thresholds must be between 0 and 1."
  }
}

variable "audit_schedule" {
  description = "Cron schedule for bias audit execution (default: weekly on Monday at 9 AM EST)"
  type        = string
  default     = "0 9 * * 1"
  validation {
    condition     = can(regex("^[0-9\\*\\-\\,\\/]+\\s+[0-9\\*\\-\\,\\/]+\\s+[0-9\\*\\-\\,\\/]+\\s+[0-9\\*\\-\\,\\/]+\\s+[0-9\\*\\-\\,\\/]+$", var.audit_schedule))
    error_message = "Audit schedule must be a valid cron expression."
  }
}

variable "audit_timezone" {
  description = "Timezone for audit schedule execution"
  type        = string
  default     = "America/New_York"
  validation {
    condition     = length(var.audit_timezone) > 0
    error_message = "Audit timezone cannot be empty."
  }
}

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions in MB"
  type = object({
    bias_detection    = string
    alert_processing  = string
    audit_generation  = string
  })
  default = {
    bias_detection   = "512Mi"
    alert_processing = "256Mi"
    audit_generation = "512Mi"
  }
  validation {
    condition = alltrue([
      contains(["128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"], var.function_memory_mb.bias_detection),
      contains(["128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"], var.function_memory_mb.alert_processing),
      contains(["128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"], var.function_memory_mb.audit_generation)
    ])
    error_message = "Function memory must be one of: 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Functions in seconds"
  type = object({
    bias_detection   = number
    alert_processing = number
    audit_generation = number
  })
  default = {
    bias_detection   = 300
    alert_processing = 120
    audit_generation = 600
  }
  validation {
    condition = alltrue([
      var.function_timeout_seconds.bias_detection >= 60 && var.function_timeout_seconds.bias_detection <= 3600,
      var.function_timeout_seconds.alert_processing >= 60 && var.function_timeout_seconds.alert_processing <= 3600,
      var.function_timeout_seconds.audit_generation >= 60 && var.function_timeout_seconds.audit_generation <= 3600
    ])
    error_message = "Function timeout must be between 60 and 3600 seconds."
  }
}

variable "max_function_instances" {
  description = "Maximum number of function instances for auto-scaling"
  type = object({
    bias_detection   = number
    alert_processing = number
    audit_generation = number
  })
  default = {
    bias_detection   = 100
    alert_processing = 50
    audit_generation = 10
  }
  validation {
    condition = alltrue([
      var.max_function_instances.bias_detection >= 1 && var.max_function_instances.bias_detection <= 1000,
      var.max_function_instances.alert_processing >= 1 && var.max_function_instances.alert_processing <= 1000,
      var.max_function_instances.audit_generation >= 1 && var.max_function_instances.audit_generation <= 1000
    ])
    error_message = "Maximum function instances must be between 1 and 1000."
  }
}

variable "pubsub_message_retention_seconds" {
  description = "Message retention duration for Pub/Sub topics in seconds"
  type        = number
  default     = 604800 # 7 days
  validation {
    condition     = var.pubsub_message_retention_seconds >= 600 && var.pubsub_message_retention_seconds <= 2678400
    error_message = "Pub/Sub message retention must be between 600 seconds (10 minutes) and 2678400 seconds (31 days)."
  }
}

variable "storage_lifecycle_rules" {
  description = "Lifecycle rules for Cloud Storage bucket"
  type = object({
    nearline_days  = number
    coldline_days  = number
    delete_days    = number
  })
  default = {
    nearline_days = 90
    coldline_days = 365
    delete_days   = 2555 # 7 years for compliance
  }
  validation {
    condition = alltrue([
      var.storage_lifecycle_rules.nearline_days > 0,
      var.storage_lifecycle_rules.coldline_days > var.storage_lifecycle_rules.nearline_days,
      var.storage_lifecycle_rules.delete_days > var.storage_lifecycle_rules.coldline_days
    ])
    error_message = "Storage lifecycle rules must be in ascending order: nearline < coldline < delete."
  }
}

variable "enable_bigquery_export" {
  description = "Enable BigQuery export for bias detection logs"
  type        = bool
  default     = true
}

variable "bigquery_dataset_location" {
  description = "Location for BigQuery dataset (for logs export)"
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU", "us-central1", "europe-west1", "asia-east1"], var.bigquery_dataset_location)
    error_message = "BigQuery dataset location must be a valid location."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain bias detection logs in BigQuery"
  type        = number
  default     = 365
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 3650
    error_message = "Log retention must be between 30 days and 10 years (3650 days)."
  }
}

variable "notification_channels" {
  description = "List of notification channels for monitoring alerts"
  type        = list(string)
  default     = []
}

variable "enable_vpc_connector" {
  description = "Enable VPC connector for Cloud Functions (for enhanced security)"
  type        = bool
  default     = false
}

variable "vpc_connector_name" {
  description = "Name of the VPC connector (if enabled)"
  type        = string
  default     = ""
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k))
    ])
    error_message = "Label keys must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "enable_monitoring_alerts" {
  description = "Enable Cloud Monitoring alerts for bias detection"
  type        = bool
  default     = true
}

variable "alert_severity_thresholds" {
  description = "Thresholds for alert severity classification"
  type = object({
    low_threshold      = number
    medium_threshold   = number
    high_threshold     = number
    critical_threshold = number
  })
  default = {
    low_threshold      = 0.01
    medium_threshold   = 0.05
    high_threshold     = 0.1
    critical_threshold = 0.15
  }
  validation {
    condition = alltrue([
      var.alert_severity_thresholds.low_threshold >= 0,
      var.alert_severity_thresholds.medium_threshold > var.alert_severity_thresholds.low_threshold,
      var.alert_severity_thresholds.high_threshold > var.alert_severity_thresholds.medium_threshold,
      var.alert_severity_thresholds.critical_threshold > var.alert_severity_thresholds.high_threshold,
      var.alert_severity_thresholds.critical_threshold <= 1
    ])
    error_message = "Alert severity thresholds must be in ascending order and between 0 and 1."
  }
}

variable "enable_audit_trail" {
  description = "Enable comprehensive audit trail for compliance"
  type        = bool
  default     = true
}

variable "compliance_reporting_frequency" {
  description = "Frequency for automated compliance reporting"
  type        = string
  default     = "weekly"
  validation {
    condition     = contains(["daily", "weekly", "monthly"], var.compliance_reporting_frequency)
    error_message = "Compliance reporting frequency must be one of: daily, weekly, monthly."
  }
}

variable "data_residency_region" {
  description = "Region for data residency compliance (should match region variable)"
  type        = string
  default     = ""
}

variable "encryption_key_name" {
  description = "Customer-managed encryption key for additional security (optional)"
  type        = string
  default     = ""
}

variable "enable_private_google_access" {
  description = "Enable private Google access for enhanced security"
  type        = bool
  default     = true
}