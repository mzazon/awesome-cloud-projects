# Variables for AlloyDB AI Performance Automation Infrastructure
# These variables allow customization of the deployment while maintaining security and best practices

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 6 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must be valid Google Cloud project identifier."
  }
}

variable "region" {
  description = "The Google Cloud region for deploying resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region with AlloyDB support."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "alloydb-perf"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# AlloyDB Configuration Variables
variable "alloydb_cluster_id" {
  description = "Unique identifier for the AlloyDB cluster"
  type        = string
  default     = ""
}

variable "alloydb_instance_type" {
  description = "Machine type for AlloyDB primary instance"
  type        = string
  default     = "alloydb-omni-medium"
  
  validation {
    condition = contains([
      "alloydb-omni-medium", "alloydb-omni-large", "alloydb-omni-xlarge"
    ], var.alloydb_instance_type)
    error_message = "Instance type must be a valid AlloyDB machine type."
  }
}

variable "alloydb_cpu_count" {
  description = "Number of vCPUs for AlloyDB instance"
  type        = number
  default     = 4
  
  validation {
    condition     = var.alloydb_cpu_count >= 2 && var.alloydb_cpu_count <= 128
    error_message = "CPU count must be between 2 and 128."
  }
}

variable "alloydb_memory_size_gb" {
  description = "Memory size in GB for AlloyDB instance"
  type        = number
  default     = 16
  
  validation {
    condition     = var.alloydb_memory_size_gb >= 4 && var.alloydb_memory_size_gb <= 864
    error_message = "Memory size must be between 4 and 864 GB."
  }
}

variable "alloydb_availability_type" {
  description = "Availability configuration for AlloyDB cluster"
  type        = string
  default     = "ZONAL"
  
  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.alloydb_availability_type)
    error_message = "Availability type must be either ZONAL or REGIONAL."
  }
}

variable "alloydb_backup_enabled" {
  description = "Enable automated backups for AlloyDB cluster"
  type        = bool
  default     = true
}

variable "alloydb_backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.alloydb_backup_retention_days >= 1 && var.alloydb_backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}

# Network Configuration Variables
variable "vpc_cidr_range" {
  description = "CIDR range for the VPC subnet"
  type        = string
  default     = "10.0.0.0/24"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr_range, 0))
    error_message = "VPC CIDR range must be a valid CIDR notation."
  }
}

variable "private_service_cidr" {
  description = "CIDR range for private service connection"
  type        = string
  default     = "10.1.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.private_service_cidr, 0))
    error_message = "Private service CIDR must be a valid CIDR notation."
  }
}

# Cloud Functions Configuration Variables
variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be a valid Cloud Functions memory size."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 540
  
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

# Monitoring and Alerting Configuration
variable "monitoring_enabled" {
  description = "Enable Cloud Monitoring integration"
  type        = bool
  default     = true
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

variable "performance_threshold_latency_ms" {
  description = "Query latency threshold in milliseconds for alerts"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.performance_threshold_latency_ms > 0
    error_message = "Performance threshold must be positive."
  }
}

# Vertex AI Configuration Variables
variable "vertex_ai_region" {
  description = "Region for Vertex AI resources"
  type        = string
  default     = ""
}

variable "ai_model_display_name" {
  description = "Display name for the AI performance model"
  type        = string
  default     = "alloydb-performance-optimizer"
}

variable "ai_training_budget_hours" {
  description = "Training budget in node hours for AutoML model"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.ai_training_budget_hours >= 100 && var.ai_training_budget_hours <= 10000
    error_message = "Training budget must be between 100 and 10000 node hours."
  }
}

# Scheduling Configuration
variable "performance_analysis_schedule" {
  description = "Cron schedule for performance analysis (default: every 15 minutes)"
  type        = string
  default     = "*/15 * * * *"
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.performance_analysis_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "daily_report_schedule" {
  description = "Cron schedule for daily performance reports (default: 9 AM daily)"
  type        = string
  default     = "0 9 * * *"
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.daily_report_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "timezone" {
  description = "Timezone for scheduled jobs"
  type        = string
  default     = "America/New_York"
}

# Security and Access Configuration
variable "enable_iam_authentication" {
  description = "Enable IAM authentication for AlloyDB"
  type        = bool
  default     = true
}

variable "authorized_networks" {
  description = "List of authorized networks for database access"
  type        = list(string)
  default     = []
}

# Resource Tagging
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "database-performance-automation"
    managed-by  = "terraform"
    component   = "alloydb-ai-optimization"
  }
  
  validation {
    condition     = can([for k, v in var.labels : regex("^[a-z][a-z0-9_-]*$", k)])
    error_message = "Label keys must start with lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Cost Control Variables
variable "enable_cost_alerts" {
  description = "Enable cost monitoring and alerts"
  type        = bool
  default     = true
}

variable "daily_cost_budget_usd" {
  description = "Daily cost budget in USD for alerts"
  type        = number
  default     = 100
  
  validation {
    condition     = var.daily_cost_budget_usd > 0
    error_message = "Daily cost budget must be positive."
  }
}