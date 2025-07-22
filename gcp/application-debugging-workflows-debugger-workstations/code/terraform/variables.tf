# Project configuration variables
variable "project_id" {
  description = "Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1, europe-west1)."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone (e.g., us-central1-a, europe-west1-b)."
  }
}

# Resource naming variables
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "debug-workflow"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Cloud Workstations configuration
variable "workstation_cluster_name" {
  description = "Name for the Cloud Workstations cluster"
  type        = string
  default     = ""
}

variable "workstation_config_name" {
  description = "Name for the Cloud Workstations configuration"
  type        = string
  default     = ""
}

variable "workstation_instance_name" {
  description = "Name for the Cloud Workstations instance"
  type        = string
  default     = ""
}

variable "workstation_machine_type" {
  description = "Machine type for Cloud Workstations instances"
  type        = string
  default     = "e2-standard-4"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+-[0-9]+$", var.workstation_machine_type))
    error_message = "Machine type must be a valid Google Cloud machine type (e.g., e2-standard-4, n1-standard-2)."
  }
}

variable "workstation_disk_size_gb" {
  description = "Disk size in GB for Cloud Workstations instances"
  type        = number
  default     = 200
  validation {
    condition     = var.workstation_disk_size_gb >= 50 && var.workstation_disk_size_gb <= 1000
    error_message = "Workstation disk size must be between 50 and 1000 GB."
  }
}

variable "workstation_disk_type" {
  description = "Disk type for Cloud Workstations instances"
  type        = string
  default     = "pd-standard"
  validation {
    condition     = contains(["pd-standard", "pd-ssd", "pd-balanced"], var.workstation_disk_type)
    error_message = "Workstation disk type must be one of: pd-standard, pd-ssd, pd-balanced."
  }
}

variable "workstation_idle_timeout" {
  description = "Idle timeout in seconds for Cloud Workstations instances"
  type        = number
  default     = 7200
  validation {
    condition     = var.workstation_idle_timeout >= 300 && var.workstation_idle_timeout <= 43200
    error_message = "Workstation idle timeout must be between 300 seconds (5 minutes) and 43200 seconds (12 hours)."
  }
}

variable "workstation_running_timeout" {
  description = "Running timeout in seconds for Cloud Workstations instances"
  type        = number
  default     = 28800
  validation {
    condition     = var.workstation_running_timeout >= 3600 && var.workstation_running_timeout <= 86400
    error_message = "Workstation running timeout must be between 3600 seconds (1 hour) and 86400 seconds (24 hours)."
  }
}

# Artifact Registry configuration
variable "artifact_registry_repository_name" {
  description = "Name for the Artifact Registry repository"
  type        = string
  default     = ""
}

variable "artifact_registry_description" {
  description = "Description for the Artifact Registry repository"
  type        = string
  default     = "Repository for debugging workflow containers"
}

# Cloud Run configuration
variable "cloud_run_service_name" {
  description = "Name for the Cloud Run service"
  type        = string
  default     = ""
}

variable "cloud_run_image" {
  description = "Container image for the Cloud Run service"
  type        = string
  default     = "gcr.io/google-samples/hello-app:1.0"
}

variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "1"
  validation {
    condition     = contains(["1", "2", "4", "8"], var.cloud_run_cpu)
    error_message = "Cloud Run CPU must be one of: 1, 2, 4, 8."
  }
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "512Mi"
  validation {
    condition     = can(regex("^[0-9]+[MG]i$", var.cloud_run_memory))
    error_message = "Cloud Run memory must be in format like 512Mi or 1Gi."
  }
}

variable "cloud_run_port" {
  description = "Port for the Cloud Run service"
  type        = number
  default     = 8080
  validation {
    condition     = var.cloud_run_port >= 1024 && var.cloud_run_port <= 65535
    error_message = "Cloud Run port must be between 1024 and 65535."
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

# Monitoring and logging configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for the debugging workflow"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Cloud Logging for the debugging workflow"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
  }
}

# Security configuration
variable "enable_private_google_access" {
  description = "Enable Private Google Access for the subnet"
  type        = bool
  default     = true
}

variable "allowed_ingress_cidr_blocks" {
  description = "List of CIDR blocks allowed to access Cloud Run service"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition     = alltrue([for cidr in var.allowed_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All CIDR blocks must be valid (e.g., 10.0.0.0/8, 192.168.1.0/24)."
  }
}

# IAM configuration
variable "workstation_service_account_email" {
  description = "Email of the service account for Cloud Workstations (optional)"
  type        = string
  default     = ""
}

variable "cloud_run_service_account_email" {
  description = "Email of the service account for Cloud Run (optional)"
  type        = string
  default     = ""
}

# Container image configuration
variable "debug_tools_image_name" {
  description = "Name for the custom debug tools container image"
  type        = string
  default     = "debug-workstation"
}

variable "debug_tools_image_tag" {
  description = "Tag for the custom debug tools container image"
  type        = string
  default     = "latest"
}

# Resource labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "debugging-workflow"
    managed-by  = "terraform"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && length(k) <= 63])
    error_message = "Label keys must start with a letter, contain only lowercase letters, numbers, underscores, and hyphens, and be at most 63 characters long."
  }
  validation {
    condition     = alltrue([for k, v in var.labels : length(v) <= 63])
    error_message = "Label values must be at most 63 characters long."
  }
}

# APIs to enable
variable "enable_apis" {
  description = "List of APIs to enable for the project"
  type        = list(string)
  default = [
    "workstations.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com"
  ]
}

# Cost optimization settings
variable "enable_auto_shutdown" {
  description = "Enable automatic shutdown for workstations during non-business hours"
  type        = bool
  default     = true
}

variable "auto_shutdown_schedule" {
  description = "Cron schedule for automatic workstation shutdown (UTC)"
  type        = string
  default     = "0 18 * * 1-5"
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.auto_shutdown_schedule))
    error_message = "Auto shutdown schedule must be a valid cron expression."
  }
}