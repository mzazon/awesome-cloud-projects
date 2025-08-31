# Variables for AlloyDB Omni and Hyperdisk Extreme performance optimization

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must be a valid Google Cloud project identifier."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region identifier."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone identifier."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "perf-test"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

# Compute Instance Configuration
variable "machine_type" {
  description = "Machine type for the AlloyDB Omni compute instance"
  type        = string
  default     = "c3-highmem-8"
  validation {
    condition     = contains(["c3-highmem-8", "c3-highmem-16", "c3-highmem-32"], var.machine_type)
    error_message = "Machine type must be one of: c3-highmem-8, c3-highmem-16, c3-highmem-32."
  }
}

variable "boot_disk_size" {
  description = "Size of the boot disk in GB"
  type        = number
  default     = 50
  validation {
    condition     = var.boot_disk_size >= 20 && var.boot_disk_size <= 2000
    error_message = "Boot disk size must be between 20 and 2000 GB."
  }
}

variable "boot_disk_type" {
  description = "Type of the boot disk"
  type        = string
  default     = "pd-ssd"
  validation {
    condition     = contains(["pd-standard", "pd-ssd", "pd-balanced"], var.boot_disk_type)
    error_message = "Boot disk type must be one of: pd-standard, pd-ssd, pd-balanced."
  }
}

# Hyperdisk Extreme Configuration
variable "hyperdisk_size" {
  description = "Size of the Hyperdisk Extreme volume in GB"
  type        = number
  default     = 500
  validation {
    condition     = var.hyperdisk_size >= 64 && var.hyperdisk_size <= 65536
    error_message = "Hyperdisk Extreme size must be between 64 and 65536 GB."
  }
}

variable "hyperdisk_provisioned_iops" {
  description = "Provisioned IOPS for Hyperdisk Extreme (max 350000)"
  type        = number
  default     = 100000
  validation {
    condition     = var.hyperdisk_provisioned_iops >= 10000 && var.hyperdisk_provisioned_iops <= 350000
    error_message = "Provisioned IOPS must be between 10000 and 350000."
  }
}

# AlloyDB Omni Configuration
variable "alloydb_password" {
  description = "Password for the AlloyDB Omni PostgreSQL instance"
  type        = string
  default     = "AlloyDB_Secure_2025!"
  sensitive   = true
  validation {
    condition     = length(var.alloydb_password) >= 12
    error_message = "AlloyDB password must be at least 12 characters long."
  }
}

variable "alloydb_database" {
  description = "Default database name for AlloyDB Omni"
  type        = string
  default     = "analytics_db"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.alloydb_database))
    error_message = "Database name must start with a letter and contain only letters, numbers, and underscores."
  }
}

# Cloud Function Configuration
variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 3 && var.function_timeout <= 540
    error_message = "Function timeout must be between 3 and 540 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "python312"
  validation {
    condition     = contains(["python39", "python310", "python311", "python312"], var.function_runtime)
    error_message = "Function runtime must be one of: python39, python310, python311, python312."
  }
}

# Monitoring Configuration
variable "cpu_threshold" {
  description = "CPU utilization threshold for alerting (0.0 to 1.0)"
  type        = number
  default     = 0.8
  validation {
    condition     = var.cpu_threshold >= 0.1 && var.cpu_threshold <= 1.0
    error_message = "CPU threshold must be between 0.1 and 1.0."
  }
}

variable "alert_duration" {
  description = "Duration for alert condition in seconds"
  type        = string
  default     = "60s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.alert_duration))
    error_message = "Alert duration must be in seconds format (e.g., '60s')."
  }
}

# Networking Configuration
variable "network_name" {
  description = "Name of the VPC network (defaults to 'default')"
  type        = string
  default     = "default"
}

variable "subnet_name" {
  description = "Name of the subnet (defaults to 'default')"
  type        = string
  default     = "default"
}

# Tagging and Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "alloydb-perf-optimization"
    component   = "database"
    environment = "performance-testing"
    managed_by  = "terraform"
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Whether to create monitoring dashboard and alerts"
  type        = bool
  default     = true
}

variable "enable_cloud_function" {
  description = "Whether to deploy the performance scaling Cloud Function"
  type        = bool
  default     = true
}

# Resource naming prefix
variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "alloydb-perf"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "Name prefix must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}