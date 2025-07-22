# =============================================================================
# VARIABLES - Database Maintenance Automation with Cloud SQL and Cloud Scheduler
# =============================================================================
# This file defines all configurable variables for the database maintenance
# automation infrastructure. These variables allow customization of the
# deployment for different environments and requirements.
# =============================================================================

# =============================================================================
# PROJECT CONFIGURATION
# =============================================================================

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region where resources will be deployed"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone within the region for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and organization"
  type        = string
  default     = "development"
  
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# =============================================================================
# CLOUD SQL DATABASE CONFIGURATION
# =============================================================================

variable "db_tier" {
  description = "Cloud SQL instance tier (machine type and memory)"
  type        = string
  default     = "db-f1-micro"
  
  validation {
    condition = can(regex("^db-(f1-micro|g1-small|n1-standard-[0-9]+|n1-highmem-[0-9]+|n1-highcpu-[0-9]+)$", var.db_tier))
    error_message = "Database tier must be a valid Cloud SQL tier (e.g., db-f1-micro, db-n1-standard-1)."
  }
}

variable "db_disk_size" {
  description = "Initial disk size for Cloud SQL instance in GB"
  type        = number
  default     = 10
  
  validation {
    condition     = var.db_disk_size >= 10 && var.db_disk_size <= 65536
    error_message = "Database disk size must be between 10 GB and 65536 GB."
  }
}

variable "db_password" {
  description = "Password for the database maintenance user"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Database password must be at least 8 characters long."
  }
}

# =============================================================================
# CLOUD SCHEDULER CONFIGURATION
# =============================================================================

variable "maintenance_schedule" {
  description = "Cron schedule for daily maintenance tasks (in UTC)"
  type        = string
  default     = "0 2 * * *"  # Daily at 2 AM EST (7 AM UTC)
  
  validation {
    condition = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.maintenance_schedule))
    error_message = "Maintenance schedule must be a valid cron expression (5 fields)."
  }
}

variable "monitoring_schedule" {
  description = "Cron schedule for performance monitoring tasks (in UTC)"
  type        = string
  default     = "0 */6 * * *"  # Every 6 hours
  
  validation {
    condition = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.monitoring_schedule))
    error_message = "Monitoring schedule must be a valid cron expression (5 fields)."
  }
}

variable "timezone" {
  description = "Timezone for Cloud Scheduler jobs"
  type        = string
  default     = "America/New_York"
  
  validation {
    condition = can(regex("^[A-Za-z]+/[A-Za-z_]+$", var.timezone))
    error_message = "Timezone must be a valid IANA timezone (e.g., America/New_York)."
  }
}

# =============================================================================
# MONITORING AND ALERTING CONFIGURATION
# =============================================================================

variable "alert_email" {
  description = "Email address for monitoring alerts (leave empty to disable email alerts)"
  type        = string
  default     = ""
  
  validation {
    condition = var.alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be empty or a valid email address."
  }
}

variable "cpu_alert_threshold" {
  description = "CPU utilization threshold (0.0-1.0) for triggering alerts"
  type        = number
  default     = 0.8
  
  validation {
    condition     = var.cpu_alert_threshold >= 0.0 && var.cpu_alert_threshold <= 1.0
    error_message = "CPU alert threshold must be between 0.0 and 1.0."
  }
}

variable "connection_alert_threshold" {
  description = "Number of database connections threshold for triggering alerts"
  type        = number
  default     = 80
  
  validation {
    condition     = var.connection_alert_threshold > 0 && var.connection_alert_threshold <= 4000
    error_message = "Connection alert threshold must be between 1 and 4000."
  }
}

# =============================================================================
# CLOUD FUNCTION CONFIGURATION
# =============================================================================

variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 256
  
  validation {
    condition = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 540
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime environment for Cloud Function"
  type        = string
  default     = "python39"
  
  validation {
    condition = contains(["python38", "python39", "python310", "python311"], var.function_runtime)
    error_message = "Function runtime must be one of: python38, python39, python310, python311."
  }
}

# =============================================================================
# STORAGE CONFIGURATION
# =============================================================================

variable "bucket_location" {
  description = "Location for Cloud Storage bucket (region or multi-region)"
  type        = string
  default     = ""  # Will use region if empty
  
  validation {
    condition = var.bucket_location == "" || can(regex("^[A-Z0-9-]+$", var.bucket_location))
    error_message = "Bucket location must be empty (to use region) or a valid Cloud Storage location."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain maintenance logs in storage"
  type        = number
  default     = 365
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3650
    error_message = "Log retention days must be between 1 and 3650 (10 years)."
  }
}

variable "nearline_transition_days" {
  description = "Number of days after which logs transition to Nearline storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.nearline_transition_days >= 1 && var.nearline_transition_days <= 365
    error_message = "Nearline transition days must be between 1 and 365."
  }
}

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

variable "enable_deletion_protection" {
  description = "Enable deletion protection for Cloud SQL instance"
  type        = bool
  default     = false
}

variable "authorized_networks" {
  description = "List of authorized networks for Cloud SQL access"
  type = list(object({
    name  = string
    value = string
  }))
  default = [
    {
      name  = "allow-all"
      value = "0.0.0.0/0"
    }
  ]
  
  validation {
    condition = alltrue([
      for network in var.authorized_networks : can(cidrhost(network.value, 0))
    ])
    error_message = "All authorized networks must be valid CIDR blocks."
  }
}

variable "require_ssl" {
  description = "Require SSL connections to Cloud SQL instance"
  type        = bool
  default     = false
}

# =============================================================================
# ADVANCED CONFIGURATION
# =============================================================================

variable "backup_retention_count" {
  description = "Number of automated backups to retain"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_count >= 1 && var.backup_retention_count <= 365
    error_message = "Backup retention count must be between 1 and 365."
  }
}

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
  description = "Hour of day for maintenance window (0-23, UTC)"
  type        = number
  default     = 3
  
  validation {
    condition     = var.maintenance_window_hour >= 0 && var.maintenance_window_hour <= 23
    error_message = "Maintenance window hour must be between 0 and 23."
  }
}

variable "enable_query_insights" {
  description = "Enable Cloud SQL Query Insights for performance monitoring"
  type        = bool
  default     = true
}

variable "scheduler_retry_count" {
  description = "Maximum number of retry attempts for failed scheduler jobs"
  type        = number
  default     = 3
  
  validation {
    condition     = var.scheduler_retry_count >= 0 && var.scheduler_retry_count <= 5
    error_message = "Scheduler retry count must be between 0 and 5."
  }
}

# =============================================================================
# FEATURE FLAGS
# =============================================================================

variable "enable_monitoring_dashboard" {
  description = "Enable creation of Cloud Monitoring dashboard"
  type        = bool
  default     = true
}

variable "enable_alerting_policies" {
  description = "Enable creation of monitoring alert policies"
  type        = bool
  default     = true
}

variable "enable_performance_monitoring" {
  description = "Enable separate performance monitoring scheduler job"
  type        = bool
  default     = true
}

variable "enable_bucket_versioning" {
  description = "Enable versioning for Cloud Storage bucket"
  type        = bool
  default     = true
}

# =============================================================================
# TAGS AND LABELS
# =============================================================================

variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "All label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}