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
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1, europe-west1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for resource deployment"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone (e.g., us-central1-a, europe-west1-b)."
  }
}

# Resource Naming Configuration
variable "name_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "deploy-demo"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "random_suffix" {
  description = "Random suffix for unique resource naming (auto-generated if not provided)"
  type        = string
  default     = null
}

# Application Configuration
variable "app_name" {
  description = "Name of the application being deployed"
  type        = string
  default     = "sample-app"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.app_name))
    error_message = "Application name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "container_image" {
  description = "Container image for the application (leave empty to use default)"
  type        = string
  default     = ""
}

# GKE Cluster Configuration
variable "gke_dev_config" {
  description = "Configuration for development GKE cluster"
  type = object({
    node_count           = number
    machine_type         = string
    enable_autorepair    = bool
    enable_autoupgrade   = bool
    enable_autoscaling   = bool
    min_node_count       = number
    max_node_count       = number
    disk_size_gb         = number
    disk_type            = string
    preemptible          = bool
    enable_private_nodes = bool
  })
  default = {
    node_count           = 2
    machine_type         = "e2-standard-2"
    enable_autorepair    = true
    enable_autoupgrade   = true
    enable_autoscaling   = true
    min_node_count       = 1
    max_node_count       = 3
    disk_size_gb         = 20
    disk_type            = "pd-standard"
    preemptible          = true
    enable_private_nodes = false
  }
}

variable "gke_staging_config" {
  description = "Configuration for staging GKE cluster"
  type = object({
    node_count           = number
    machine_type         = string
    enable_autorepair    = bool
    enable_autoupgrade   = bool
    enable_autoscaling   = bool
    min_node_count       = number
    max_node_count       = number
    disk_size_gb         = number
    disk_type            = string
    preemptible          = bool
    enable_private_nodes = bool
  })
  default = {
    node_count           = 2
    machine_type         = "e2-standard-2"
    enable_autorepair    = true
    enable_autoupgrade   = true
    enable_autoscaling   = true
    min_node_count       = 1
    max_node_count       = 5
    disk_size_gb         = 30
    disk_type            = "pd-standard"
    preemptible          = false
    enable_private_nodes = false
  }
}

variable "gke_prod_config" {
  description = "Configuration for production GKE cluster"
  type = object({
    node_count           = number
    machine_type         = string
    enable_autorepair    = bool
    enable_autoupgrade   = bool
    enable_autoscaling   = bool
    min_node_count       = number
    max_node_count       = number
    disk_size_gb         = number
    disk_type            = string
    preemptible          = bool
    enable_private_nodes = bool
  })
  default = {
    node_count           = 3
    machine_type         = "e2-standard-4"
    enable_autorepair    = true
    enable_autoupgrade   = true
    enable_autoscaling   = true
    min_node_count       = 2
    max_node_count       = 10
    disk_size_gb         = 50
    disk_type            = "pd-ssd"
    preemptible          = false
    enable_private_nodes = true
  }
}

# Cloud Deploy Configuration
variable "pipeline_name" {
  description = "Name of the Cloud Deploy pipeline"
  type        = string
  default     = "app-pipeline"
}

variable "require_approval_for_staging" {
  description = "Whether to require approval for staging environment deployment"
  type        = bool
  default     = false
}

variable "require_approval_for_prod" {
  description = "Whether to require approval for production environment deployment"
  type        = bool
  default     = true
}

# Cloud Build Configuration
variable "build_timeout" {
  description = "Timeout for Cloud Build operations"
  type        = string
  default     = "1200s"
}

variable "build_machine_type" {
  description = "Machine type for Cloud Build"
  type        = string
  default     = "E2_HIGHCPU_8"
  validation {
    condition = contains([
      "E2_HIGHCPU_8",
      "E2_HIGHCPU_32",
      "E2_MEDIUM",
      "N1_HIGHCPU_8",
      "N1_HIGHCPU_32"
    ], var.build_machine_type)
    error_message = "Build machine type must be one of: E2_HIGHCPU_8, E2_HIGHCPU_32, E2_MEDIUM, N1_HIGHCPU_8, N1_HIGHCPU_32."
  }
}

variable "github_repo_owner" {
  description = "GitHub repository owner (for Cloud Build triggers)"
  type        = string
  default     = ""
}

variable "github_repo_name" {
  description = "GitHub repository name (for Cloud Build triggers)"
  type        = string
  default     = ""
}

variable "branch_pattern" {
  description = "Branch pattern for Cloud Build triggers"
  type        = string
  default     = "^main$"
}

# IAM Configuration
variable "create_service_accounts" {
  description = "Whether to create dedicated service accounts for Cloud Deploy and Cloud Build"
  type        = bool
  default     = true
}

# Network Configuration
variable "enable_private_cluster" {
  description = "Enable private cluster configuration for production"
  type        = bool
  default     = false
}

variable "authorized_networks" {
  description = "List of authorized networks for private clusters"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

# Monitoring and Logging
variable "enable_workload_identity" {
  description = "Enable Workload Identity for secure pod-to-service communication"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable network policy for cluster security"
  type        = bool
  default     = true
}

variable "enable_cloud_logging" {
  description = "Enable Cloud Logging for clusters"
  type        = bool
  default     = true
}

variable "enable_cloud_monitoring" {
  description = "Enable Cloud Monitoring for clusters"
  type        = bool
  default     = true
}

# Cost Optimization
variable "enable_preemptible_nodes" {
  description = "Enable preemptible nodes for cost optimization (development only)"
  type        = bool
  default     = true
}

variable "enable_node_auto_provisioning" {
  description = "Enable node auto-provisioning for cost optimization"
  type        = bool
  default     = false
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "multi-env-demo"
    managed-by  = "terraform"
    project     = "cloud-deploy-demo"
  }
}

variable "environment_labels" {
  description = "Environment-specific labels"
  type = object({
    dev = map(string)
    staging = map(string)
    prod = map(string)
  })
  default = {
    dev = {
      environment = "development"
      tier        = "dev"
    }
    staging = {
      environment = "staging"
      tier        = "staging"
    }
    prod = {
      environment = "production"
      tier        = "prod"
    }
  }
}