# Core Configuration Variables
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
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming Variables
variable "name_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "health-assessment"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.name_prefix))
    error_message = "Name prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and organization"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

# GKE Cluster Configuration
variable "cluster_node_count" {
  description = "Number of nodes in the GKE cluster"
  type        = number
  default     = 3
  validation {
    condition     = var.cluster_node_count >= 1 && var.cluster_node_count <= 10
    error_message = "Node count must be between 1 and 10."
  }
}

variable "cluster_machine_type" {
  description = "Machine type for GKE cluster nodes"
  type        = string
  default     = "e2-medium"
  validation {
    condition = contains([
      "e2-medium", "e2-standard-2", "e2-standard-4",
      "n1-standard-1", "n1-standard-2", "n1-standard-4"
    ], var.cluster_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "cluster_disk_size_gb" {
  description = "Disk size in GB for GKE cluster nodes"
  type        = number
  default     = 50
  validation {
    condition     = var.cluster_disk_size_gb >= 20 && var.cluster_disk_size_gb <= 500
    error_message = "Disk size must be between 20 and 500 GB."
  }
}

variable "cluster_enable_autopilot" {
  description = "Enable GKE Autopilot mode for fully managed cluster"
  type        = bool
  default     = false
}

# Cloud Function Configuration
variable "function_runtime" {
  description = "Runtime environment for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python310", "python311", "python312",
      "nodejs18", "nodejs20", "go121"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Cloud Functions runtime."
  }
}

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 256
  validation {
    condition     = var.function_memory_mb >= 128 && var.function_memory_mb <= 8192
    error_message = "Function memory must be between 128 and 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Function execution in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

# Storage Configuration
variable "storage_bucket_location" {
  description = "Location for Cloud Storage bucket (regional or multi-regional)"
  type        = string
  default     = "US"
}

variable "storage_retention_days" {
  description = "Number of days to retain assessment reports in storage"
  type        = number
  default     = 90
  validation {
    condition     = var.storage_retention_days >= 1 && var.storage_retention_days <= 365
    error_message = "Storage retention must be between 1 and 365 days."
  }
}

# Assessment Configuration
variable "assessment_schedule" {
  description = "Cron schedule for infrastructure health assessments"
  type        = string
  default     = "0 */6 * * *"
  validation {
    condition     = can(regex("^[0-5]?[0-9] [0-2]?[0-9]|\\*(/[0-9]+)? [0-3]?[0-9]|\\*(/[0-9]+)? [0-1]?[0-9]|\\*(/[0-9]+)? [0-6]|\\*(/[0-9]+)?$", var.assessment_schedule))
    error_message = "Assessment schedule must be a valid cron expression."
  }
}

variable "enable_security_assessment" {
  description = "Enable security configuration assessment rules"
  type        = bool
  default     = true
}

variable "enable_performance_assessment" {
  description = "Enable performance optimization assessment rules"
  type        = bool
  default     = true
}

variable "enable_cost_assessment" {
  description = "Enable cost optimization assessment rules"
  type        = bool
  default     = true
}

# Monitoring and Alerting Configuration
variable "notification_email" {
  description = "Email address for critical health assessment notifications"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "alert_threshold_critical_issues" {
  description = "Number of critical issues that trigger immediate alerts"
  type        = number
  default     = 1
  validation {
    condition     = var.alert_threshold_critical_issues >= 1 && var.alert_threshold_critical_issues <= 100
    error_message = "Alert threshold must be between 1 and 100."
  }
}

# Cloud Deploy Configuration
variable "deploy_require_approval" {
  description = "Require manual approval for production deployments"
  type        = bool
  default     = true
}

variable "deploy_parallel_execution" {
  description = "Enable parallel execution of deployment stages"
  type        = bool
  default     = false
}

# Labels and Tags
variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Network Configuration
variable "enable_private_cluster" {
  description = "Enable private GKE cluster with private node IPs"
  type        = bool
  default     = true
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for GKE master nodes (private cluster only)"
  type        = string
  default     = "172.16.0.0/28"
  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0))
    error_message = "Master CIDR block must be a valid IPv4 CIDR."
  }
}

# API Enablement
variable "enable_apis" {
  description = "List of additional Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "workloadmanager.googleapis.com",
    "clouddeploy.googleapis.com",
    "monitoring.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "container.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com"
  ]
}