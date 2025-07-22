# Variables for User Lifecycle Management with Firebase Authentication and Cloud Tasks
# This file defines all configurable parameters for the infrastructure deployment

# Project Configuration
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
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Firebase Configuration
variable "firebase_site_id" {
  description = "The Firebase Hosting site ID for the application"
  type        = string
  default     = "user-lifecycle-app"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.firebase_site_id))
    error_message = "Firebase site ID must contain only lowercase letters, numbers, and hyphens."
  }
}

# Cloud SQL Configuration
variable "db_instance_tier" {
  description = "The machine type for the Cloud SQL instance"
  type        = string
  default     = "db-f1-micro"
  
  validation {
    condition = contains([
      "db-f1-micro", "db-g1-small", "db-n1-standard-1", "db-n1-standard-2", 
      "db-n1-standard-4", "db-n1-standard-8", "db-n1-standard-16"
    ], var.db_instance_tier)
    error_message = "Database tier must be a valid Cloud SQL machine type."
  }
}

variable "db_disk_size" {
  description = "The size of the Cloud SQL instance disk in GB"
  type        = number
  default     = 10
  
  validation {
    condition     = var.db_disk_size >= 10 && var.db_disk_size <= 65536
    error_message = "Database disk size must be between 10 and 65536 GB."
  }
}

variable "db_backup_start_time" {
  description = "The start time for automated database backups (HH:MM format)"
  type        = string
  default     = "03:00"
  
  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.db_backup_start_time))
    error_message = "Backup start time must be in HH:MM format (24-hour)."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

# Cloud Run Configuration
variable "worker_service_name" {
  description = "The name for the Cloud Run worker service"
  type        = string
  default     = "lifecycle-worker"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.worker_service_name))
    error_message = "Worker service name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "worker_memory" {
  description = "Memory allocation for the Cloud Run worker service"
  type        = string
  default     = "512Mi"
  
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.worker_memory)
    error_message = "Worker memory must be a valid Cloud Run memory allocation."
  }
}

variable "worker_cpu" {
  description = "CPU allocation for the Cloud Run worker service"
  type        = string
  default     = "1"
  
  validation {
    condition = contains([
      "0.08", "0.17", "0.25", "0.33", "0.5", "0.58", "0.83", "1", "2", "4", "6", "8"
    ], var.worker_cpu)
    error_message = "Worker CPU must be a valid Cloud Run CPU allocation."
  }
}

variable "worker_timeout" {
  description = "Request timeout for the Cloud Run worker service in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.worker_timeout >= 1 && var.worker_timeout <= 3600
    error_message = "Worker timeout must be between 1 and 3600 seconds."
  }
}

variable "worker_max_instances" {
  description = "Maximum number of Cloud Run worker instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.worker_max_instances >= 1 && var.worker_max_instances <= 1000
    error_message = "Maximum instances must be between 1 and 1000."
  }
}

# Cloud Tasks Configuration
variable "task_queue_name" {
  description = "The name for the Cloud Tasks queue"
  type        = string
  default     = "user-lifecycle-queue"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.task_queue_name))
    error_message = "Task queue name must contain only letters, numbers, and hyphens."
  }
}

variable "task_max_concurrent_dispatches" {
  description = "Maximum number of concurrent task dispatches"
  type        = number
  default     = 10
  
  validation {
    condition     = var.task_max_concurrent_dispatches >= 1 && var.task_max_concurrent_dispatches <= 1000
    error_message = "Max concurrent dispatches must be between 1 and 1000."
  }
}

variable "task_max_dispatches_per_second" {
  description = "Maximum number of task dispatches per second"
  type        = number
  default     = 5
  
  validation {
    condition     = var.task_max_dispatches_per_second >= 1 && var.task_max_dispatches_per_second <= 500
    error_message = "Max dispatches per second must be between 1 and 500."
  }
}

variable "task_max_retry_duration" {
  description = "Maximum retry duration for failed tasks (in seconds)"
  type        = string
  default     = "3600s"
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.task_max_retry_duration))
    error_message = "Task max retry duration must be in format 'Ns' where N is a number."
  }
}

# Cloud Scheduler Configuration
variable "engagement_analysis_schedule" {
  description = "Cron schedule for daily engagement analysis (cron format)"
  type        = string
  default     = "0 2 * * *"
  
  validation {
    condition     = can(regex("^[0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+$", var.engagement_analysis_schedule))
    error_message = "Schedule must be in valid cron format."
  }
}

variable "retention_check_schedule" {
  description = "Cron schedule for weekly retention checks (cron format)"
  type        = string
  default     = "0 10 * * 1"
  
  validation {
    condition     = can(regex("^[0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+$", var.retention_check_schedule))
    error_message = "Schedule must be in valid cron format."
  }
}

variable "lifecycle_review_schedule" {
  description = "Cron schedule for monthly lifecycle reviews (cron format)"
  type        = string
  default     = "0 8 1 * *"
  
  validation {
    condition     = can(regex("^[0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+$", var.lifecycle_review_schedule))
    error_message = "Schedule must be in valid cron format."
  }
}

variable "scheduler_time_zone" {
  description = "Time zone for scheduled jobs"
  type        = string
  default     = "UTC"
}

# Monitoring and Logging Configuration
variable "log_retention_days" {
  description = "Number of days to retain Cloud Logging entries"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring and alerting"
  type        = bool
  default     = true
}

# Security Configuration
variable "allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "enable_audit_logs" {
  description = "Enable audit logging for security compliance"
  type        = bool
  default     = true
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "user-lifecycle"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
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

# Tags and Labels
variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    application = "user-lifecycle-management"
    component   = "backend"
    environment = "dev"
  }
  
  validation {
    condition = alltrue([
      for key, value in var.labels : 
      can(regex("^[a-z0-9_-]+$", key)) && can(regex("^[a-z0-9_-]+$", value))
    ])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}