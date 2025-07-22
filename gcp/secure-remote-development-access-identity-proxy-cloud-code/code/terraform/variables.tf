# Project configuration variables
variable "project_id" {
  description = "Google Cloud Project ID for deploying secure development infrastructure"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be a valid Google Cloud project identifier."
  }
}

variable "region" {
  description = "Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for Compute Engine resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone identifier."
  }
}

# Development VM configuration
variable "vm_machine_type" {
  description = "Machine type for the development VM"
  type        = string
  default     = "e2-standard-4"
  
  validation {
    condition = contains([
      "e2-standard-2", "e2-standard-4", "e2-standard-8",
      "n1-standard-2", "n1-standard-4", "n1-standard-8",
      "n2-standard-2", "n2-standard-4", "n2-standard-8"
    ], var.vm_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "vm_boot_disk_size" {
  description = "Boot disk size for development VM in GB"
  type        = number
  default     = 50
  
  validation {
    condition     = var.vm_boot_disk_size >= 20 && var.vm_boot_disk_size <= 500
    error_message = "Boot disk size must be between 20 and 500 GB."
  }
}

variable "vm_boot_disk_type" {
  description = "Boot disk type for development VM"
  type        = string
  default     = "pd-standard"
  
  validation {
    condition     = contains(["pd-standard", "pd-ssd", "pd-balanced"], var.vm_boot_disk_type)
    error_message = "Boot disk type must be pd-standard, pd-ssd, or pd-balanced."
  }
}

# Artifact Registry configuration
variable "artifact_registry_format" {
  description = "Format for Artifact Registry repository"
  type        = string
  default     = "DOCKER"
  
  validation {
    condition     = contains(["DOCKER", "NPM", "MAVEN", "APT", "YUM", "PYTHON"], var.artifact_registry_format)
    error_message = "Repository format must be a valid Artifact Registry format."
  }
}

# Security and access configuration
variable "allowed_users" {
  description = "List of user emails allowed to access the development environment via IAP"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.allowed_users : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All allowed users must be valid email addresses."
  }
}

variable "enable_os_login" {
  description = "Enable OS Login for enhanced security and audit capabilities"
  type        = bool
  default     = true
}

variable "enable_vulnerability_scanning" {
  description = "Enable vulnerability scanning for Artifact Registry"
  type        = bool
  default     = true
}

# OAuth consent screen configuration
variable "oauth_application_title" {
  description = "Title for the OAuth application used by IAP"
  type        = string
  default     = "Secure Development Environment"
  
  validation {
    condition     = length(var.oauth_application_title) > 0 && length(var.oauth_application_title) <= 120
    error_message = "OAuth application title must be between 1 and 120 characters."
  }
}

variable "oauth_support_email" {
  description = "Support email for OAuth consent screen"
  type        = string
  default     = ""
  
  validation {
    condition = var.oauth_support_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.oauth_support_email))
    error_message = "Support email must be a valid email address or empty string."
  }
}

# Resource naming and tagging
variable "resource_name_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "secure-dev"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_name_prefix))
    error_message = "Resource name prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment label for resource tagging"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "secure-remote-development"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain lowercase letters, numbers, underscores, and hyphens."
  }
}

# Network configuration
variable "network_name" {
  description = "Name of the VPC network to use (default network if not specified)"
  type        = string
  default     = "default"
}

variable "subnet_name" {
  description = "Name of the subnet to use (default subnet if not specified)"
  type        = string
  default     = "default"
}

# Enable APIs configuration
variable "enable_apis" {
  description = "List of Google Cloud APIs to enable for the project"
  type        = list(string)
  default = [
    "iap.googleapis.com",
    "compute.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}