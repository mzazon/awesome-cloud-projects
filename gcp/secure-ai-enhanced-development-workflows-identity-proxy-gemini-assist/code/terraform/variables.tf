# Core project configuration variables
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone (e.g., us-central1-a)."
  }
}

variable "organization_id" {
  description = "The Google Cloud Organization ID (required for IAP configuration)"
  type        = string
  validation {
    condition     = length(var.organization_id) > 0
    error_message = "Organization ID must not be empty for IAP configuration."
  }
}

# Application and resource naming variables
variable "app_name" {
  description = "Base name for the secure development application"
  type        = string
  default     = "secure-dev-app"
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.app_name))
    error_message = "App name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "workstation_name" {
  description = "Name for the secure development workstation"
  type        = string
  default     = "secure-workstation"
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.workstation_name))
    error_message = "Workstation name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Cloud Workstations configuration variables
variable "workstation_machine_type" {
  description = "Machine type for Cloud Workstations"
  type        = string
  default     = "e2-standard-4"
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.workstation_machine_type))
    error_message = "Machine type must be a valid Google Cloud machine type."
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
  default     = 3600
  validation {
    condition = var.workstation_idle_timeout >= 300 && var.workstation_idle_timeout <= 86400
    error_message = "Idle timeout must be between 300 and 86400 seconds."
  }
}

# Cloud Run configuration variables
variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "512Mi"
  validation {
    condition = can(regex("^[0-9]+Mi$|^[0-9]+Gi$", var.cloud_run_memory))
    error_message = "Memory must be specified in Mi or Gi format (e.g., 512Mi, 2Gi)."
  }
}

variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "1"
  validation {
    condition = contains(["1", "2", "4", "8"], var.cloud_run_cpu)
    error_message = "CPU must be one of: 1, 2, 4, 8."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
  validation {
    condition = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "cloud_run_timeout_seconds" {
  description = "Request timeout for Cloud Run service in seconds"
  type        = number
  default     = 300
  validation {
    condition = var.cloud_run_timeout_seconds >= 1 && var.cloud_run_timeout_seconds <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

# Security and compliance variables
variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for container image validation"
  type        = bool
  default     = true
}

variable "enable_vpc_sc" {
  description = "Enable VPC Service Controls for additional security"
  type        = bool
  default     = false
}

variable "allowed_users" {
  description = "List of user emails allowed to access IAP-protected resources"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for email in var.allowed_users : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All allowed users must be valid email addresses."
  }
}

variable "oauth_brand_application_title" {
  description = "Application title for OAuth consent screen"
  type        = string
  default     = "Secure Development Environment"
  validation {
    condition = length(var.oauth_brand_application_title) > 0 && length(var.oauth_brand_application_title) <= 120
    error_message = "OAuth brand application title must be between 1 and 120 characters."
  }
}

variable "oauth_support_email" {
  description = "Support email for OAuth consent screen"
  type        = string
  default     = ""
  validation {
    condition = var.oauth_support_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.oauth_support_email))
    error_message = "OAuth support email must be a valid email address or empty string."
  }
}

# KMS encryption variables
variable "kms_key_rotation_period" {
  description = "Rotation period for KMS keys (e.g., 7776000s for 90 days)"
  type        = string
  default     = "7776000s"
  validation {
    condition = can(regex("^[0-9]+s$", var.kms_key_rotation_period))
    error_message = "KMS key rotation period must be specified in seconds with 's' suffix."
  }
}

# Container image configuration
variable "container_image" {
  description = "Container image for Cloud Workstations"
  type        = string
  default     = "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"
  validation {
    condition = can(regex("^[a-z0-9.-]+/[a-z0-9.-]+/[a-z0-9.-]+:[a-z0-9.-]+$", var.container_image))
    error_message = "Container image must be a valid Docker image reference."
  }
}

# Network configuration variables
variable "network_name" {
  description = "Name of the VPC network (if using custom network)"
  type        = string
  default     = "default"
}

variable "subnetwork_name" {
  description = "Name of the subnetwork (if using custom network)"
  type        = string
  default     = "default"
}

# Labels and tags
variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "secure-ai-development"
    managed-by  = "terraform"
    environment = "dev"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain lowercase letters, numbers, underscores, and hyphens."
  }
}

# Billing and cost management
variable "budget_amount" {
  description = "Budget amount in USD for cost monitoring (0 to disable)"
  type        = number
  default     = 100
  validation {
    condition = var.budget_amount >= 0
    error_message = "Budget amount must be non-negative."
  }
}

variable "budget_alert_thresholds" {
  description = "Budget alert thresholds as percentages"
  type        = list(number)
  default     = [50, 75, 90, 100]
  validation {
    condition = alltrue([
      for threshold in var.budget_alert_thresholds : threshold > 0 && threshold <= 100
    ])
    error_message = "Budget alert thresholds must be between 1 and 100."
  }
}