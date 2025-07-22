# Core Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The Google Cloud zone for resources"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "email-campaign"
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

# Cloud Storage Configuration
variable "bucket_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "bucket_storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "bucket_versioning_enabled" {
  description = "Enable versioning for Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age" {
  description = "Number of days after which to delete old versions of objects"
  type        = number
  default     = 30
}

# Cloud Functions Configuration
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python39"
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (MB)"
  type        = number
  default     = 512
  
  validation {
    condition     = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of instances for Cloud Functions"
  type        = number
  default     = 10
}

variable "function_min_instances" {
  description = "Minimum number of instances for Cloud Functions"
  type        = number
  default     = 0
}

# BigQuery Configuration
variable "bigquery_dataset_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "US"
}

variable "bigquery_table_deletion_protection" {
  description = "Enable deletion protection for BigQuery tables"
  type        = bool
  default     = true
}

variable "bigquery_default_table_expiration_ms" {
  description = "Default table expiration time in milliseconds"
  type        = number
  default     = null
}

# Cloud Scheduler Configuration
variable "scheduler_time_zone" {
  description = "Time zone for Cloud Scheduler jobs"
  type        = string
  default     = "America/New_York"
}

variable "scheduler_retry_config" {
  description = "Configuration for Cloud Scheduler retry policy"
  type = object({
    retry_count          = number
    max_retry_duration   = string
    min_backoff_duration = string
    max_backoff_duration = string
    max_doublings        = number
  })
  default = {
    retry_count          = 3
    max_retry_duration   = "300s"
    min_backoff_duration = "5s"
    max_backoff_duration = "3600s"
    max_doublings        = 5
  }
}

# Campaign Schedule Configuration
variable "daily_campaign_schedule" {
  description = "Cron schedule for daily campaign generation"
  type        = string
  default     = "0 8 * * *"
}

variable "weekly_newsletter_schedule" {
  description = "Cron schedule for weekly newsletter"
  type        = string
  default     = "0 10 * * 1"
}

variable "promotional_campaign_schedule" {
  description = "Cron schedule for promotional campaigns"
  type        = string
  default     = "0 14 * * 3,6"
}

# Gmail API Configuration
variable "gmail_scopes" {
  description = "OAuth scopes for Gmail API access"
  type        = list(string)
  default     = ["https://www.googleapis.com/auth/gmail.send"]
}

# Monitoring Configuration
variable "monitoring_enabled" {
  description = "Enable Cloud Monitoring for the email campaign system"
  type        = bool
  default     = true
}

variable "logging_retention_days" {
  description = "Number of days to retain logs in Cloud Logging"
  type        = number
  default     = 30
}

# Security Configuration
variable "service_account_roles" {
  description = "IAM roles to assign to the service account"
  type        = list(string)
  default = [
    "roles/cloudsql.client",
    "roles/bigquery.dataEditor",
    "roles/storage.objectAdmin",
    "roles/cloudfunctions.invoker",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ]
}

variable "enable_apis" {
  description = "List of APIs to enable for the project"
  type        = list(string)
  default = [
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "gmail.googleapis.com",
    "bigquery.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com"
  ]
}

# Resource Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "email-campaign-automation"
    managed_by  = "terraform"
    cost_center = "marketing"
  }
}

# Email Templates Configuration
variable "email_templates" {
  description = "Email template configurations"
  type = map(object({
    subject     = string
    description = string
  }))
  default = {
    product_announcement = {
      subject     = "Exciting New Product Updates!"
      description = "Template for product announcement emails"
    }
    promotional_offer = {
      subject     = "Special Offer Just for You!"
      description = "Template for promotional offer emails"
    }
    newsletter = {
      subject     = "Your Weekly Newsletter"
      description = "Template for weekly newsletter emails"
    }
  }
}

# Cost Management
variable "budget_amount" {
  description = "Monthly budget amount for the email campaign system (USD)"
  type        = number
  default     = 100
}

variable "budget_alert_thresholds" {
  description = "Budget alert thresholds as percentages"
  type        = list(number)
  default     = [50, 75, 90, 100]
}