# Variables for Database Disaster Recovery with Backup and DR Service and Cloud SQL

variable "project_id" {
  description = "The Google Cloud Project ID"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be a valid GCP project identifier."
  }
}

variable "project_number" {
  description = "The Google Cloud Project Number (required for service account permissions)"
  type        = string
  validation {
    condition     = can(regex("^[0-9]+$", var.project_number))
    error_message = "Project number must be numeric."
  }
}

variable "primary_region" {
  description = "Primary region for Cloud SQL instance and backup vault"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.primary_region)
    error_message = "Primary region must be a valid GCP region."
  }
}

variable "secondary_region" {
  description = "Secondary region for disaster recovery replica and backup vault"
  type        = string
  default     = "us-east1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.secondary_region)
    error_message = "Secondary region must be a valid GCP region."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "Environment must be lowercase alphanumeric with hyphens."
  }
}

variable "db_instance_name" {
  description = "Name for the primary Cloud SQL instance"
  type        = string
  default     = ""
  validation {
    condition     = var.db_instance_name == "" || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.db_instance_name))
    error_message = "Database instance name must be lowercase alphanumeric with hyphens."
  }
}

variable "database_version" {
  description = "The database version for Cloud SQL"
  type        = string
  default     = "POSTGRES_15"
  validation {
    condition = contains([
      "POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16",
      "MYSQL_8_0", "MYSQL_8_0_18", "MYSQL_8_0_26", "MYSQL_8_0_27", "MYSQL_8_0_28", "MYSQL_8_0_29", "MYSQL_8_0_30", "MYSQL_8_0_31", "MYSQL_8_0_32", "MYSQL_8_0_33", "MYSQL_8_0_34", "MYSQL_8_0_35", "MYSQL_8_0_36", "MYSQL_8_0_37"
    ], var.database_version)
    error_message = "Database version must be a supported Cloud SQL version."
  }
}

variable "db_tier" {
  description = "The machine type for Cloud SQL instances"
  type        = string
  default     = "db-custom-2-8192"
  validation {
    condition     = can(regex("^db-(f1-micro|g1-small|custom-[0-9]+-[0-9]+)$", var.db_tier))
    error_message = "Database tier must be a valid Cloud SQL machine type."
  }
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 7 and 365 days."
  }
}

variable "backup_start_time" {
  description = "HH:MM format time when automated backups should start"
  type        = string
  default     = "03:00"
  validation {
    condition     = can(regex("^[0-2][0-9]:[0-5][0-9]$", var.backup_start_time))
    error_message = "Backup start time must be in HH:MM format."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for Cloud SQL instances"
  type        = bool
  default     = true
}

variable "enable_binary_logging" {
  description = "Enable binary logging for point-in-time recovery"
  type        = bool
  default     = true
}

variable "storage_size_gb" {
  description = "Initial storage size in GB for Cloud SQL instances"
  type        = number
  default     = 100
  validation {
    condition     = var.storage_size_gb >= 10 && var.storage_size_gb <= 65536
    error_message = "Storage size must be between 10 and 65536 GB."
  }
}

variable "max_connections" {
  description = "Maximum number of connections for Cloud SQL instances"
  type        = number
  default     = 200
  validation {
    condition     = var.max_connections >= 10 && var.max_connections <= 10000
    error_message = "Max connections must be between 10 and 10000."
  }
}

variable "monitoring_schedule" {
  description = "Cron schedule for disaster recovery monitoring jobs"
  type        = string
  default     = "0 */6 * * *"
  validation {
    condition     = can(regex("^[0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+$", var.monitoring_schedule))
    error_message = "Monitoring schedule must be a valid cron expression."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout in seconds for Cloud Functions"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "512M"
  validation {
    condition = contains([
      "128M", "256M", "512M", "1024M", "2048M", "4096M", "8192M"
    ], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions memory allocation."
  }
}

variable "network_name" {
  description = "Name of the VPC network (optional, uses default if not specified)"
  type        = string
  default     = "default"
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    purpose     = "disaster-recovery"
    managed-by  = "terraform"
    environment = "production"
  }
}

variable "enable_private_ip" {
  description = "Enable private IP for Cloud SQL instances"
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

variable "alert_notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}