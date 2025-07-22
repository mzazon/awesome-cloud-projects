# Project and Location Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0 && can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, contain only lowercase letters, numbers and hyphens, and end with letter or number."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "pipeline"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name (used for labeling)"
  type        = string
  default     = "development"
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# GKE Cluster Configuration
variable "dev_cluster_config" {
  description = "Configuration for the development GKE cluster"
  type = object({
    node_count    = number
    machine_type  = string
    disk_size_gb  = number
    disk_type     = string
  })
  default = {
    node_count    = 2
    machine_type  = "e2-medium"
    disk_size_gb  = 20
    disk_type     = "pd-standard"
  }
}

variable "staging_cluster_config" {
  description = "Configuration for the staging GKE cluster"
  type = object({
    node_count    = number
    machine_type  = string
    disk_size_gb  = number
    disk_type     = string
  })
  default = {
    node_count    = 2
    machine_type  = "e2-medium"
    disk_size_gb  = 20
    disk_type     = "pd-standard"
  }
}

variable "prod_cluster_config" {
  description = "Configuration for the production GKE cluster"
  type = object({
    node_count    = number
    machine_type  = string
    disk_size_gb  = number
    disk_type     = string
  })
  default = {
    node_count    = 3
    machine_type  = "e2-standard-2"
    disk_size_gb  = 30
    disk_type     = "pd-ssd"
  }
}

# Artifact Registry Configuration
variable "artifact_registry_format" {
  description = "Format of the Artifact Registry repository"
  type        = string
  default     = "DOCKER"
  validation {
    condition = contains(["DOCKER", "MAVEN", "NPM", "PYTHON"], var.artifact_registry_format)
    error_message = "Artifact registry format must be one of: DOCKER, MAVEN, NPM, PYTHON."
  }
}

# Cloud Deploy Configuration
variable "require_approval_prod" {
  description = "Whether to require approval for production deployments"
  type        = bool
  default     = true
}

variable "enable_verification" {
  description = "Whether to enable verification steps in the deployment pipeline"
  type        = bool
  default     = true
}

variable "app_name" {
  description = "Name of the application being deployed"
  type        = string
  default     = "sample-app"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.app_name))
    error_message = "App name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "github_owner" {
  description = "GitHub username or organization name"
  type        = string
  default     = "your-github-username"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "your-repo-name"
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring resources"
  type        = bool
  default     = true
}

variable "notification_channels" {
  description = "List of notification channel IDs for alerting"
  type        = list(string)
  default     = []
}

# Network Configuration
variable "enable_network_policy" {
  description = "Whether to enable network policy on GKE clusters"
  type        = bool
  default     = true
}

variable "enable_private_nodes" {
  description = "Whether to enable private nodes on GKE clusters"
  type        = bool
  default     = false
}

# Security Configuration
variable "enable_shielded_nodes" {
  description = "Whether to enable shielded nodes on GKE clusters"
  type        = bool
  default     = true
}

variable "enable_workload_identity" {
  description = "Whether to enable Workload Identity on GKE clusters"
  type        = bool
  default     = true
}

# Resource Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "multi-environment-testing-pipeline"
  }
}