# Project configuration variables
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for resource deployment"
  type        = string
  default     = "us-central1-a"
}

# Resource naming and configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "application_name" {
  description = "Name of the application for resource naming"
  type        = string
  default     = "route-optimizer"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.application_name))
    error_message = "Application name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Cloud SQL configuration
variable "sql_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-f1-micro"
  
  validation {
    condition = contains([
      "db-f1-micro", "db-g1-small", "db-n1-standard-1", "db-n1-standard-2",
      "db-n1-standard-4", "db-n1-standard-8", "db-n1-standard-16"
    ], var.sql_tier)
    error_message = "SQL tier must be a valid Cloud SQL machine type."
  }
}

variable "sql_disk_size" {
  description = "Cloud SQL disk size in GB"
  type        = number
  default     = 20
  
  validation {
    condition     = var.sql_disk_size >= 10 && var.sql_disk_size <= 30720
    error_message = "SQL disk size must be between 10 and 30720 GB."
  }
}

variable "sql_database_version" {
  description = "PostgreSQL version for Cloud SQL"
  type        = string
  default     = "POSTGRES_14"
  
  validation {
    condition = contains([
      "POSTGRES_11", "POSTGRES_12", "POSTGRES_13", "POSTGRES_14", "POSTGRES_15"
    ], var.sql_database_version)
    error_message = "Database version must be a supported PostgreSQL version."
  }
}

variable "sql_backup_enabled" {
  description = "Enable automated backups for Cloud SQL"
  type        = bool
  default     = true
}

variable "sql_ha_enabled" {
  description = "Enable high availability for Cloud SQL"
  type        = bool
  default     = false
}

# Cloud Run configuration
variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "1"
  
  validation {
    condition = contains([
      "0.08", "0.17", "0.25", "0.33", "0.5", "0.58", "0.67", "0.75", "0.83", "1", "2", "4", "6", "8"
    ], var.cloud_run_cpu)
    error_message = "CPU allocation must be a valid Cloud Run CPU value."
  }
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "1Gi"
  
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.cloud_run_memory))
    error_message = "Memory allocation must be in Mi or Gi format (e.g., 512Mi, 1Gi)."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 0
  
  validation {
    condition     = var.cloud_run_min_instances >= 0 && var.cloud_run_min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "cloud_run_timeout" {
  description = "Request timeout for Cloud Run service in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.cloud_run_timeout >= 1 && var.cloud_run_timeout <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

variable "cloud_run_concurrency" {
  description = "Maximum concurrent requests per Cloud Run instance"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cloud_run_concurrency >= 1 && var.cloud_run_concurrency <= 1000
    error_message = "Concurrency must be between 1 and 1000."
  }
}

# Google Maps API configuration
variable "maps_api_key" {
  description = "Google Maps API key for Routes API access"
  type        = string
  default     = ""
  sensitive   = true
  
  validation {
    condition     = var.maps_api_key != ""
    error_message = "Maps API key is required for route optimization functionality."
  }
}

# Pub/Sub configuration
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub subscription"
  type        = string
  default     = "604800s" # 7 days
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., 604800s)."
  }
}

variable "pubsub_ack_deadline" {
  description = "Acknowledgment deadline for Pub/Sub subscription in seconds"
  type        = number
  default     = 600
  
  validation {
    condition     = var.pubsub_ack_deadline >= 10 && var.pubsub_ack_deadline <= 600
    error_message = "Ack deadline must be between 10 and 600 seconds."
  }
}

# Cloud Function configuration
variable "cloud_function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 256
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.cloud_function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "cloud_function_timeout" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.cloud_function_timeout >= 1 && var.cloud_function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

# Networking configuration
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
  default = []
}

# Monitoring and logging
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Security configuration
variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for container images"
  type        = bool
  default     = false
}

variable "enable_vpc_sc" {
  description = "Enable VPC Service Controls"
  type        = bool
  default     = false
}

# Tags and labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "route-optimization"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}