# Variables for GCP Database Performance Monitoring Infrastructure
# These variables allow customization of the deployment for different environments

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.region))
    error_message = "Region must be a valid GCP region name."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.zone))
    error_message = "Zone must be a valid GCP zone name."
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

# Database Configuration Variables
variable "database_name" {
  description = "Name for the Cloud SQL database instance"
  type        = string
  default     = "performance-monitoring-db"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.database_name))
    error_message = "Database name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "database_version" {
  description = "PostgreSQL version for Cloud SQL instance"
  type        = string
  default     = "POSTGRES_15"
  validation {
    condition     = contains(["POSTGRES_13", "POSTGRES_14", "POSTGRES_15"], var.database_version)
    error_message = "Database version must be one of: POSTGRES_13, POSTGRES_14, POSTGRES_15."
  }
}

variable "database_tier" {
  description = "Machine type for Cloud SQL instance"
  type        = string
  default     = "db-perf-optimized-N-2"
  validation {
    condition     = can(regex("^db-(perf-optimized|custom|standard)-", var.database_tier))
    error_message = "Database tier must be a valid Cloud SQL machine type."
  }
}

variable "storage_size_gb" {
  description = "Initial storage size for Cloud SQL instance in GB"
  type        = number
  default     = 100
  validation {
    condition     = var.storage_size_gb >= 10 && var.storage_size_gb <= 65536
    error_message = "Storage size must be between 10 and 65536 GB."
  }
}

variable "enable_backup" {
  description = "Enable automated backups for Cloud SQL instance"
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "Start time for automated backups (HH:MM format)"
  type        = string
  default     = "02:00"
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Backup start time must be in HH:MM format (24-hour)."
  }
}

# Monitoring Configuration Variables
variable "enable_query_insights" {
  description = "Enable Cloud SQL Query Insights for advanced performance monitoring"
  type        = bool
  default     = true
}

variable "query_string_length" {
  description = "Maximum length of query strings to capture in Query Insights"
  type        = number
  default     = 1024
  validation {
    condition     = var.query_string_length >= 256 && var.query_string_length <= 4500
    error_message = "Query string length must be between 256 and 4500 characters."
  }
}

variable "record_application_tags" {
  description = "Enable recording of application tags in Query Insights"
  type        = bool
  default     = true
}

variable "record_client_address" {
  description = "Enable recording of client addresses in Query Insights"
  type        = bool
  default     = true
}

# Alerting Configuration Variables
variable "cpu_threshold" {
  description = "CPU utilization threshold for alerting (as decimal, e.g., 0.8 for 80%)"
  type        = number
  default     = 0.8
  validation {
    condition     = var.cpu_threshold >= 0.1 && var.cpu_threshold <= 1.0
    error_message = "CPU threshold must be between 0.1 and 1.0."
  }
}

variable "slow_query_threshold_ms" {
  description = "Query execution time threshold for slow query alerts (in milliseconds)"
  type        = number
  default     = 5000
  validation {
    condition     = var.slow_query_threshold_ms >= 100 && var.slow_query_threshold_ms <= 60000
    error_message = "Slow query threshold must be between 100 and 60000 milliseconds."
  }
}

variable "alert_duration" {
  description = "Duration threshold must be exceeded before alerting (in seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.alert_duration >= 60 && var.alert_duration <= 3600
    error_message = "Alert duration must be between 60 and 3600 seconds."
  }
}

# Cloud Function Configuration Variables
variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
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

# Storage Configuration Variables
variable "storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "storage_location" {
  description = "Location for Cloud Storage bucket (region or multi-region)"
  type        = string
  default     = "US-CENTRAL1"
}

# Security Configuration Variables
variable "database_root_password" {
  description = "Root password for Cloud SQL instance (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "authorized_networks" {
  description = "List of authorized networks for Cloud SQL access"
  type = list(object({
    name  = string
    value = string
  }))
  default = [
    {
      name  = "all"
      value = "0.0.0.0/0"
    }
  ]
}

variable "deletion_protection" {
  description = "Enable deletion protection for Cloud SQL instance"
  type        = bool
  default     = false
}

# Tagging Variables
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    project     = "database-monitoring"
    managed_by  = "terraform"
  }
}

# Maintenance Window Configuration
variable "maintenance_window_day" {
  description = "Day of week for maintenance window (1=Monday, 7=Sunday)"
  type        = number
  default     = 7
  validation {
    condition     = var.maintenance_window_day >= 1 && var.maintenance_window_day <= 7
    error_message = "Maintenance window day must be between 1 (Monday) and 7 (Sunday)."
  }
}

variable "maintenance_window_hour" {
  description = "Hour of day for maintenance window (0-23)"
  type        = number
  default     = 4
  validation {
    condition     = var.maintenance_window_hour >= 0 && var.maintenance_window_hour <= 23
    error_message = "Maintenance window hour must be between 0 and 23."
  }
}