# ==============================================================================
# VARIABLES - Multi-Database Disaster Recovery with AlloyDB and Cloud Spanner
# ==============================================================================
# This file defines all configurable variables for the disaster recovery
# infrastructure deployment. Customize these values according to your
# specific requirements for regions, sizing, and naming conventions.
# ==============================================================================

# ==============================================================================
# PROJECT AND ENVIRONMENT CONFIGURATION
# ==============================================================================

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be deployed"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and organization"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production", "dr"], var.environment)
    error_message = "Environment must be one of: development, staging, production, dr."
  }
}

# ==============================================================================
# REGIONAL CONFIGURATION
# ==============================================================================

variable "primary_region" {
  description = "Primary Google Cloud region for database deployments"
  type        = string
  default     = "us-central1"

  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.primary_region))
    error_message = "Primary region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "secondary_region" {
  description = "Secondary Google Cloud region for disaster recovery deployments"
  type        = string
  default     = "us-east1"

  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.secondary_region))
    error_message = "Secondary region must be a valid Google Cloud region format (e.g., us-east1)."
  }
}

variable "primary_zone" {
  description = "Primary Google Cloud zone within the primary region"
  type        = string
  default     = "us-central1-a"

  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.primary_zone))
    error_message = "Primary zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "secondary_zone" {
  description = "Secondary Google Cloud zone within the secondary region"
  type        = string
  default     = "us-east1-b"

  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.secondary_zone))
    error_message = "Secondary zone must be a valid Google Cloud zone format (e.g., us-east1-b)."
  }
}

# ==============================================================================
# NETWORKING CONFIGURATION
# ==============================================================================

variable "primary_subnet_cidr" {
  description = "CIDR block for the primary region subnet"
  type        = string
  default     = "10.0.0.0/24"

  validation {
    condition = can(cidrhost(var.primary_subnet_cidr, 0))
    error_message = "Primary subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "secondary_subnet_cidr" {
  description = "CIDR block for the secondary region subnet"
  type        = string
  default     = "10.1.0.0/24"

  validation {
    condition = can(cidrhost(var.secondary_subnet_cidr, 0))
    error_message = "Secondary subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "primary_secondary_cidr" {
  description = "Secondary IP range for primary subnet (used for services)"
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition = can(cidrhost(var.primary_secondary_cidr, 0))
    error_message = "Primary secondary CIDR must be a valid IPv4 CIDR block."
  }
}

variable "secondary_secondary_cidr" {
  description = "Secondary IP range for secondary subnet (used for services)"
  type        = string
  default     = "10.1.1.0/24"

  validation {
    condition = can(cidrhost(var.secondary_secondary_cidr, 0))
    error_message = "Secondary secondary CIDR must be a valid IPv4 CIDR block."
  }
}

# ==============================================================================
# ALLOYDB CONFIGURATION
# ==============================================================================

variable "cluster_name" {
  description = "Base name for AlloyDB clusters (will be suffixed with primary/secondary and random suffix)"
  type        = string
  default     = "alloydb-dr"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cluster_name))
    error_message = "Cluster name must contain only lowercase letters, numbers, and hyphens, starting and ending with alphanumeric characters."
  }
}

variable "db_admin_user" {
  description = "Administrative username for AlloyDB databases"
  type        = string
  default     = "alloydb-admin"

  validation {
    condition     = length(var.db_admin_user) >= 1 && length(var.db_admin_user) <= 63
    error_message = "Database admin username must be between 1 and 63 characters."
  }
}

variable "db_admin_password" {
  description = "Administrative password for AlloyDB databases (use secure methods for production)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_admin_password) >= 8
    error_message = "Database admin password must be at least 8 characters long."
  }
}

variable "alloydb_cpu_count" {
  description = "Number of CPUs for AlloyDB primary instance"
  type        = number
  default     = 4

  validation {
    condition     = var.alloydb_cpu_count >= 2 && var.alloydb_cpu_count <= 96
    error_message = "AlloyDB CPU count must be between 2 and 96."
  }
}

variable "alloydb_read_pool_cpu_count" {
  description = "Number of CPUs for AlloyDB read pool instances"
  type        = number
  default     = 2

  validation {
    condition     = var.alloydb_read_pool_cpu_count >= 2 && var.alloydb_read_pool_cpu_count <= 96
    error_message = "AlloyDB read pool CPU count must be between 2 and 96."
  }
}

variable "alloydb_read_pool_nodes" {
  description = "Number of nodes in AlloyDB read pool"
  type        = number
  default     = 2

  validation {
    condition     = var.alloydb_read_pool_nodes >= 1 && var.alloydb_read_pool_nodes <= 20
    error_message = "AlloyDB read pool nodes must be between 1 and 20."
  }
}

# ==============================================================================
# CLOUD SPANNER CONFIGURATION
# ==============================================================================

variable "spanner_config" {
  description = "Cloud Spanner instance configuration (regional or multi-regional)"
  type        = string
  default     = "nam-eur-asia1"

  validation {
    condition = contains([
      "regional-us-central1", "regional-us-east1", "regional-us-west1", "regional-us-west2",
      "regional-europe-west1", "regional-europe-west2", "regional-europe-west3",
      "regional-asia-southeast1", "regional-asia-northeast1", "regional-asia-east1",
      "nam-eur-asia1", "nam3", "eur3", "asia1"
    ], var.spanner_config)
    error_message = "Spanner config must be a valid regional or multi-regional configuration."
  }
}

variable "spanner_processing_units" {
  description = "Processing units for Cloud Spanner instance (minimum 1000 for multi-regional)"
  type        = number
  default     = 2000

  validation {
    condition     = var.spanner_processing_units >= 1000 && var.spanner_processing_units <= 10000
    error_message = "Spanner processing units must be between 1000 and 10000 for multi-regional configurations."
  }
}

variable "spanner_display_name" {
  description = "Display name for the Cloud Spanner instance"
  type        = string
  default     = "Disaster Recovery Spanner Instance"

  validation {
    condition     = length(var.spanner_display_name) >= 4 && length(var.spanner_display_name) <= 30
    error_message = "Spanner display name must be between 4 and 30 characters."
  }
}

# ==============================================================================
# STORAGE CONFIGURATION
# ==============================================================================

variable "backup_bucket_prefix" {
  description = "Prefix for backup storage bucket names (will be suffixed with region and random suffix)"
  type        = string
  default     = "dr-backup"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.backup_bucket_prefix))
    error_message = "Backup bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "backup_retention_days" {
  description = "Number of days to retain backup files in storage"
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 7 and 365."
  }
}

# ==============================================================================
# CLOUD FUNCTIONS CONFIGURATION
# ==============================================================================

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = number
  default     = 512

  validation {
    condition = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Functions execution (in seconds)"
  type        = number
  default     = 540

  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 3600
    error_message = "Function timeout must be between 60 and 3600 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"

  validation {
    condition = contains([
      "python39", "python310", "python311", "python312",
      "nodejs18", "nodejs20", "go119", "go121",
      "java17", "java21", "dotnet6", "dotnet8"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Google Cloud Functions runtime."
  }
}

# ==============================================================================
# CLOUD SCHEDULER CONFIGURATION
# ==============================================================================

variable "backup_schedule" {
  description = "Cron schedule for automated backup operations"
  type        = string
  default     = "0 */6 * * *"

  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.backup_schedule))
    error_message = "Backup schedule must be a valid cron expression."
  }
}

variable "validation_schedule" {
  description = "Cron schedule for backup validation operations"
  type        = string
  default     = "30 */12 * * *"

  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.validation_schedule))
    error_message = "Validation schedule must be a valid cron expression."
  }
}

variable "scheduler_timezone" {
  description = "Timezone for Cloud Scheduler jobs"
  type        = string
  default     = "UTC"

  validation {
    condition = contains([
      "UTC", "America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles",
      "Europe/London", "Europe/Paris", "Europe/Berlin", "Asia/Tokyo", "Asia/Singapore"
    ], var.scheduler_timezone)
    error_message = "Scheduler timezone must be a valid timezone identifier."
  }
}

# ==============================================================================
# MONITORING AND ALERTING CONFIGURATION
# ==============================================================================

variable "enable_monitoring" {
  description = "Enable comprehensive monitoring and alerting for disaster recovery resources"
  type        = bool
  default     = true
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for disaster recovery alerts"
  type        = list(string)
  default     = []
}

variable "monitoring_dashboard_name" {
  description = "Name for the monitoring dashboard"
  type        = string
  default     = "Multi-Database Disaster Recovery Dashboard"

  validation {
    condition     = length(var.monitoring_dashboard_name) >= 1 && length(var.monitoring_dashboard_name) <= 100
    error_message = "Monitoring dashboard name must be between 1 and 100 characters."
  }
}

# ==============================================================================
# RESOURCE LABELING
# ==============================================================================

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*[a-z0-9]$", k))
    ])
    error_message = "Label keys must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# ==============================================================================
# SECURITY CONFIGURATION
# ==============================================================================

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest for all database resources"
  type        = bool
  default     = true
}

variable "kms_key_ring_location" {
  description = "Location for KMS key ring (if encryption is enabled)"
  type        = string
  default     = "global"

  validation {
    condition = contains(["global", "us", "europe", "asia"], var.kms_key_ring_location)
    error_message = "KMS key ring location must be one of: global, us, europe, asia."
  }
}

# ==============================================================================
# DISASTER RECOVERY CONFIGURATION
# ==============================================================================

variable "rpo_minutes" {
  description = "Recovery Point Objective in minutes (how much data loss is acceptable)"
  type        = number
  default     = 60

  validation {
    condition     = var.rpo_minutes >= 5 && var.rpo_minutes <= 1440
    error_message = "RPO must be between 5 minutes and 24 hours (1440 minutes)."
  }
}

variable "rto_minutes" {
  description = "Recovery Time Objective in minutes (how long recovery should take)"
  type        = number
  default     = 30

  validation {
    condition     = var.rto_minutes >= 5 && var.rto_minutes <= 480
    error_message = "RTO must be between 5 minutes and 8 hours (480 minutes)."
  }
}

variable "enable_cross_region_backup" {
  description = "Enable automatic cross-region backup replication"
  type        = bool
  default     = true
}

variable "backup_verification_enabled" {
  description = "Enable automatic backup verification and testing"
  type        = bool
  default     = true
}

# ==============================================================================
# COST OPTIMIZATION CONFIGURATION
# ==============================================================================

variable "enable_automatic_scaling" {
  description = "Enable automatic scaling for applicable resources"
  type        = bool
  default     = false
}

variable "cost_optimization_level" {
  description = "Level of cost optimization (basic, standard, aggressive)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["basic", "standard", "aggressive"], var.cost_optimization_level)
    error_message = "Cost optimization level must be one of: basic, standard, aggressive."
  }
}