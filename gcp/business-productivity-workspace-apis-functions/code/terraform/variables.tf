# Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region where resources will be created"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

# Cloud SQL Configuration
variable "database_name" {
  description = "Name of the Cloud SQL database for productivity analytics"
  type        = string
  default     = "productivity_db"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.database_name))
    error_message = "Database name must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "db_instance_tier" {
  description = "The machine tier for the Cloud SQL instance"
  type        = string
  default     = "db-f1-micro"
  validation {
    condition = contains([
      "db-f1-micro", "db-g1-small", "db-n1-standard-1", "db-n1-standard-2"
    ], var.db_instance_tier)
    error_message = "Database tier must be a valid Cloud SQL tier."
  }
}

variable "db_storage_size" {
  description = "The storage size for the Cloud SQL instance in GB"
  type        = number
  default     = 20
  validation {
    condition     = var.db_storage_size >= 10 && var.db_storage_size <= 1000
    error_message = "Database storage size must be between 10 and 1000 GB."
  }
}

# Cloud Functions Configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 512
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = ""
  validation {
    condition     = length(var.resource_prefix) <= 10
    error_message = "Resource prefix must be 10 characters or less."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition = contains([
      "dev", "development", "staging", "stage", "prod", "production"
    ], var.environment)
    error_message = "Environment must be one of: dev, development, staging, stage, prod, production."
  }
}

# Google Workspace API Configuration
variable "workspace_domain" {
  description = "Google Workspace domain for API access"
  type        = string
  default     = ""
  validation {
    condition     = var.workspace_domain == "" || can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$", var.workspace_domain))
    error_message = "Workspace domain must be a valid domain name or empty."
  }
}

# Cloud Scheduler Configuration
variable "scheduler_timezone" {
  description = "Timezone for Cloud Scheduler jobs"
  type        = string
  default     = "America/New_York"
}

variable "enable_scheduler_jobs" {
  description = "Whether to create Cloud Scheduler jobs for automation"
  type        = bool
  default     = true
}

# Monitoring and Logging Configuration
variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring for the solution"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653 (10 years)."
  }
}

# Security Configuration
variable "enable_private_ip" {
  description = "Whether to use private IP for Cloud SQL instance"
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

# Cost Management
variable "enable_backup" {
  description = "Whether to enable automated backups for Cloud SQL"
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "Start time for automated backups (HH:MM format)"
  type        = string
  default     = "03:00"
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Backup start time must be in HH:MM format (24-hour)."
  }
}

# Common Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "productivity-automation"
    managed-by  = "terraform"
    component   = "workspace-integration"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z]([a-z0-9_-]{0,62}[a-z0-9])?$", k))])
    error_message = "Label keys must be lowercase, start with a letter, and contain only letters, numbers, hyphens, and underscores."
  }
}