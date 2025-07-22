# Variables for GCP Disaster Recovery with Cloud WAN and Parallelstore
# This file defines all configurable parameters for the disaster recovery solution

# Project and Environment Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Regional Configuration for Disaster Recovery
variable "primary_region" {
  description = "Primary GCP region for main resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.primary_region))
    error_message = "Primary region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "primary_zone" {
  description = "Primary GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.primary_zone))
    error_message = "Primary zone must be a valid GCP zone format (e.g., us-central1-a)."
  }
}

variable "secondary_region" {
  description = "Secondary GCP region for disaster recovery"
  type        = string
  default     = "us-east1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.secondary_region))
    error_message = "Secondary region must be a valid GCP region format (e.g., us-east1)."
  }
}

variable "secondary_zone" {
  description = "Secondary GCP zone for disaster recovery resources"
  type        = string
  default     = "us-east1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.secondary_zone))
    error_message = "Secondary zone must be a valid GCP zone format (e.g., us-east1-a)."
  }
}

# Network Configuration
variable "primary_vpc_cidr" {
  description = "CIDR block for primary region VPC subnet"
  type        = string
  default     = "10.1.0.0/16"
  validation {
    condition     = can(cidrhost(var.primary_vpc_cidr, 0))
    error_message = "Primary VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "secondary_vpc_cidr" {
  description = "CIDR block for secondary region VPC subnet"
  type        = string
  default     = "10.2.0.0/16"
  validation {
    condition     = can(cidrhost(var.secondary_vpc_cidr, 0))
    error_message = "Secondary VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "enable_cloud_nat" {
  description = "Enable Cloud NAT for private instances"
  type        = bool
  default     = true
}

# Parallelstore Configuration
variable "parallelstore_capacity_gib" {
  description = "Capacity of Parallelstore instances in GiB (minimum 12000 GiB)"
  type        = number
  default     = 12000
  validation {
    condition     = var.parallelstore_capacity_gib >= 12000
    error_message = "Parallelstore capacity must be at least 12000 GiB."
  }
}

variable "parallelstore_deployment_type" {
  description = "Deployment type for Parallelstore (SCRATCH or PERSISTENT)"
  type        = string
  default     = "PERSISTENT"
  validation {
    condition     = contains(["SCRATCH", "PERSISTENT"], var.parallelstore_deployment_type)
    error_message = "Deployment type must be either SCRATCH or PERSISTENT."
  }
}

variable "parallelstore_file_stripe_level" {
  description = "File stripe level for Parallelstore performance optimization"
  type        = string
  default     = "FILE_STRIPE_LEVEL_BALANCED"
  validation {
    condition = contains([
      "FILE_STRIPE_LEVEL_UNSPECIFIED",
      "FILE_STRIPE_LEVEL_MIN",
      "FILE_STRIPE_LEVEL_BALANCED",
      "FILE_STRIPE_LEVEL_MAX"
    ], var.parallelstore_file_stripe_level)
    error_message = "File stripe level must be a valid Parallelstore stripe level."
  }
}

variable "parallelstore_directory_stripe_level" {
  description = "Directory stripe level for Parallelstore performance optimization"
  type        = string
  default     = "DIRECTORY_STRIPE_LEVEL_BALANCED"
  validation {
    condition = contains([
      "DIRECTORY_STRIPE_LEVEL_UNSPECIFIED",
      "DIRECTORY_STRIPE_LEVEL_MIN",
      "DIRECTORY_STRIPE_LEVEL_BALANCED",
      "DIRECTORY_STRIPE_LEVEL_MAX"
    ], var.parallelstore_directory_stripe_level)
    error_message = "Directory stripe level must be a valid Parallelstore stripe level."
  }
}

# VPN Configuration
variable "vpn_shared_secret" {
  description = "Shared secret for VPN tunnels (leave empty for auto-generation)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "bgp_asn_primary" {
  description = "BGP ASN for primary region router"
  type        = number
  default     = 64512
  validation {
    condition     = var.bgp_asn_primary >= 64512 && var.bgp_asn_primary <= 65534
    error_message = "BGP ASN must be in the private range 64512-65534."
  }
}

variable "bgp_asn_secondary" {
  description = "BGP ASN for secondary region router"
  type        = number
  default     = 64513
  validation {
    condition     = var.bgp_asn_secondary >= 64512 && var.bgp_asn_secondary <= 65534
    error_message = "BGP ASN must be in the private range 64512-65534."
  }
}

# Cloud Functions Configuration
variable "health_monitor_memory" {
  description = "Memory allocation for health monitoring Cloud Function (MB)"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.health_monitor_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "health_monitor_timeout" {
  description = "Timeout for health monitoring Cloud Function (seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.health_monitor_timeout >= 1 && var.health_monitor_timeout <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

variable "replication_function_memory" {
  description = "Memory allocation for replication Cloud Function (MB)"
  type        = number
  default     = 1024
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.replication_function_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "replication_function_timeout" {
  description = "Timeout for replication Cloud Function (seconds)"
  type        = number
  default     = 900
  validation {
    condition     = var.replication_function_timeout >= 1 && var.replication_function_timeout <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

# Pub/Sub Configuration
variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub topics (seconds)"
  type        = string
  default     = "86400s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., 86400s)."
  }
}

# Monitoring Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring with custom metrics"
  type        = bool
  default     = true
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

variable "replication_lag_threshold_minutes" {
  description = "Threshold for replication lag alerts (minutes)"
  type        = number
  default     = 15
  validation {
    condition     = var.replication_lag_threshold_minutes > 0 && var.replication_lag_threshold_minutes <= 60
    error_message = "Replication lag threshold must be between 1 and 60 minutes."
  }
}

# Cloud Scheduler Configuration
variable "replication_schedule" {
  description = "Cron schedule for automated replication (every 15 minutes by default)"
  type        = string
  default     = "*/15 * * * *"
  validation {
    condition     = can(regex("^[0-9\\*/,-]+\\s+[0-9\\*/,-]+\\s+[0-9\\*/,-]+\\s+[0-9\\*/,-]+\\s+[0-9\\*/,-]+$", var.replication_schedule))
    error_message = "Replication schedule must be a valid cron expression."
  }
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "hpc-dr"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_suffix" {
  description = "Suffix for resource names (leave empty for auto-generation)"
  type        = string
  default     = ""
}

# Labels and Tagging
variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "disaster-recovery"
    managed-by  = "terraform"
    environment = "production"
  }
}

# Security Configuration
variable "enable_deletion_protection" {
  description = "Enable deletion protection on critical resources"
  type        = bool
  default     = true
}

variable "enable_audit_logging" {
  description = "Enable audit logging for all supported services"
  type        = bool
  default     = true
}

# Cost Optimization
variable "enable_preemptible_instances" {
  description = "Use preemptible instances for non-critical components"
  type        = bool
  default     = false
}