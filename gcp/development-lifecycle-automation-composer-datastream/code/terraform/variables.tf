# Variables for Development Lifecycle Automation Infrastructure
# Cloud Composer, Datastream, Artifact Registry, and Cloud Workflows

# Core Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports Cloud Composer."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "devops-automation"
  validation {
    condition     = length(var.resource_prefix) <= 20
    error_message = "Resource prefix must be 20 characters or less."
  }
}

# Cloud Composer Configuration
variable "composer_env_name" {
  description = "Name of the Cloud Composer environment"
  type        = string
  default     = "intelligent-devops"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.composer_env_name))
    error_message = "Composer environment name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "composer_node_count" {
  description = "Number of nodes in the Cloud Composer environment"
  type        = number
  default     = 3
  validation {
    condition     = var.composer_node_count >= 3 && var.composer_node_count <= 10
    error_message = "Composer node count must be between 3 and 10."
  }
}

variable "composer_machine_type" {
  description = "Machine type for Cloud Composer nodes"
  type        = string
  default     = "n1-standard-2"
  validation {
    condition = contains([
      "n1-standard-1", "n1-standard-2", "n1-standard-4",
      "n2-standard-2", "n2-standard-4", "e2-medium", "e2-standard-2"
    ], var.composer_machine_type)
    error_message = "Invalid machine type for Cloud Composer."
  }
}

variable "composer_disk_size" {
  description = "Disk size in GB for Cloud Composer nodes"
  type        = number
  default     = 30
  validation {
    condition     = var.composer_disk_size >= 20 && var.composer_disk_size <= 100
    error_message = "Composer disk size must be between 20 and 100 GB."
  }
}

variable "airflow_version" {
  description = "Apache Airflow version for Cloud Composer"
  type        = string
  default     = "composer-3-airflow-3"
  validation {
    condition     = can(regex("^composer-[0-9]+-airflow-[0-9]+", var.airflow_version))
    error_message = "Airflow version must follow the pattern 'composer-X-airflow-Y'."
  }
}

# Database Configuration
variable "database_tier" {
  description = "Cloud SQL instance tier for development database"
  type        = string
  default     = "db-f1-micro"
  validation {
    condition = contains([
      "db-f1-micro", "db-g1-small", "db-n1-standard-1", "db-n1-standard-2"
    ], var.database_tier)
    error_message = "Invalid database tier."
  }
}

variable "database_version" {
  description = "PostgreSQL version for the development database"
  type        = string
  default     = "POSTGRES_15"
  validation {
    condition = contains([
      "POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16"
    ], var.database_version)
    error_message = "Invalid PostgreSQL version."
  }
}

variable "database_name" {
  description = "Name of the application database"
  type        = string
  default     = "app_development"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.database_name))
    error_message = "Database name must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

# Storage Configuration
variable "storage_class" {
  description = "Storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Invalid storage class."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on storage buckets for audit trail"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_private_ip" {
  description = "Enable private IP for Cloud Composer environment"
  type        = bool
  default     = true
}

variable "enable_ssl" {
  description = "Enable SSL for database connections"
  type        = bool
  default     = true
}

variable "authorized_networks" {
  description = "List of authorized networks for database access"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

# Monitoring and Alerting Configuration
variable "enable_monitoring" {
  description = "Enable monitoring and alerting for the infrastructure"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

# Cost Management
variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain database backups"
  type        = number
  default     = 7
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

# Feature Flags
variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for container security"
  type        = bool
  default     = true
}

variable "enable_vulnerability_scanning" {
  description = "Enable vulnerability scanning for container images"
  type        = bool
  default     = true
}

variable "enable_audit_logging" {
  description = "Enable audit logging for compliance"
  type        = bool
  default     = true
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    project     = "devops-automation"
    managed-by  = "terraform"
  }
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Maximum of 64 labels allowed per resource."
  }
}