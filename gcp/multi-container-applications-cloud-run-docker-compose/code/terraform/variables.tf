# Input variables for the multi-container Cloud Run application
# These variables allow customization of the deployment for different environments

# Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1, europe-west1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for single-zone resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone (e.g., us-central1-a, europe-west1-b)."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and naming"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Service Configuration
variable "service_name" {
  description = "Name for the Cloud Run service"
  type        = string
  default     = "multi-container-app"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.service_name))
    error_message = "Service name must start with a letter, be 1-63 characters, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "container_images" {
  description = "Container images for the multi-container service"
  type = object({
    frontend = string
    backend  = string
    proxy    = string
  })
  default = {
    frontend = "gcr.io/cloudrun/hello"
    backend  = "gcr.io/cloudrun/hello"
    proxy    = "nginx:alpine"
  }
}

# Database Configuration
variable "database_instance_name" {
  description = "Name for the Cloud SQL PostgreSQL instance"
  type        = string
  default     = "multiapp-postgres"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.database_instance_name))
    error_message = "Database instance name must start with a letter, be 1-63 characters, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "database_tier" {
  description = "Machine type for the Cloud SQL instance"
  type        = string
  default     = "db-f1-micro"
  validation {
    condition = contains([
      "db-f1-micro", "db-g1-small", "db-n1-standard-1", "db-n1-standard-2",
      "db-n1-standard-4", "db-n1-standard-8", "db-n1-standard-16",
      "db-n1-highmem-2", "db-n1-highmem-4", "db-n1-highmem-8"
    ], var.database_tier)
    error_message = "Database tier must be a valid Cloud SQL machine type."
  }
}

variable "database_disk_size" {
  description = "Size of the database disk in GB"
  type        = number
  default     = 10
  validation {
    condition     = var.database_disk_size >= 10 && var.database_disk_size <= 65536
    error_message = "Database disk size must be between 10 and 65536 GB."
  }
}

variable "database_name" {
  description = "Name of the application database"
  type        = string
  default     = "appdb"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "Database name must start with a letter and contain only letters, numbers, and underscores (1-63 characters)."
  }
}

variable "database_user" {
  description = "Username for the application database user"
  type        = string
  default     = "appuser"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_user))
    error_message = "Database user must start with a letter and contain only letters, numbers, and underscores (1-63 characters)."
  }
}

# Artifact Registry Configuration
variable "repository_name" {
  description = "Name for the Artifact Registry repository"
  type        = string
  default     = "multiapp-repo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.repository_name))
    error_message = "Repository name must start with a letter, be 1-63 characters, and contain only lowercase letters, numbers, and hyphens."
  }
}

# Cloud Run Service Configuration
variable "cpu_limit" {
  description = "CPU limit for each container (in millicores)"
  type        = string
  default     = "1000m"
  validation {
    condition     = can(regex("^[0-9]+m?$", var.cpu_limit))
    error_message = "CPU limit must be a number optionally followed by 'm' for millicores (e.g., 1000m, 2000m)."
  }
}

variable "memory_limit" {
  description = "Memory limit for each container"
  type        = string
  default     = "512Mi"
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.memory_limit))
    error_message = "Memory limit must be a number followed by Mi or Gi (e.g., 512Mi, 1Gi)."
  }
}

variable "max_scale" {
  description = "Maximum number of container instances"
  type        = number
  default     = 10
  validation {
    condition     = var.max_scale >= 1 && var.max_scale <= 1000
    error_message = "Max scale must be between 1 and 1000."
  }
}

variable "min_scale" {
  description = "Minimum number of container instances (0 for scale-to-zero)"
  type        = number
  default     = 0
  validation {
    condition     = var.min_scale >= 0 && var.min_scale <= var.max_scale
    error_message = "Min scale must be 0 or greater and not exceed max scale."
  }
}

# Security Configuration
variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the Cloud Run service"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection for the Cloud SQL instance"
  type        = bool
  default     = false
}

# Networking Configuration
variable "vpc_connector_name" {
  description = "Name of the VPC connector for private networking (optional)"
  type        = string
  default     = ""
}

variable "authorized_networks" {
  description = "List of authorized networks for Cloud SQL access"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

# Labels and Tags
variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens (1-63 characters)."
  }
}