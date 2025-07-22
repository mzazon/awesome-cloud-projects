# =============================================================================
# Core Project Configuration
# =============================================================================

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., us-central1-a)."
  }
}

# =============================================================================
# Resource Naming and Labels
# =============================================================================

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "migration-monitor"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,20}$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens, max 20 characters."
  }
}

variable "environment" {
  description = "Environment name for resource labeling"
  type        = string
  default     = "development"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "database-migration-monitoring"
    recipe      = "database-migration-health-performance-workload-manager-functions"
    managed-by  = "terraform"
  }
}

# =============================================================================
# Database Configuration
# =============================================================================

variable "database_version" {
  description = "The MySQL database version for Cloud SQL"
  type        = string
  default     = "MYSQL_8_0"
  validation {
    condition     = contains(["MYSQL_5_7", "MYSQL_8_0"], var.database_version)
    error_message = "Database version must be MYSQL_5_7 or MYSQL_8_0."
  }
}

variable "database_tier" {
  description = "The machine type for the Cloud SQL instance"
  type        = string
  default     = "db-g1-small"
  validation {
    condition     = can(regex("^db-[a-z0-9-]+$", var.database_tier))
    error_message = "Database tier must be a valid Cloud SQL machine type (e.g., db-g1-small)."
  }
}

variable "database_storage_size" {
  description = "Storage size in GB for the Cloud SQL instance"
  type        = number
  default     = 20
  validation {
    condition     = var.database_storage_size >= 10 && var.database_storage_size <= 65536
    error_message = "Database storage size must be between 10GB and 65536GB."
  }
}

variable "database_backup_time" {
  description = "Backup start time in HH:MM format"
  type        = string
  default     = "03:00"
  validation {
    condition     = can(regex("^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$", var.database_backup_time))
    error_message = "Backup time must be in HH:MM format (24-hour)."
  }
}

variable "database_name" {
  description = "Name of the database to create"
  type        = string
  default     = "sample_db"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "Database name must start with a letter and contain only letters, numbers, and underscores, max 63 characters."
  }
}

# =============================================================================
# Cloud Functions Configuration
# =============================================================================

variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition     = contains(["python38", "python39", "python310", "python311", "python312"], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (MB)"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (seconds)"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "validation_function_timeout" {
  description = "Timeout for data validation function (seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.validation_function_timeout >= 1 && var.validation_function_timeout <= 540
    error_message = "Validation function timeout must be between 1 and 540 seconds."
  }
}

variable "validation_function_memory" {
  description = "Memory allocation for data validation function (MB)"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.validation_function_memory)
    error_message = "Validation function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

# =============================================================================
# Cloud Storage Configuration
# =============================================================================

variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "storage_versioning" {
  description = "Enable versioning for the Cloud Storage bucket"
  type        = bool
  default     = true
}

# =============================================================================
# Workload Manager Configuration
# =============================================================================

variable "workload_type" {
  description = "Type of workload for Cloud Workload Manager"
  type        = string
  default     = "DATABASE"
  validation {
    condition     = contains(["DATABASE", "APPLICATION", "INFRASTRUCTURE"], var.workload_type)
    error_message = "Workload type must be one of: DATABASE, APPLICATION, INFRASTRUCTURE."
  }
}

# =============================================================================
# Monitoring and Alerting Configuration
# =============================================================================

variable "enable_monitoring_dashboard" {
  description = "Enable creation of custom monitoring dashboard"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be empty or a valid email address."
  }
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "enable_private_ip" {
  description = "Enable private IP for Cloud SQL instance"
  type        = bool
  default     = false
}

variable "authorized_networks" {
  description = "List of authorized networks for Cloud SQL access"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

# =============================================================================
# Cost and Resource Management
# =============================================================================

variable "enable_deletion_protection" {
  description = "Enable deletion protection for Cloud SQL instance"
  type        = bool
  default     = false
}

variable "auto_scaling_enabled" {
  description = "Enable automatic scaling for Cloud SQL storage"
  type        = bool
  default     = true
}

variable "maintenance_window_day" {
  description = "Day of week for maintenance window (1-7, 1=Sunday)"
  type        = number
  default     = 1
  validation {
    condition     = var.maintenance_window_day >= 1 && var.maintenance_window_day <= 7
    error_message = "Maintenance window day must be between 1 (Sunday) and 7 (Saturday)."
  }
}

variable "maintenance_window_hour" {
  description = "Hour of day for maintenance window (0-23)"
  type        = number
  default     = 3
  validation {
    condition     = var.maintenance_window_hour >= 0 && var.maintenance_window_hour <= 23
    error_message = "Maintenance window hour must be between 0 and 23."
  }
}