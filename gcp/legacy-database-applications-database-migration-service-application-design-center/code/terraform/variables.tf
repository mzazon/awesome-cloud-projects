# ===================================================
# Variables for Legacy Database Migration Solution
# ===================================================

# ===================================================
# General Configuration
# ===================================================

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
}

variable "base_name" {
  description = "Base name for all resources (will be suffixed with random string)"
  type        = string
  default     = "legacy-migration"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.base_name))
    error_message = "Base name must be 3-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "Google Cloud region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# ===================================================
# Network Configuration
# ===================================================

variable "subnet_cidr" {
  description = "CIDR range for the migration subnet"
  type        = string
  default     = "10.1.0.0/24"
  
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR range."
  }
}

variable "services_cidr" {
  description = "CIDR range for services secondary range"
  type        = string
  default     = "10.1.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.services_cidr, 0))
    error_message = "Services CIDR must be a valid IPv4 CIDR range."
  }
}

variable "allowed_ssh_sources" {
  description = "List of CIDR ranges allowed for SSH access"
  type        = list(string)
  default     = ["35.235.240.0/20"] # Google Cloud IAP range
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_ssh_sources : can(cidrhost(cidr, 0))
    ])
    error_message = "All SSH source ranges must be valid IPv4 CIDR ranges."
  }
}

variable "authorized_networks" {
  description = "List of authorized networks for Cloud SQL public access"
  type = list(object({
    name = string
    cidr = string
  }))
  default = []
}

# ===================================================
# Cloud SQL PostgreSQL Configuration
# ===================================================

variable "postgres_version" {
  description = "PostgreSQL version for the target database"
  type        = string
  default     = "POSTGRES_15"
  
  validation {
    condition = contains([
      "POSTGRES_12", "POSTGRES_13", "POSTGRES_14", 
      "POSTGRES_15", "POSTGRES_16"
    ], var.postgres_version)
    error_message = "PostgreSQL version must be one of: POSTGRES_12, POSTGRES_13, POSTGRES_14, POSTGRES_15, POSTGRES_16."
  }
}

variable "postgres_tier" {
  description = "Machine tier for the PostgreSQL instance"
  type        = string
  default     = "db-standard-2"
  
  validation {
    condition     = can(regex("^db-(standard|custom|highmem|n1-|custom-)", var.postgres_tier))
    error_message = "PostgreSQL tier must be a valid Cloud SQL machine type."
  }
}

variable "postgres_availability_type" {
  description = "Availability type for PostgreSQL instance (ZONAL or REGIONAL)"
  type        = string
  default     = "ZONAL"
  
  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.postgres_availability_type)
    error_message = "Availability type must be either ZONAL or REGIONAL."
  }
}

variable "postgres_disk_size" {
  description = "Initial disk size for PostgreSQL instance in GB"
  type        = number
  default     = 100
  
  validation {
    condition     = var.postgres_disk_size >= 10 && var.postgres_disk_size <= 65536
    error_message = "PostgreSQL disk size must be between 10 GB and 65536 GB."
  }
}

variable "postgres_disk_autoresize_limit" {
  description = "Maximum disk size for autoresize in GB (0 for unlimited)"
  type        = number
  default     = 500
  
  validation {
    condition     = var.postgres_disk_autoresize_limit >= 0
    error_message = "PostgreSQL disk autoresize limit must be 0 or greater."
  }
}

variable "postgres_database_flags" {
  description = "Database flags for PostgreSQL instance optimization"
  type        = map(string)
  default = {
    "shared_preload_libraries" = "pg_stat_statements"
    "log_checkpoints"         = "on"
    "log_connections"         = "on"
    "log_disconnections"      = "on"
    "log_lock_waits"         = "on"
    "log_temp_files"         = "0"
    "track_activity_query_size" = "2048"
    "track_io_timing"        = "on"
  }
}

variable "enable_public_ip" {
  description = "Enable public IP for Cloud SQL instance"
  type        = bool
  default     = false
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for Cloud SQL instance"
  type        = bool
  default     = true
}

# ===================================================
# Source Database Configuration
# ===================================================

variable "source_database_host" {
  description = "Hostname or IP address of the source database (SQL Server)"
  type        = string
  default     = "source-sqlserver.example.com"
  sensitive   = false # Set to true in production
}

variable "source_database_port" {
  description = "Port number of the source database"
  type        = number
  default     = 1433
  
  validation {
    condition     = var.source_database_port > 0 && var.source_database_port <= 65535
    error_message = "Source database port must be between 1 and 65535."
  }
}

variable "source_database_username" {
  description = "Username for connecting to the source database"
  type        = string
  default     = "migration_user"
  sensitive   = true
}

variable "source_database_password" {
  description = "Password for connecting to the source database"
  type        = string
  default     = "please-change-this-password"
  sensitive   = true
  
  validation {
    condition     = length(var.source_database_password) >= 8
    error_message = "Source database password must be at least 8 characters long."
  }
}

variable "source_ssl_type" {
  description = "SSL configuration type for source database connection"
  type        = string
  default     = "REQUIRED"
  
  validation {
    condition     = contains(["NONE", "REQUIRED", "SERVER_CLIENT"], var.source_ssl_type)
    error_message = "Source SSL type must be one of: NONE, REQUIRED, SERVER_CLIENT."
  }
}

# ===================================================
# Database Migration Service Configuration
# ===================================================

variable "migration_type" {
  description = "Type of migration (ONE_TIME or CONTINUOUS)"
  type        = string
  default     = "CONTINUOUS"
  
  validation {
    condition     = contains(["ONE_TIME", "CONTINUOUS"], var.migration_type)
    error_message = "Migration type must be either ONE_TIME or CONTINUOUS."
  }
}

variable "migration_parallel_level" {
  description = "Parallelism level for migration dump operations"
  type        = string
  default     = "OPTIMAL"
  
  validation {
    condition     = contains(["MIN", "OPTIMAL", "MAX"], var.migration_parallel_level)
    error_message = "Migration parallel level must be one of: MIN, OPTIMAL, MAX."
  }
}

# ===================================================
# Application Modernization Configuration
# ===================================================

variable "enable_code_assist" {
  description = "Enable Gemini Code Assist for application modernization"
  type        = bool
  default     = true
}

variable "enable_application_design_center" {
  description = "Enable Application Design Center for architecture guidance"
  type        = bool
  default     = true
}

variable "modernization_frameworks" {
  description = "Target frameworks for application modernization"
  type = object({
    backend_framework = string
    orm_framework     = string
    build_tool       = string
    deployment_target = string
  })
  default = {
    backend_framework = "spring-boot"
    orm_framework     = "hibernate"
    build_tool       = "maven"
    deployment_target = "gke"
  }
}

# ===================================================
# Monitoring and Observability Configuration
# ===================================================

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable detailed logging for migration activities"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain migration logs"
  type        = number
  default     = 90
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653 (10 years)."
  }
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

# ===================================================
# Security Configuration
# ===================================================

variable "enable_vpc_flow_logs" {
  description = "Enable VPC flow logs for network monitoring"
  type        = bool
  default     = true
}

variable "enable_private_google_access" {
  description = "Enable Private Google Access for subnets"
  type        = bool
  default     = true
}

variable "require_ssl_connections" {
  description = "Require SSL connections to Cloud SQL"
  type        = bool
  default     = true
}

# ===================================================
# Backup and Recovery Configuration
# ===================================================

variable "backup_retention_days" {
  description = "Number of days to retain database backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 7 and 365 days."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for PostgreSQL"
  type        = bool
  default     = true
}

variable "transaction_log_retention_days" {
  description = "Number of days to retain transaction logs for point-in-time recovery"
  type        = number
  default     = 7
  
  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35
    error_message = "Transaction log retention must be between 1 and 35 days."
  }
}

# ===================================================
# Cost Optimization Configuration
# ===================================================

variable "enable_deletion_protection_override" {
  description = "Override deletion protection for non-production environments"
  type        = bool
  default     = false
}

variable "scheduled_maintenance_window" {
  description = "Preferred maintenance window configuration"
  type = object({
    day  = number # 1-7 (Monday-Sunday)
    hour = number # 0-23
  })
  default = {
    day  = 7 # Sunday
    hour = 4 # 4 AM
  }
  
  validation {
    condition = (
      var.scheduled_maintenance_window.day >= 1 && 
      var.scheduled_maintenance_window.day <= 7 &&
      var.scheduled_maintenance_window.hour >= 0 && 
      var.scheduled_maintenance_window.hour <= 23
    )
    error_message = "Maintenance window day must be 1-7 and hour must be 0-23."
  }
}

# ===================================================
# Feature Flags
# ===================================================

variable "enable_advanced_features" {
  description = "Enable advanced features like Query Insights and Performance Schema"
  type        = bool
  default     = true
}

variable "enable_data_governance" {
  description = "Enable data governance features like Data Catalog integration"
  type        = bool
  default     = false
}

variable "enable_disaster_recovery" {
  description = "Enable disaster recovery features like cross-region replicas"
  type        = bool
  default     = false
}

# ===================================================
# Tags and Labels
# ===================================================

variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens (max 63 chars)."
  }
}

variable "cost_center" {
  description = "Cost center for billing and chargeback"
  type        = string
  default     = "engineering"
}

variable "owner" {
  description = "Owner or team responsible for the resources"
  type        = string
  default     = "data-platform-team"
}