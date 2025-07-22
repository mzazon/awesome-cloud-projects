# Variables for GCP OS Patch Management Infrastructure
# This file defines all configurable parameters for the patch management solution

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_id))
    error_message = "Project ID must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for compute instances"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vm_instance_count" {
  description = "Number of VM instances to create for patch management testing"
  type        = number
  default     = 3
  
  validation {
    condition     = var.vm_instance_count >= 1 && var.vm_instance_count <= 10
    error_message = "VM instance count must be between 1 and 10."
  }
}

variable "vm_machine_type" {
  description = "Machine type for VM instances"
  type        = string
  default     = "e2-medium"
  
  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n2-standard-2", "n2-standard-4"
    ], var.vm_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "vm_boot_disk_size" {
  description = "Boot disk size in GB for VM instances"
  type        = number
  default     = 20
  
  validation {
    condition     = var.vm_boot_disk_size >= 10 && var.vm_boot_disk_size <= 100
    error_message = "Boot disk size must be between 10 and 100 GB."
  }
}

variable "vm_image_family" {
  description = "Image family for VM instances"
  type        = string
  default     = "ubuntu-2004-lts"
  
  validation {
    condition = contains([
      "ubuntu-2004-lts", "ubuntu-2204-lts", "debian-11", "debian-12",
      "centos-7", "rhel-8", "windows-2019", "windows-2022"
    ], var.vm_image_family)
    error_message = "Image family must be a supported OS family."
  }
}

variable "vm_image_project" {
  description = "Image project for VM instances"
  type        = string
  default     = "ubuntu-os-cloud"
}

variable "patch_schedule" {
  description = "Cron schedule for patch deployment (default: weekly on Sunday at 2 AM)"
  type        = string
  default     = "0 2 * * SUN"
  
  validation {
    condition     = can(regex("^([0-9*,-/]+\\s+){4}[0-9*,-/A-Z]+$", var.patch_schedule))
    error_message = "Patch schedule must be a valid cron expression."
  }
}

variable "patch_schedule_timezone" {
  description = "Timezone for patch scheduling"
  type        = string
  default     = "America/New_York"
}

variable "patch_reboot_config" {
  description = "Reboot configuration for patch deployments"
  type        = string
  default     = "REBOOT_IF_REQUIRED"
  
  validation {
    condition = contains([
      "REBOOT_IF_REQUIRED", "NEVER_REBOOT", "ALWAYS_REBOOT"
    ], var.patch_reboot_config)
    error_message = "Reboot config must be REBOOT_IF_REQUIRED, NEVER_REBOOT, or ALWAYS_REBOOT."
  }
}

variable "patch_duration_seconds" {
  description = "Maximum duration for patch deployment in seconds"
  type        = number
  default     = 7200
  
  validation {
    condition     = var.patch_duration_seconds >= 300 && var.patch_duration_seconds <= 14400
    error_message = "Patch duration must be between 300 and 14400 seconds (5 minutes to 4 hours)."
  }
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring dashboard and alerts"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Cloud Logging for patch management activities"
  type        = bool
  default     = true
}

variable "notification_channels" {
  description = "List of notification channel names for alerts"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "patch-management"
    managed-by  = "terraform"
    component   = "vm-manager"
  }
}

variable "network_name" {
  description = "Name of the VPC network (will be created if doesn't exist)"
  type        = string
  default     = "patch-management-network"
}

variable "subnet_name" {
  description = "Name of the subnet for VM instances"
  type        = string
  default     = "patch-management-subnet"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "create_service_account" {
  description = "Whether to create a dedicated service account for patch management"
  type        = bool
  default     = true
}

variable "service_account_name" {
  description = "Name of the service account for patch management"
  type        = string
  default     = "patch-management-sa"
}

variable "enable_os_config_api" {
  description = "Enable OS Config API for the project"
  type        = bool
  default     = true
}

variable "enable_compute_api" {
  description = "Enable Compute Engine API for the project"
  type        = bool
  default     = true
}

variable "enable_scheduler_api" {
  description = "Enable Cloud Scheduler API for the project"
  type        = bool
  default     = true
}

variable "enable_functions_api" {
  description = "Enable Cloud Functions API for the project"
  type        = bool
  default     = true
}

variable "enable_monitoring_api" {
  description = "Enable Cloud Monitoring API for the project"
  type        = bool
  default     = true
}