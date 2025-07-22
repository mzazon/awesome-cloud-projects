# Variables for zero-downtime database migration infrastructure

# ============================================================================
# PROJECT AND ENVIRONMENT CONFIGURATION
# ============================================================================

variable "project_id" {
  description = "Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for resources requiring zone specification"
  type        = string
  default     = "us-central1-a"
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

# ============================================================================
# CLOUD SQL CONFIGURATION
# ============================================================================

variable "cloudsql_instance_name" {
  description = "Name for the Cloud SQL instance (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "database_version" {
  description = "MySQL version for Cloud SQL instance"
  type        = string
  default     = "MYSQL_8_0"
  validation {
    condition = contains([
      "MYSQL_5_6", "MYSQL_5_7", "MYSQL_8_0", "MYSQL_8_4"
    ], var.database_version)
    error_message = "Database version must be a supported MySQL version."
  }
}

variable "database_tier" {
  description = "Machine type for Cloud SQL instance"
  type        = string
  default     = "db-n1-standard-2"
  validation {
    condition = can(regex("^db-(n1|n2|custom)-", var.database_tier))
    error_message = "Database tier must be a valid Cloud SQL machine type."
  }
}

variable "disk_size" {
  description = "Disk size in GB for Cloud SQL instance"
  type        = number
  default     = 100
  validation {
    condition     = var.disk_size >= 10 && var.disk_size <= 65536
    error_message = "Disk size must be between 10 and 65536 GB."
  }
}

variable "availability_type" {
  description = "Availability type for Cloud SQL instance (ZONAL or REGIONAL)"
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "Availability type must be either ZONAL or REGIONAL."
  }
}

variable "backup_start_time" {
  description = "Start time for automated backups (HH:MM format in UTC)"
  type        = string
  default     = "03:00"
  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Backup start time must be in HH:MM format."
  }
}

variable "maintenance_window_day" {
  description = "Day of week for maintenance window (1 = Monday, 7 = Sunday)"
  type        = number
  default     = 7
  validation {
    condition     = var.maintenance_window_day >= 1 && var.maintenance_window_day <= 7
    error_message = "Maintenance window day must be between 1 and 7."
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

# ============================================================================
# SOURCE DATABASE CONFIGURATION
# ============================================================================

variable "source_database_host" {
  description = "Hostname or IP address of the source MySQL database"
  type        = string
  default     = ""
}

variable "source_database_port" {
  description = "Port number for the source MySQL database"
  type        = number
  default     = 3306
  validation {
    condition     = var.source_database_port > 0 && var.source_database_port <= 65535
    error_message = "Source database port must be between 1 and 65535."
  }
}

variable "source_database_username" {
  description = "Username for connecting to the source MySQL database"
  type        = string
  default     = "migration_user"
}

variable "source_database_password" {
  description = "Password for connecting to the source MySQL database"
  type        = string
  sensitive   = true
  default     = ""
}

# ============================================================================
# DATABASE MIGRATION SERVICE CONFIGURATION
# ============================================================================

variable "migration_type" {
  description = "Type of migration (ONE_TIME or CONTINUOUS)"
  type        = string
  default     = "CONTINUOUS"
  validation {
    condition     = contains(["ONE_TIME", "CONTINUOUS"], var.migration_type)
    error_message = "Migration type must be either ONE_TIME or CONTINUOUS."
  }
}

variable "connectivity_type" {
  description = "Connectivity type for migration (static_ip or vpc_peering)"
  type        = string
  default     = "vpc_peering"
  validation {
    condition     = contains(["static_ip", "vpc_peering"], var.connectivity_type)
    error_message = "Connectivity type must be either static_ip or vpc_peering."
  }
}

variable "dump_path" {
  description = "Cloud Storage path for database dump (gs://bucket/path)"
  type        = string
  default     = ""
}

# ============================================================================
# NETWORKING CONFIGURATION
# ============================================================================

variable "vpc_name" {
  description = "Name for the VPC network (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid CIDR block."
  }
}

variable "authorized_networks" {
  description = "List of authorized networks for Cloud SQL access"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

# ============================================================================
# MONITORING AND LOGGING CONFIGURATION
# ============================================================================

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for the migration"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Cloud Logging for the migration"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "alert_cpu_threshold" {
  description = "CPU utilization threshold for alerts (0.0 to 1.0)"
  type        = number
  default     = 0.8
  validation {
    condition     = var.alert_cpu_threshold >= 0.0 && var.alert_cpu_threshold <= 1.0
    error_message = "CPU threshold must be between 0.0 and 1.0."
  }
}

variable "alert_memory_threshold" {
  description = "Memory utilization threshold for alerts (0.0 to 1.0)"
  type        = number
  default     = 0.9
  validation {
    condition     = var.alert_memory_threshold >= 0.0 && var.alert_memory_threshold <= 1.0
    error_message = "Memory threshold must be between 0.0 and 1.0."
  }
}

# ============================================================================
# RESOURCE LABELING
# ============================================================================

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}