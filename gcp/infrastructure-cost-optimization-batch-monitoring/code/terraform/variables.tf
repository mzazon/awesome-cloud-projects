# Input variables for GCP Infrastructure Cost Optimization solution
#
# This file defines all configurable parameters for the cost optimization infrastructure,
# including resource names, locations, scheduling configurations, and optimization policies.

# ==============================================================================
# PROJECT AND LOCATION CONFIGURATION
# ==============================================================================

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for compute resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

# ==============================================================================
# ENVIRONMENT AND NAMING CONFIGURATION
# ==============================================================================

variable "environment" {
  description = "Environment name for resource labeling and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "application_name" {
  description = "Application name for resource naming and labeling"
  type        = string
  default     = "cost-optimization"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.application_name))
    error_message = "Application name must be 3-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness (leave empty for auto-generation)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.resource_suffix == "" || can(regex("^[a-z0-9]{1,8}$", var.resource_suffix))
    error_message = "Resource suffix must be empty or 1-8 characters containing only lowercase letters and numbers."
  }
}

# ==============================================================================
# COST OPTIMIZATION CONFIGURATION
# ==============================================================================

variable "optimization_schedule" {
  description = "Cron schedule for automated cost optimization analysis"
  type        = string
  default     = "0 2 * * *"  # Daily at 2 AM
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.optimization_schedule))
    error_message = "Schedule must be a valid cron expression (e.g., '0 2 * * *')."
  }
}

variable "batch_analysis_schedule" {
  description = "Cron schedule for comprehensive batch analysis"
  type        = string
  default     = "0 3 * * 0"  # Weekly on Sunday at 3 AM
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.batch_analysis_schedule))
    error_message = "Schedule must be a valid cron expression (e.g., '0 3 * * 0')."
  }
}

variable "cpu_utilization_threshold" {
  description = "CPU utilization threshold below which resources are considered underutilized (0.0-1.0)"
  type        = number
  default     = 0.1
  
  validation {
    condition     = var.cpu_utilization_threshold >= 0.01 && var.cpu_utilization_threshold <= 1.0
    error_message = "CPU utilization threshold must be between 0.01 and 1.0."
  }
}

variable "memory_utilization_threshold" {
  description = "Memory utilization threshold below which resources are considered underutilized (0.0-1.0)"
  type        = number
  default     = 0.2
  
  validation {
    condition     = var.memory_utilization_threshold >= 0.01 && var.memory_utilization_threshold <= 1.0
    error_message = "Memory utilization threshold must be between 0.01 and 1.0."
  }
}

variable "monitoring_duration" {
  description = "Duration (in seconds) for monitoring thresholds before triggering alerts"
  type        = number
  default     = 300
  
  validation {
    condition     = var.monitoring_duration >= 60 && var.monitoring_duration <= 3600
    error_message = "Monitoring duration must be between 60 and 3600 seconds."
  }
}

# ==============================================================================
# CLOUD BATCH CONFIGURATION
# ==============================================================================

variable "batch_job_timeout" {
  description = "Timeout for batch jobs in seconds"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.batch_job_timeout >= 300 && var.batch_job_timeout <= 86400
    error_message = "Batch job timeout must be between 300 (5 minutes) and 86400 (24 hours) seconds."
  }
}

variable "batch_machine_type" {
  description = "Machine type for Cloud Batch compute resources"
  type        = string
  default     = "e2-standard-2"
  
  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4", "e2-standard-8",
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n2-standard-2", "n2-standard-4"
    ], var.batch_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "enable_preemptible_instances" {
  description = "Enable preemptible instances for cost optimization (recommended for batch workloads)"
  type        = bool
  default     = true
}

variable "batch_parallelism" {
  description = "Number of parallel batch tasks to run simultaneously"
  type        = number
  default     = 1
  
  validation {
    condition     = var.batch_parallelism >= 1 && var.batch_parallelism <= 10
    error_message = "Batch parallelism must be between 1 and 10."
  }
}

# ==============================================================================
# STORAGE CONFIGURATION
# ==============================================================================

variable "storage_class" {
  description = "Default storage class for cost optimization data"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "data_retention_days" {
  description = "Number of days to retain cost optimization data"
  type        = number
  default     = 90
  
  validation {
    condition     = var.data_retention_days >= 7 && var.data_retention_days <= 2555  # ~7 years
    error_message = "Data retention must be between 7 and 2555 days."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for storage buckets"
  type        = bool
  default     = true
}

# ==============================================================================
# BIGQUERY CONFIGURATION
# ==============================================================================

variable "bigquery_location" {
  description = "Location for BigQuery dataset (must match region for optimal performance)"
  type        = string
  default     = ""  # Will default to var.region if empty
}

variable "bigquery_table_expiration_days" {
  description = "Default table expiration in days for cost optimization tables"
  type        = number
  default     = 365
  
  validation {
    condition     = var.bigquery_table_expiration_days >= 1 && var.bigquery_table_expiration_days <= 2555
    error_message = "BigQuery table expiration must be between 1 and 2555 days."
  }
}

variable "enable_bigquery_encryption" {
  description = "Enable customer-managed encryption for BigQuery dataset"
  type        = bool
  default     = false
}

# ==============================================================================
# CLOUD FUNCTIONS CONFIGURATION
# ==============================================================================

variable "function_memory" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 540
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 10
    error_message = "Function minimum instances must be between 0 and 10."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function maximum instances must be between 1 and 1000."
  }
}

# ==============================================================================
# SECURITY AND ACCESS CONFIGURATION
# ==============================================================================

variable "enable_audit_logging" {
  description = "Enable audit logging for all cost optimization resources"
  type        = bool
  default     = true
}

variable "allowed_members" {
  description = "List of members (users/groups/service accounts) allowed to access cost optimization resources"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for member in var.allowed_members : 
      can(regex("^(user:|group:|serviceAccount:|domain:)", member))
    ])
    error_message = "All members must be prefixed with user:, group:, serviceAccount:, or domain:."
  }
}

variable "enable_vpc_connector" {
  description = "Enable VPC connector for Cloud Functions (required for private network access)"
  type        = bool
  default     = false
}

# ==============================================================================
# LABELING AND TAGGING
# ==============================================================================

variable "cost_center" {
  description = "Cost center for billing and chargeback purposes"
  type        = string
  default     = "engineering"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.cost_center))
    error_message = "Cost center must be 3-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "owner" {
  description = "Owner or team responsible for the cost optimization infrastructure"
  type        = string
  default     = "platform-team"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.owner))
    error_message = "Owner must be 3-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : 
      can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label keys and values must follow Google Cloud labeling conventions."
  }
}

# ==============================================================================
# FEATURE FLAGS
# ==============================================================================

variable "enable_monitoring_alerts" {
  description = "Enable Cloud Monitoring alert policies for cost optimization"
  type        = bool
  default     = true
}

variable "enable_scheduler_jobs" {
  description = "Enable Cloud Scheduler jobs for automated optimization"
  type        = bool
  default     = true
}

variable "enable_pubsub_dead_letter" {
  description = "Enable dead letter queues for Pub/Sub subscriptions"
  type        = bool
  default     = true
}

variable "enable_cost_anomaly_detection" {
  description = "Enable advanced cost anomaly detection features"
  type        = bool
  default     = false
}