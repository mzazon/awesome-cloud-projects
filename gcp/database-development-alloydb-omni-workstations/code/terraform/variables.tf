# Variables for GCP Database Development Workflow with AlloyDB Omni and Cloud Workstations
# This file defines all configurable parameters for the infrastructure deployment

# Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be a valid GCP project identifier."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone."
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

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "db-dev"
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.resource_prefix))
    error_message = "Resource prefix must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

# Networking Configuration
variable "vpc_cidr" {
  description = "CIDR range for the VPC network"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "workstation_subnet_cidr" {
  description = "CIDR range for the Cloud Workstations subnet"
  type        = string
  default     = "10.0.1.0/24"
  validation {
    condition     = can(cidrhost(var.workstation_subnet_cidr, 0))
    error_message = "Workstation subnet CIDR must be a valid IPv4 CIDR block."
  }
}

# Cloud Workstations Configuration
variable "workstation_cluster_config" {
  description = "Configuration settings for the Cloud Workstations cluster"
  type = object({
    machine_type                   = string
    boot_disk_size_gb             = number
    persistent_disk_size_gb       = number
    disable_public_ip_addresses   = bool
    enable_nested_virtualization  = bool
    enable_audit_agent           = bool
    idle_timeout                 = string
    running_timeout              = string
  })
  default = {
    machine_type                   = "e2-standard-4"
    boot_disk_size_gb             = 50
    persistent_disk_size_gb       = 200
    disable_public_ip_addresses   = true
    enable_nested_virtualization  = false
    enable_audit_agent           = true
    idle_timeout                 = "7200s"  # 2 hours
    running_timeout              = "28800s" # 8 hours
  }
  validation {
    condition = contains([
      "e2-standard-2", "e2-standard-4", "e2-standard-8", "e2-standard-16",
      "e2-highmem-2", "e2-highmem-4", "e2-highmem-8", "e2-highmem-16",
      "n2-standard-2", "n2-standard-4", "n2-standard-8", "n2-standard-16"
    ], var.workstation_cluster_config.machine_type)
    error_message = "Machine type must be a valid Compute Engine machine type suitable for workstations."
  }
}

variable "workstation_container_image" {
  description = "Container image for Cloud Workstations"
  type        = string
  default     = "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"
  validation {
    condition     = can(regex("^[a-z0-9.-]+/[a-z0-9.-]+/[a-z0-9.-]+/[a-z0-9.-]+:[a-z0-9.-]+$", var.workstation_container_image))
    error_message = "Container image must be a valid Docker image path."
  }
}

variable "workstation_users" {
  description = "List of users who can access workstations (email addresses)"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for email in var.workstation_users : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All workstation users must be valid email addresses."
  }
}

# Cloud Source Repositories Configuration
variable "repository_name" {
  description = "Name for the Cloud Source Repository"
  type        = string
  default     = "database-development"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,128}$", var.repository_name))
    error_message = "Repository name must be 1-128 characters, alphanumeric, hyphens, and underscores only."
  }
}

variable "repository_developers" {
  description = "List of developers who can access the source repository (email addresses)"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for email in var.repository_developers : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All repository developers must be valid email addresses."
  }
}

# Cloud Build Configuration
variable "build_trigger_config" {
  description = "Configuration for Cloud Build triggers"
  type = object({
    branch_pattern         = string
    tag_pattern           = string
    pull_request_pattern  = string
    include_build_logs    = bool
    timeout_seconds       = number
  })
  default = {
    branch_pattern         = "^main$"
    tag_pattern           = "^v[0-9]+\\.[0-9]+\\.[0-9]+$"
    pull_request_pattern  = ".*"
    include_build_logs    = true
    timeout_seconds       = 1800  # 30 minutes
  }
  validation {
    condition     = var.build_trigger_config.timeout_seconds >= 120 && var.build_trigger_config.timeout_seconds <= 7200
    error_message = "Build timeout must be between 120 seconds (2 minutes) and 7200 seconds (2 hours)."
  }
}

# Artifact Registry Configuration
variable "artifact_registry_config" {
  description = "Configuration for Artifact Registry repositories"
  type = object({
    format                    = string
    cleanup_policy_enabled    = bool
    cleanup_keep_tag_revisions = number
    cleanup_delete_untagged   = bool
  })
  default = {
    format                    = "DOCKER"
    cleanup_policy_enabled    = true
    cleanup_keep_tag_revisions = 10
    cleanup_delete_untagged   = true
  }
  validation {
    condition     = contains(["DOCKER", "MAVEN", "NPM", "PYTHON"], var.artifact_registry_config.format)
    error_message = "Artifact registry format must be one of: DOCKER, MAVEN, NPM, PYTHON."
  }
}

# AlloyDB Omni Configuration (for documentation and future use)
variable "alloydb_config" {
  description = "Configuration for AlloyDB Omni development environment"
  type = object({
    database_name     = string
    database_user     = string
    enable_columnar   = bool
    enable_vector     = bool
    backup_retention  = number
  })
  default = {
    database_name     = "development_db"
    database_user     = "dev_user"
    enable_columnar   = true
    enable_vector     = true
    backup_retention  = 7  # days
  }
  validation {
    condition     = var.alloydb_config.backup_retention >= 1 && var.alloydb_config.backup_retention <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}

# Monitoring and Logging Configuration
variable "monitoring_config" {
  description = "Configuration for monitoring and logging"
  type = object({
    enable_flow_logs           = bool
    enable_workstation_logs    = bool
    enable_build_logs         = bool
    log_retention_days        = number
    notification_email        = string
  })
  default = {
    enable_flow_logs           = true
    enable_workstation_logs    = true
    enable_build_logs         = true
    log_retention_days        = 30
    notification_email        = ""
  }
  validation {
    condition     = var.monitoring_config.log_retention_days >= 1 && var.monitoring_config.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days (10 years)."
  }
}

# Security Configuration
variable "security_config" {
  description = "Security configuration settings"
  type = object({
    enable_os_login                = bool
    enable_shielded_vm            = bool
    enable_secure_boot            = bool
    enable_integrity_monitoring   = bool
    require_https_lb              = bool
    enable_private_google_access  = bool
  })
  default = {
    enable_os_login                = true
    enable_shielded_vm            = true
    enable_secure_boot            = true
    enable_integrity_monitoring   = true
    require_https_lb              = true
    enable_private_google_access  = true
  }
}

# Labels and Tagging
variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for key, value in var.additional_labels : can(regex("^[a-z0-9_-]{1,63}$", key))
    ])
    error_message = "Label keys must be 1-63 characters, lowercase letters, numbers, underscores, and hyphens only."
  }
  validation {
    condition = alltrue([
      for key, value in var.additional_labels : can(regex("^[a-z0-9_-]{0,63}$", value))
    ])
    error_message = "Label values must be 0-63 characters, lowercase letters, numbers, underscores, and hyphens only."
  }
}