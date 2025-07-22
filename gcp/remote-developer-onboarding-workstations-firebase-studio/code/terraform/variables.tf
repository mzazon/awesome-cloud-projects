# Variable Definitions
# Remote Developer Onboarding with Cloud Workstations and Firebase Studio

# Project Configuration
variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3",
      "asia-east1", "asia-southeast1", "asia-northeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Workstation Configuration
variable "cluster_name" {
  description = "Name of the workstation cluster"
  type        = string
  default     = "developer-workstations"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{3,62}[a-z0-9]$", var.cluster_name))
    error_message = "Cluster name must be 5-63 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "workstation_config_name" {
  description = "Name of the workstation configuration"
  type        = string
  default     = "fullstack-dev-config"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{3,62}[a-z0-9]$", var.workstation_config_name))
    error_message = "Configuration name must be 5-63 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "machine_type" {
  description = "Machine type for workstation instances"
  type        = string
  default     = "e2-standard-4"
  
  validation {
    condition = contains([
      "e2-standard-2", "e2-standard-4", "e2-standard-8",
      "n2-standard-2", "n2-standard-4", "n2-standard-8",
      "c2-standard-4", "c2-standard-8"
    ], var.machine_type)
    error_message = "Machine type must be a valid Compute Engine machine type."
  }
}

variable "persistent_disk_size_gb" {
  description = "Size of the persistent disk in GB for each workstation"
  type        = number
  default     = 200
  
  validation {
    condition     = var.persistent_disk_size_gb >= 100 && var.persistent_disk_size_gb <= 2000
    error_message = "Persistent disk size must be between 100 and 2000 GB."
  }
}

variable "idle_timeout_seconds" {
  description = "Idle timeout in seconds before workstation shuts down"
  type        = number
  default     = 7200
  
  validation {
    condition     = var.idle_timeout_seconds >= 300 && var.idle_timeout_seconds <= 28800
    error_message = "Idle timeout must be between 5 minutes (300s) and 8 hours (28800s)."
  }
}

variable "workstation_container_image" {
  description = "Container image to use for workstations"
  type        = string
  default     = "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"
  
  validation {
    condition     = can(regex("^[a-z0-9.-]+/[a-z0-9.-]+/[a-z0-9.-]+/[a-z0-9.-]+:[a-z0-9.-]+$", var.workstation_container_image))
    error_message = "Container image must be a valid container registry URL."
  }
}

# Source Repository Configuration
variable "source_repo_name" {
  description = "Name of the Cloud Source Repository for team templates"
  type        = string
  default     = "team-templates"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_.-]{0,99}$", var.source_repo_name))
    error_message = "Repository name must start with a letter and be 1-100 characters of letters, numbers, underscores, periods, and hyphens."
  }
}

# IAM Configuration
variable "developer_users" {
  description = "List of developer email addresses to grant workstation access"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.developer_users : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All developer users must be valid email addresses."
  }
}

variable "admin_users" {
  description = "List of admin email addresses to grant full administrative access"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.admin_users : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All admin users must be valid email addresses."
  }
}

# Network Configuration
variable "network_name" {
  description = "Name of the VPC network for workstations"
  type        = string
  default     = "default"
}

variable "subnet_name" {
  description = "Name of the subnet for workstations"
  type        = string
  default     = "default"
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint for workstation cluster"
  type        = bool
  default     = true
}

# Firebase Configuration
variable "firebase_location" {
  description = "Firebase project location"
  type        = string
  default     = "us-central"
  
  validation {
    condition = contains([
      "us-central", "us-east1", "us-west2", "us-west3", "us-west4",
      "europe-west", "europe-west2", "europe-west3",
      "asia-east2", "asia-northeast1", "asia-southeast1"
    ], var.firebase_location)
    error_message = "Firebase location must be a valid Firebase region."
  }
}

# Budget and Cost Control
variable "budget_amount" {
  description = "Monthly budget amount in USD for cost monitoring"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "budget_alert_thresholds" {
  description = "Budget alert thresholds as percentages"
  type        = list(number)
  default     = [75, 90, 100]
  
  validation {
    condition = alltrue([
      for threshold in var.budget_alert_thresholds : threshold > 0 && threshold <= 100
    ])
    error_message = "Budget thresholds must be between 1 and 100."
  }
}

# Monitoring Configuration
variable "enable_audit_logging" {
  description = "Enable audit logging for workstations"
  type        = bool
  default     = true
}

variable "enable_monitoring_dashboard" {
  description = "Enable monitoring dashboard creation"
  type        = bool
  default     = true
}

# Resource Labels
variable "environment" {
  description = "Environment label for resources"
  type        = string
  default     = "development"
  
  validation {
    condition = contains([
      "development", "staging", "production", "testing"
    ], var.environment)
    error_message = "Environment must be one of: development, staging, production, testing."
  }
}

variable "team" {
  description = "Team label for resources"
  type        = string
  default     = "engineering"
  
  validation {
    condition     = length(var.team) > 0 && length(var.team) <= 50
    error_message = "Team name must be 1-50 characters."
  }
}

variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with a letter and be 1-63 characters of lowercase letters, numbers, underscores, and hyphens."
  }
}