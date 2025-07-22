# Core Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region where Database Migration Service and AlloyDB are available."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Network Configuration
variable "network_name" {
  description = "Name of the VPC network for migration infrastructure"
  type        = string
  default     = "migration-network"
}

variable "subnet_cidr" {
  description = "CIDR range for the migration subnet"
  type        = string
  default     = "10.0.0.0/24"
  
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR range."
  }
}

# Migration Worker Configuration
variable "worker_machine_type" {
  description = "Machine type for migration worker instances"
  type        = string
  default     = "e2-standard-4"
  
  validation {
    condition = contains([
      "e2-standard-2", "e2-standard-4", "e2-standard-8",
      "n2-standard-2", "n2-standard-4", "n2-standard-8",
      "c2-standard-4", "c2-standard-8", "c2-standard-16"
    ], var.worker_machine_type)
    error_message = "Machine type must be a valid GCP machine type suitable for database migration workloads."
  }
}

variable "worker_disk_size" {
  description = "Boot disk size for migration worker instances (GB)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.worker_disk_size >= 20 && var.worker_disk_size <= 1000
    error_message = "Worker disk size must be between 20 and 1000 GB."
  }
}

variable "max_worker_instances" {
  description = "Maximum number of migration worker instances for autoscaling"
  type        = number
  default     = 8
  
  validation {
    condition     = var.max_worker_instances >= 1 && var.max_worker_instances <= 20
    error_message = "Maximum worker instances must be between 1 and 20."
  }
}

# Cloud SQL Configuration
variable "cloudsql_tier" {
  description = "Cloud SQL instance tier for MySQL target database"
  type        = string
  default     = "db-n1-standard-4"
  
  validation {
    condition = can(regex("^db-(n1|n2|e2)-(standard|highmem|highcpu)-(1|2|4|8|16|32|64|96)$", var.cloudsql_tier))
    error_message = "Cloud SQL tier must be a valid instance tier (e.g., db-n1-standard-4)."
  }
}

variable "cloudsql_storage_size" {
  description = "Cloud SQL storage size in GB"
  type        = number
  default     = 100
  
  validation {
    condition     = var.cloudsql_storage_size >= 10 && var.cloudsql_storage_size <= 30720
    error_message = "Cloud SQL storage size must be between 10 and 30720 GB."
  }
}

variable "cloudsql_database_version" {
  description = "Cloud SQL MySQL database version"
  type        = string
  default     = "MYSQL_8_0"
  
  validation {
    condition = contains([
      "MYSQL_5_7", "MYSQL_8_0"
    ], var.cloudsql_database_version)
    error_message = "Database version must be a supported MySQL version."
  }
}

# AlloyDB Configuration
variable "alloydb_cpu_count" {
  description = "Number of vCPUs for AlloyDB primary instance"
  type        = number
  default     = 4
  
  validation {
    condition     = contains([2, 4, 8, 16, 32, 64, 96, 128], var.alloydb_cpu_count)
    error_message = "AlloyDB CPU count must be a valid value (2, 4, 8, 16, 32, 64, 96, or 128)."
  }
}

variable "alloydb_memory_size" {
  description = "Memory size for AlloyDB primary instance in GB"
  type        = number
  default     = 16
  
  validation {
    condition     = var.alloydb_memory_size >= 4 && var.alloydb_memory_size <= 768
    error_message = "AlloyDB memory size must be between 4 and 768 GB."
  }
}

variable "alloydb_database_version" {
  description = "AlloyDB PostgreSQL database version"
  type        = string
  default     = "POSTGRES_15"
  
  validation {
    condition = contains([
      "POSTGRES_13", "POSTGRES_14", "POSTGRES_15"
    ], var.alloydb_database_version)
    error_message = "AlloyDB database version must be a supported PostgreSQL version."
  }
}

# Source Database Configuration
variable "source_mysql_host" {
  description = "Hostname or IP address of the source MySQL database"
  type        = string
  default     = "203.0.113.1"
}

variable "source_mysql_port" {
  description = "Port number for the source MySQL database"
  type        = number
  default     = 3306
  
  validation {
    condition     = var.source_mysql_port >= 1 && var.source_mysql_port <= 65535
    error_message = "MySQL port must be a valid port number between 1 and 65535."
  }
}

variable "source_postgres_host" {
  description = "Hostname or IP address of the source PostgreSQL database"
  type        = string
  default     = "203.0.113.2"
}

variable "source_postgres_port" {
  description = "Port number for the source PostgreSQL database"
  type        = number
  default     = 5432
  
  validation {
    condition     = var.source_postgres_port >= 1 && var.source_postgres_port <= 65535
    error_message = "PostgreSQL port must be a valid port number between 1 and 65535."
  }
}

# Security Configuration
variable "source_db_username" {
  description = "Username for source database connections"
  type        = string
  default     = "migration_user"
  sensitive   = true
}

variable "source_db_password" {
  description = "Password for source database connections"
  type        = string
  default     = "SecureSourcePass123!"
  sensitive   = true
  
  validation {
    condition     = length(var.source_db_password) >= 8
    error_message = "Source database password must be at least 8 characters long."
  }
}

variable "cloudsql_migration_user_password" {
  description = "Password for Cloud SQL migration user"
  type        = string
  default     = "SecureMigration123!"
  sensitive   = true
  
  validation {
    condition     = length(var.cloudsql_migration_user_password) >= 8
    error_message = "Cloud SQL migration user password must be at least 8 characters long."
  }
}

# Tagging and Labels
variable "environment" {
  description = "Environment name for resource labeling"
  type        = string
  default     = "development"
  
  validation {
    condition = contains([
      "development", "testing", "staging", "production"
    ], var.environment)
    error_message = "Environment must be one of: development, testing, staging, production."
  }
}

variable "team" {
  description = "Team responsible for the migration resources"
  type        = string
  default     = "data-engineering"
}

variable "project_name" {
  description = "Project name for resource labeling"
  type        = string
  default     = "database-migration"
}

# Migration Configuration
variable "migration_bucket_location" {
  description = "Location for the Cloud Storage bucket used for migration artifacts"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "us-west1",
      "europe-west1", "europe-west4", "asia-east1", "asia-northeast1"
    ], var.migration_bucket_location)
    error_message = "Bucket location must be a valid Cloud Storage location."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for database instances"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

# Dynamic Workload Scheduler Configuration
variable "reservation_capacity" {
  description = "Number of instances to reserve for migration workloads"
  type        = number
  default     = 4
  
  validation {
    condition     = var.reservation_capacity >= 1 && var.reservation_capacity <= 20
    error_message = "Reservation capacity must be between 1 and 20 instances."
  }
}

variable "autoscaling_cpu_target" {
  description = "Target CPU utilization for autoscaling migration workers"
  type        = number
  default     = 0.7
  
  validation {
    condition     = var.autoscaling_cpu_target >= 0.1 && var.autoscaling_cpu_target <= 1.0
    error_message = "Autoscaling CPU target must be between 0.1 and 1.0."
  }
}

variable "cooldown_period_seconds" {
  description = "Cooldown period for autoscaler in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.cooldown_period_seconds >= 60 && var.cooldown_period_seconds <= 3600
    error_message = "Cooldown period must be between 60 and 3600 seconds."
  }
}