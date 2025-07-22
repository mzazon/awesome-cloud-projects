# Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "healthcare-compliance"
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

# Healthcare API Configuration
variable "healthcare_dataset_location" {
  description = "Location for Healthcare API dataset"
  type        = string
  default     = "us-central1"
}

variable "fhir_version" {
  description = "FHIR version for the FHIR store"
  type        = string
  default     = "R4"
  
  validation {
    condition     = contains(["DSTU2", "STU3", "R4"], var.fhir_version)
    error_message = "FHIR version must be one of: DSTU2, STU3, R4."
  }
}

variable "enable_update_create" {
  description = "Whether to enable update_create for FHIR store"
  type        = bool
  default     = true
}

variable "disable_referential_integrity" {
  description = "Whether to disable referential integrity for FHIR store"
  type        = bool
  default     = true
}

# Cloud Tasks Configuration
variable "task_queue_max_dispatches_per_second" {
  description = "Maximum dispatches per second for Cloud Tasks queue"
  type        = number
  default     = 10
}

variable "task_queue_max_concurrent_dispatches" {
  description = "Maximum concurrent dispatches for Cloud Tasks queue"
  type        = number
  default     = 5
}

variable "task_queue_max_attempts" {
  description = "Maximum retry attempts for Cloud Tasks"
  type        = number
  default     = 3
}

variable "task_queue_min_backoff" {
  description = "Minimum backoff duration for Cloud Tasks retries"
  type        = string
  default     = "1s"
}

variable "task_queue_max_backoff" {
  description = "Maximum backoff duration for Cloud Tasks retries"
  type        = string
  default     = "300s"
}

# Cloud Functions Configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python39"
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = number
  default     = 512
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 540
}

variable "function_max_instances" {
  description = "Maximum instances for Cloud Functions"
  type        = number
  default     = 10
}

# Storage Configuration
variable "storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "storage_lifecycle_age_nearline" {
  description = "Age in days to transition to NEARLINE storage class"
  type        = number
  default     = 30
}

variable "storage_lifecycle_age_coldline" {
  description = "Age in days to transition to COLDLINE storage class"
  type        = number
  default     = 365
}

# Pub/Sub Configuration
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub subscription"
  type        = string
  default     = "604800s" # 7 days
}

variable "pubsub_ack_deadline" {
  description = "Acknowledgment deadline for Pub/Sub subscription"
  type        = string
  default     = "600s" # 10 minutes
}

# BigQuery Configuration
variable "bigquery_dataset_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "us-central1"
}

variable "bigquery_dataset_description" {
  description = "Description for BigQuery dataset"
  type        = string
  default     = "Healthcare compliance analytics dataset"
}

variable "bigquery_table_deletion_protection" {
  description = "Whether to enable deletion protection for BigQuery tables"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_monitoring_alerts" {
  description = "Whether to enable monitoring alerts"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for compliance notifications"
  type        = string
  default     = "compliance@example.com"
}

variable "alert_threshold_value" {
  description = "Threshold value for high-risk event alerts"
  type        = number
  default     = 3
}

variable "alert_duration" {
  description = "Duration for alert conditions"
  type        = string
  default     = "60s"
}

# Labels and Tags
variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    managed_by    = "terraform"
    project_type  = "healthcare-compliance"
    compliance    = "hipaa"
  }
}

# Security Configuration
variable "enable_uniform_bucket_level_access" {
  description = "Whether to enable uniform bucket-level access"
  type        = bool
  default     = true
}

variable "enable_audit_logging" {
  description = "Whether to enable audit logging"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Whether to enable encryption for sensitive resources"
  type        = bool
  default     = true
}