# Variable definitions for GCP secure remote development environment

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The Google Cloud region where regional resources will be created"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone (e.g., us-central1-a)."
  }
}

variable "environment" {
  description = "Environment tag for resource organization"
  type        = string
  default     = "development"
  
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# Networking configuration variables
variable "vpc_cidr_range" {
  description = "CIDR range for the development subnet"
  type        = string
  default     = "10.0.0.0/24"
  
  validation {
    condition = can(cidrhost(var.vpc_cidr_range, 0))
    error_message = "VPC CIDR range must be a valid CIDR notation."
  }
}

variable "build_pool_cidr_range" {
  description = "CIDR range for the private build pool peered network"
  type        = string
  default     = "10.1.0.0/24"
  
  validation {
    condition = can(cidrhost(var.build_pool_cidr_range, 0))
    error_message = "Build pool CIDR range must be a valid CIDR notation."
  }
}

# Workstation configuration variables
variable "workstation_machine_type" {
  description = "Machine type for Cloud Workstations"
  type        = string
  default     = "e2-standard-4"
  
  validation {
    condition = can(regex("^[a-z0-9]+-[a-z0-9]+-[0-9]+$", var.workstation_machine_type))
    error_message = "Machine type must be a valid Google Cloud machine type (e.g., e2-standard-4)."
  }
}

variable "workstation_disk_size_gb" {
  description = "Persistent disk size in GB for workstations"
  type        = number
  default     = 100
  
  validation {
    condition = var.workstation_disk_size_gb >= 10 && var.workstation_disk_size_gb <= 65536
    error_message = "Workstation disk size must be between 10 and 65536 GB."
  }
}

variable "workstation_disk_type" {
  description = "Persistent disk type for workstations"
  type        = string
  default     = "pd-standard"
  
  validation {
    condition = contains(["pd-standard", "pd-ssd", "pd-balanced"], var.workstation_disk_type)
    error_message = "Disk type must be one of: pd-standard, pd-ssd, pd-balanced."
  }
}

variable "workstation_idle_timeout" {
  description = "Idle timeout for workstations in seconds"
  type        = number
  default     = 7200  # 2 hours
  
  validation {
    condition = var.workstation_idle_timeout >= 60 && var.workstation_idle_timeout <= 86400
    error_message = "Idle timeout must be between 60 seconds (1 minute) and 86400 seconds (24 hours)."
  }
}

variable "workstation_running_timeout" {
  description = "Maximum running timeout for workstations in seconds"
  type        = string
  default     = "43200s"  # 12 hours
}

variable "workstation_container_image" {
  description = "Container image for Cloud Workstations"
  type        = string
  default     = "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"
}

# Cloud Build configuration variables
variable "build_pool_machine_type" {
  description = "Machine type for private Cloud Build pool workers"
  type        = string
  default     = "e2-medium"
  
  validation {
    condition = can(regex("^[a-z0-9]+-[a-z0-9]+-[0-9]+$", var.build_pool_machine_type))
    error_message = "Build pool machine type must be a valid Google Cloud machine type."
  }
}

variable "build_pool_disk_size_gb" {
  description = "Disk size in GB for private Cloud Build pool workers"
  type        = number
  default     = 100
  
  validation {
    condition = var.build_pool_disk_size_gb >= 10 && var.build_pool_disk_size_gb <= 65536
    error_message = "Build pool disk size must be between 10 and 65536 GB."
  }
}

# Application and repository configuration
variable "repository_name_suffix" {
  description = "Optional suffix for repository names (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "cloudbuild_filename" {
  description = "Name of the Cloud Build configuration file in the repository"
  type        = string
  default     = "cloudbuild.yaml"
}

variable "source_repo_branch_pattern" {
  description = "Branch pattern to trigger builds (supports wildcards)"
  type        = string
  default     = "main"
}

# Developer access configuration
variable "developer_emails" {
  description = "List of developer email addresses to grant workstation access"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.developer_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All developer emails must be valid email addresses."
  }
}

variable "developer_groups" {
  description = "List of Google Groups to grant workstation access"
  type        = list(string)
  default     = []
}

# Security and compliance variables
variable "enable_audit_logs" {
  description = "Enable audit logging for workstations"
  type        = bool
  default     = true
}

variable "disable_public_ip" {
  description = "Disable public IP addresses for workstations"
  type        = bool
  default     = true
}

variable "enable_private_google_access" {
  description = "Enable Private Google Access for the subnet"
  type        = bool
  default     = true
}

# Resource tagging and labeling
variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]{1,63}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, hyphens, and underscores, and be 63 characters or less."
  }
}

# Cost optimization variables
variable "enable_workstation_auto_shutdown" {
  description = "Enable automatic shutdown of idle workstations"
  type        = bool
  default     = true
}

variable "workstation_preemptible" {
  description = "Use preemptible instances for workstations (cost optimization)"
  type        = bool
  default     = false
}