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
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-central2", "europe-north1", "europe-southwest1", "europe-west1", 
      "europe-west2", "europe-west3", "europe-west4", "europe-west6", "europe-west8", 
      "europe-west9", "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", 
      "asia-northeast3", "asia-south1", "asia-south2", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Database Configuration
variable "db_tier" {
  description = "The machine type for the Cloud SQL instance"
  type        = string
  default     = "db-f1-micro"
  
  validation {
    condition = contains([
      "db-f1-micro", "db-g1-small", "db-n1-standard-1", "db-n1-standard-2", 
      "db-n1-standard-4", "db-n1-standard-8", "db-n1-standard-16"
    ], var.db_tier)
    error_message = "Database tier must be a valid Cloud SQL machine type."
  }
}

variable "db_version" {
  description = "The PostgreSQL version for Cloud SQL"
  type        = string
  default     = "POSTGRES_15"
  
  validation {
    condition = contains([
      "POSTGRES_12", "POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16"
    ], var.db_version)
    error_message = "Database version must be a supported PostgreSQL version."
  }
}

variable "enable_backup" {
  description = "Enable automated backups for Cloud SQL"
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "The start time for automated backups (HH:MM format)"
  type        = string
  default     = "03:00"
  
  validation {
    condition     = can(regex("^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Backup start time must be in HH:MM format (24-hour)."
  }
}

# Cloud Functions Configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = number
  default     = 256
  
  validation {
    condition     = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 MB and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (in seconds)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "python_runtime" {
  description = "Python runtime version for Cloud Functions"
  type        = string
  default     = "python311"
  
  validation {
    condition = contains([
      "python37", "python38", "python39", "python310", "python311", "python312"
    ], var.python_runtime)
    error_message = "Python runtime must be a supported version."
  }
}

# Workflow Configuration
variable "workflow_location" {
  description = "Location for Cloud Workflows (must be same as region)"
  type        = string
  default     = ""
}

# Networking Configuration
variable "enable_private_services" {
  description = "Enable private services access for Cloud SQL"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_deletion_protection" {
  description = "Enable deletion protection for Cloud SQL instances"
  type        = bool
  default     = false
}

# Monitoring and Logging
variable "enable_monitoring" {
  description = "Enable advanced monitoring and alerting"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain Cloud Function logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Resource Naming
variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains([
      "dev", "development", "staging", "stage", "prod", "production", "test"
    ], var.environment)
    error_message = "Environment must be one of: dev, development, staging, stage, prod, production, test."
  }
}

# Tags and Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "intelligent-business-process-automation"
    terraform   = "true"
    environment = "dev"
  }
}

# API Configuration
variable "enable_apis" {
  description = "List of APIs to enable for the project"
  type        = list(string)
  default = [
    "aiplatform.googleapis.com",
    "workflows.googleapis.com", 
    "sqladmin.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "servicenetworking.googleapis.com"
  ]
}