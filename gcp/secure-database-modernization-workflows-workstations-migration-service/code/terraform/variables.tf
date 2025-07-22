# Project Configuration
variable "project_id" {
  description = "GCP Project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "GCP region for regional resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "workstation_cluster_name" {
  description = "Name for the Cloud Workstations cluster"
  type        = string
  default     = "db-migration-cluster"
}

variable "workstation_config_name" {
  description = "Name for the Cloud Workstations configuration"
  type        = string
  default     = "db-migration-config"
}

# Database Configuration
variable "source_database_host" {
  description = "Hostname of the source database to migrate"
  type        = string
  default     = "source-db.example.com"
}

variable "source_database_port" {
  description = "Port of the source database"
  type        = number
  default     = 3306
}

variable "source_database_user" {
  description = "Username for source database connection"
  type        = string
  default     = "migration_user"
}

variable "source_database_password" {
  description = "Password for source database connection"
  type        = string
  sensitive   = true
}

variable "source_database_name" {
  description = "Name of the source database"
  type        = string
  default     = "legacy_db"
}

variable "target_database_version" {
  description = "Target Cloud SQL database version"
  type        = string
  default     = "MYSQL_8_0"
}

variable "target_database_tier" {
  description = "Machine type for target Cloud SQL instance"
  type        = string
  default     = "db-custom-2-7680"
}

variable "target_database_storage_size" {
  description = "Storage size for target Cloud SQL instance in GB"
  type        = number
  default     = 100
}

# Cloud Workstations Configuration
variable "workstation_machine_type" {
  description = "Machine type for Cloud Workstations"
  type        = string
  default     = "e2-standard-4"
}

variable "workstation_boot_disk_size" {
  description = "Boot disk size for workstations in GB"
  type        = number
  default     = 50
}

variable "workstation_persistent_disk_size" {
  description = "Persistent disk size for workstations in GB"
  type        = number
  default     = 50
}

variable "workstation_idle_timeout" {
  description = "Idle timeout for workstations in seconds"
  type        = number
  default     = 3600 # 1 hour
}

variable "workstation_running_timeout" {
  description = "Running timeout for workstations in seconds"
  type        = number
  default     = 43200 # 12 hours
}

# Network Configuration
variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "default"
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "default"
}

variable "enable_private_ip" {
  description = "Enable private IP for workstations"
  type        = bool
  default     = true
}

# Migration Team Configuration
variable "migration_team_members" {
  description = "List of email addresses for migration team members"
  type        = list(string)
  default     = []
}

# Artifact Registry Configuration
variable "artifact_registry_repo_name" {
  description = "Name for the Artifact Registry repository"
  type        = string
  default     = "db-migration-images"
}

# Cloud Build Configuration
variable "enable_cloud_build" {
  description = "Enable Cloud Build for CI/CD pipeline"
  type        = bool
  default     = true
}

variable "cloud_build_trigger_name" {
  description = "Name for the Cloud Build trigger"
  type        = string
  default     = "db-migration-pipeline"
}

# Monitoring and Logging
variable "enable_audit_logging" {
  description = "Enable audit logging for security compliance"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
}

# Security Configuration
variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access workstations"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for container security"
  type        = bool
  default     = false
}

# Tags and Labels
variable "labels" {
  description = "Common labels to be applied to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    project     = "db-migration"
    managed-by  = "terraform"
  }
}

# Backup Configuration
variable "backup_retention_days" {
  description = "Number of days to retain database backups"
  type        = number
  default     = 7
}

variable "backup_start_time" {
  description = "Backup start time in UTC (HH:MM format)"
  type        = string
  default     = "03:00"
}