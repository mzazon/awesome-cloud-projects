# Project Configuration
variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
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
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3",
      "asia-east1", "asia-southeast1", "asia-northeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports all required services."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "intelligent-search"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
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

# Cloud SQL Configuration
variable "db_instance_tier" {
  description = "Cloud SQL instance machine type tier"
  type        = string
  default     = "db-n1-standard-2"
  
  validation {
    condition = can(regex("^db-(n1|e2|custom)-(standard|highmem|highcpu)-.*", var.db_instance_tier))
    error_message = "Database tier must be a valid Cloud SQL machine type."
  }
}

variable "db_storage_size" {
  description = "Cloud SQL storage size in GB"
  type        = number
  default     = 20
  
  validation {
    condition     = var.db_storage_size >= 10 && var.db_storage_size <= 65536
    error_message = "Database storage size must be between 10 GB and 65536 GB."
  }
}

variable "db_storage_type" {
  description = "Cloud SQL storage type (PD_SSD or PD_HDD)"
  type        = string
  default     = "PD_SSD"
  
  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.db_storage_type)
    error_message = "Storage type must be either PD_SSD or PD_HDD."
  }
}

variable "db_backup_start_time" {
  description = "Backup start time in 24-hour format (HH:MM)"
  type        = string
  default     = "03:00"
  
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.db_backup_start_time))
    error_message = "Backup start time must be in HH:MM format."
  }
}

variable "db_maintenance_window_day" {
  description = "Day of week for maintenance window (1=Monday, 7=Sunday)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.db_maintenance_window_day >= 1 && var.db_maintenance_window_day <= 7
    error_message = "Maintenance window day must be between 1 (Monday) and 7 (Sunday)."
  }
}

variable "db_maintenance_window_hour" {
  description = "Hour of day for maintenance window (0-23)"
  type        = number
  default     = 4
  
  validation {
    condition     = var.db_maintenance_window_hour >= 0 && var.db_maintenance_window_hour <= 23
    error_message = "Maintenance window hour must be between 0 and 23."
  }
}

variable "enable_binary_log" {
  description = "Enable binary logging for Cloud SQL instance"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection for Cloud SQL instance"
  type        = bool
  default     = true
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
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, or 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 100
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Maximum instances must be between 1 and 3000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Minimum instances must be between 0 and 1000."
  }
}

# Cloud Storage Configuration
variable "storage_class" {
  description = "Cloud Storage bucket storage class"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage"
  type        = bool
  default     = true
}

# Network Configuration
variable "enable_private_ip" {
  description = "Enable private IP for Cloud SQL instance"
  type        = bool
  default     = false
}

variable "authorized_networks" {
  description = "List of authorized networks for Cloud SQL access"
  type = list(object({
    name  = string
    value = string
  }))
  default = [{
    name  = "allow-all"
    value = "0.0.0.0/0"
  }]
}

# Vertex AI Configuration
variable "vertex_ai_location" {
  description = "Location for Vertex AI resources (must support text-embedding-005)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west4",
      "europe-west1", "europe-west4", "asia-southeast1"
    ], var.vertex_ai_location)
    error_message = "Vertex AI location must support the text-embedding-005 model."
  }
}

# Monitoring and Logging
variable "enable_logging" {
  description = "Enable Cloud Logging for functions"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Log level for Cloud Functions"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, or CRITICAL."
  }
}

# Security Configuration
variable "enable_ssl" {
  description = "Require SSL for Cloud SQL connections"
  type        = bool
  default     = true
}

variable "enable_binary_log_retention" {
  description = "Number of days to retain binary logs"
  type        = number
  default     = 7
  
  validation {
    condition     = var.enable_binary_log_retention >= 1 && var.enable_binary_log_retention <= 30
    error_message = "Binary log retention must be between 1 and 30 days."
  }
}

# Sample Data Configuration
variable "load_sample_data" {
  description = "Whether to load sample product data during deployment"
  type        = bool
  default     = true
}

# Cost Optimization
variable "enable_auto_increase" {
  description = "Enable automatic storage increase for Cloud SQL"
  type        = bool
  default     = true
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for Cloud SQL"
  type        = bool
  default     = true
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "intelligent-product-search"
    environment = "dev"
    managed-by  = "terraform"
    use-case    = "semantic-search"
  }
}