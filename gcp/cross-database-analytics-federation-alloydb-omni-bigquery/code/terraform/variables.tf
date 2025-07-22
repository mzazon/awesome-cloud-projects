# Variables for Cross-Database Analytics Federation with AlloyDB Omni and BigQuery
# This file defines all configurable parameters for the federated analytics platform

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
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
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

variable "environment" {
  description = "Environment name for resource labeling (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains([
      "dev", "development", "staging", "stage", "prod", "production", "test", "testing"
    ], var.environment)
    error_message = "Environment must be one of: dev, development, staging, stage, prod, production, test, testing."
  }
}

variable "db_password" {
  description = "Password for the AlloyDB Omni simulation Cloud SQL instance"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Database password must be at least 8 characters long."
  }
  
  validation {
    condition     = can(regex("^[A-Za-z0-9!@#$%^&*()_+-=\\[\\]{}|;:,.<>?]+$", var.db_password))
    error_message = "Database password contains invalid characters."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs (set to false if APIs are already enabled)"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources like Cloud SQL instances"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain Cloud SQL backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

variable "alloydb_tier" {
  description = "Cloud SQL instance tier for AlloyDB Omni simulation"
  type        = string
  default     = "db-custom-2-8192"  # 2 vCPUs, 8GB RAM
  
  validation {
    condition = contains([
      "db-custom-1-3840", "db-custom-2-8192", "db-custom-4-16384", 
      "db-custom-8-32768", "db-custom-16-65536"
    ], var.alloydb_tier)
    error_message = "AlloyDB tier must be a valid Cloud SQL custom machine type."
  }
}

variable "alloydb_disk_size" {
  description = "Disk size in GB for the AlloyDB Omni simulation instance"
  type        = number
  default     = 20
  
  validation {
    condition     = var.alloydb_disk_size >= 10 && var.alloydb_disk_size <= 30720
    error_message = "Disk size must be between 10 GB and 30,720 GB."
  }
}

variable "alloydb_disk_type" {
  description = "Disk type for the AlloyDB Omni simulation instance"
  type        = string
  default     = "PD_SSD"
  
  validation {
    condition = contains([
      "PD_SSD", "PD_HDD"
    ], var.alloydb_disk_type)
    error_message = "Disk type must be either PD_SSD or PD_HDD."
  }
}

variable "bigquery_location" {
  description = "BigQuery dataset location (can be different from compute region for multi-regional datasets)"
  type        = string
  default     = ""  # Empty string means use the same as var.region
  
  validation {
    condition = var.bigquery_location == "" || contains([
      "US", "EU", "asia-northeast1", "asia-southeast1", "australia-southeast1",
      "europe-west1", "europe-west2", "europe-west4", "europe-west6",
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid BigQuery region or multi-region."
  }
}

variable "storage_class" {
  description = "Default storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_storage_versioning" {
  description = "Enable versioning for Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "cloud_function_memory" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 256
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.cloud_function_memory)
    error_message = "Cloud Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "cloud_function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.cloud_function_timeout >= 1 && var.cloud_function_timeout <= 540
    error_message = "Cloud Function timeout must be between 1 and 540 seconds."
  }
}

variable "metadata_sync_schedule" {
  description = "Cron schedule for automated metadata synchronization (in cron format)"
  type        = string
  default     = "0 */6 * * *"  # Every 6 hours
  
  validation {
    condition     = length(split(" ", var.metadata_sync_schedule)) == 5
    error_message = "Metadata sync schedule must be in valid cron format (5 fields)."
  }
}

variable "authorized_networks" {
  description = "List of authorized networks for Cloud SQL instance access"
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

variable "database_flags" {
  description = "Database flags for Cloud SQL PostgreSQL instance optimization"
  type = map(string)
  default = {
    max_connections                = "200"
    shared_preload_libraries      = "pg_stat_statements"
    log_statement                 = "all"
    log_min_duration_statement    = "1000"  # Log queries taking more than 1 second
  }
}

variable "enable_high_availability" {
  description = "Enable high availability (regional) for Cloud SQL instance"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "enable_dataplex_discovery" {
  description = "Enable automatic data discovery in Dataplex"
  type        = bool
  default     = true
}

variable "dataplex_zone_type" {
  description = "Type of Dataplex zone to create (RAW or CURATED)"
  type        = string
  default     = "RAW"
  
  validation {
    condition = contains([
      "RAW", "CURATED"
    ], var.dataplex_zone_type)
    error_message = "Dataplex zone type must be either RAW or CURATED."
  }
}

variable "create_sample_data" {
  description = "Whether to create sample data for testing federation capabilities"
  type        = bool
  default     = true
}

variable "function_source_bucket_name" {
  description = "Name for the Cloud Function source code bucket (leave empty for auto-generated name)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.function_source_bucket_name == "" || can(regex("^[a-z0-9._-]*$", var.function_source_bucket_name))
    error_message = "Function source bucket name must contain only lowercase letters, numbers, dots, underscores, and hyphens."
  }
}

variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access for Cloud Storage buckets"
  type        = bool
  default     = true
}