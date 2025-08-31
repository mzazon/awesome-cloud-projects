# Core project configuration variables
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
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# App Engine configuration variables
variable "app_engine_location" {
  description = "The location for the App Engine application (must be a valid App Engine region)"
  type        = string
  default     = "us-central"
  validation {
    condition = contains([
      "us-central", "us-east1", "us-east4", "us-west2", "us-west3", "us-west4",
      "europe-west", "europe-west2", "europe-west3", "europe-west6",
      "asia-east2", "asia-northeast1", "asia-southeast2", "australia-southeast1"
    ], var.app_engine_location)
    error_message = "App Engine location must be a valid App Engine region."
  }
}

variable "app_engine_runtime" {
  description = "The runtime for the App Engine application"
  type        = string
  default     = "python39"
  validation {
    condition = contains([
      "python37", "python38", "python39", "python310", "python311"
    ], var.app_engine_runtime)
    error_message = "Runtime must be a supported Python version."
  }
}

# Cloud SQL configuration variables
variable "database_version" {
  description = "The PostgreSQL version for Cloud SQL instance"
  type        = string
  default     = "POSTGRES_17"
  validation {
    condition = contains([
      "POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17"
    ], var.database_version)
    error_message = "Database version must be a supported PostgreSQL version."
  }
}

variable "database_tier" {
  description = "The machine type for the Cloud SQL instance"
  type        = string
  default     = "db-f1-micro"
  validation {
    condition = contains([
      "db-f1-micro", "db-g1-small", "db-n1-standard-1", "db-n1-standard-2",
      "db-n1-standard-4", "db-n1-standard-8", "db-n1-standard-16"
    ], var.database_tier)
    error_message = "Database tier must be a valid Cloud SQL machine type."
  }
}

variable "database_storage_size" {
  description = "The size of the Cloud SQL instance storage in GB"
  type        = number
  default     = 10
  validation {
    condition     = var.database_storage_size >= 10 && var.database_storage_size <= 65536
    error_message = "Database storage size must be between 10 and 65536 GB."
  }
}

variable "database_storage_type" {
  description = "The storage type for the Cloud SQL instance"
  type        = string
  default     = "PD_SSD"
  validation {
    condition = contains([
      "PD_SSD", "PD_HDD"
    ], var.database_storage_type)
    error_message = "Database storage type must be PD_SSD or PD_HDD."
  }
}

variable "database_backup_enabled" {
  description = "Whether to enable automated backups for the Cloud SQL instance"
  type        = bool
  default     = true
}

variable "database_backup_time" {
  description = "The start time for daily automated backups (HH:MM format in UTC)"
  type        = string
  default     = "02:00"
  validation {
    condition     = can(regex("^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$", var.database_backup_time))
    error_message = "Database backup time must be in HH:MM format (24-hour)."
  }
}

# Database configuration variables
variable "database_name" {
  description = "The name of the application database"
  type        = string
  default     = "expenses"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.database_name))
    error_message = "Database name must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "database_user" {
  description = "The name of the application database user"
  type        = string
  default     = "expense_user"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.database_user))
    error_message = "Database user must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "database_password" {
  description = "The password for the database user (if not provided, will be auto-generated)"
  type        = string
  default     = ""
  sensitive   = true
}

# Network security variables
variable "authorized_networks" {
  description = "List of authorized networks for Cloud SQL access (CIDR blocks)"
  type = list(object({
    name  = string
    value = string
  }))
  default = [
    {
      name  = "all-networks"
      value = "0.0.0.0/0"
    }
  ]
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection for the Cloud SQL instance"
  type        = bool
  default     = false
}

# Application configuration variables
variable "app_environment_variables" {
  description = "Environment variables for the App Engine application"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "app_scaling_settings" {
  description = "Automatic scaling settings for the App Engine application"
  type = object({
    min_instances           = number
    max_instances          = number
    target_cpu_utilization = number
  })
  default = {
    min_instances           = 0
    max_instances          = 2
    target_cpu_utilization = 0.6
  }
  validation {
    condition = (
      var.app_scaling_settings.min_instances >= 0 &&
      var.app_scaling_settings.max_instances >= var.app_scaling_settings.min_instances &&
      var.app_scaling_settings.target_cpu_utilization > 0 &&
      var.app_scaling_settings.target_cpu_utilization <= 1
    )
    error_message = "Invalid scaling settings: min_instances >= 0, max_instances >= min_instances, target_cpu_utilization between 0 and 1."
  }
}

# Resource naming and tagging variables
variable "resource_prefix" {
  description = "Prefix to add to all resource names for identification"
  type        = string
  default     = "expense-tracker"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    application = "expense-tracker"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# API enablement variable
variable "enable_apis" {
  description = "List of APIs to enable for this project"
  type        = list(string)
  default = [
    "appengine.googleapis.com",
    "sql.googleapis.com",
    "sqladmin.googleapis.com",
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com"
  ]
}