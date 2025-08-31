# Project and region configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must be provided and cannot be empty."
  }
}

variable "region" {
  description = "The GCP region for resources"
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
  description = "The GCP zone for resources"
  type        = string
  default     = "us-central1-a"
}

# Cloud SQL configuration
variable "sql_instance_name" {
  description = "Name for the Cloud SQL PostgreSQL instance"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.sql_instance_name)) || var.sql_instance_name == ""
    error_message = "SQL instance name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "sql_database_version" {
  description = "PostgreSQL version for Cloud SQL instance"
  type        = string
  default     = "POSTGRES_15"
  validation {
    condition = contains([
      "POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16"
    ], var.sql_database_version)
    error_message = "Database version must be a supported PostgreSQL version."
  }
}

variable "sql_tier" {
  description = "Machine type for Cloud SQL instance"
  type        = string
  default     = "db-custom-2-7680"
  validation {
    condition     = can(regex("^db-(custom|standard|highmem)-.+", var.sql_tier))
    error_message = "SQL tier must be a valid Cloud SQL machine type."
  }
}

variable "sql_disk_size" {
  description = "Disk size for Cloud SQL instance in GB"
  type        = number
  default     = 20
  validation {
    condition     = var.sql_disk_size >= 10 && var.sql_disk_size <= 65536
    error_message = "Disk size must be between 10 and 65536 GB."
  }
}

variable "sql_edition" {
  description = "Cloud SQL edition (ENTERPRISE required for Query Insights)"
  type        = string
  default     = "ENTERPRISE"
  validation {
    condition = contains([
      "ENTERPRISE", "ENTERPRISE_PLUS"
    ], var.sql_edition)
    error_message = "SQL edition must be ENTERPRISE or ENTERPRISE_PLUS for Query Insights."
  }
}

# Database configuration
variable "database_name" {
  description = "Name of the database to create for performance testing"
  type        = string
  default     = "performance_test"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.database_name))
    error_message = "Database name must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "db_root_password" {
  description = "Password for the postgres root user"
  type        = string
  default     = "SecurePassword123!"
  sensitive   = true
  validation {
    condition     = length(var.db_root_password) >= 8
    error_message = "Root password must be at least 8 characters long."
  }
}

variable "db_monitor_password" {
  description = "Password for the monitor user"
  type        = string
  default     = "MonitorPass456!"
  sensitive   = true
  validation {
    condition     = length(var.db_monitor_password) >= 8
    error_message = "Monitor password must be at least 8 characters long."
  }
}

# Cloud Function configuration
variable "function_name" {
  description = "Name for the Cloud Function that processes alerts"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.function_name)) || var.function_name == ""
    error_message = "Function name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 256
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

# Monitoring configuration
variable "alert_policy_name" {
  description = "Name for the Cloud Monitoring alert policy"
  type        = string
  default     = ""
}

variable "query_threshold_seconds" {
  description = "Query execution time threshold in seconds to trigger alerts"
  type        = number
  default     = 5.0
  validation {
    condition     = var.query_threshold_seconds > 0 && var.query_threshold_seconds <= 3600
    error_message = "Query threshold must be between 0 and 3600 seconds."
  }
}

variable "alert_auto_close_duration" {
  description = "Duration after which alerts auto-close if not resolved"
  type        = string
  default     = "1800s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.alert_auto_close_duration))
    error_message = "Alert auto-close duration must be in seconds format (e.g., '1800s')."
  }
}

# Sample data configuration
variable "enable_sample_data" {
  description = "Whether to create sample data for testing"
  type        = bool
  default     = true
}

variable "sample_users_count" {
  description = "Number of sample users to create"
  type        = number
  default     = 10000
  validation {
    condition     = var.sample_users_count >= 100 && var.sample_users_count <= 100000
    error_message = "Sample users count must be between 100 and 100,000."
  }
}

variable "sample_orders_count" {
  description = "Number of sample orders to create"
  type        = number
  default     = 50000
  validation {
    condition     = var.sample_orders_count >= 1000 && var.sample_orders_count <= 1000000
    error_message = "Sample orders count must be between 1,000 and 1,000,000."
  }
}

# Resource naming
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "sql-alerts"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,20}[a-z0-9])?$", var.resource_prefix))
    error_message = "Resource prefix must be lowercase, start with a letter, max 22 chars, and contain only letters, numbers, and hyphens."
  }
}

# GCP APIs to enable
variable "enable_apis" {
  description = "Whether to enable required GCP APIs"
  type        = bool
  default     = true
}

variable "required_apis" {
  description = "List of required GCP APIs"
  type        = list(string)
  default = [
    "sqladmin.googleapis.com",
    "cloudfunctions.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com"
  ]
}

# Tags and labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    project     = "sql-query-alerts"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}