# Variables for Oracle Database@Google Cloud Enterprise Analytics with Vertex AI
# This file defines all configurable parameters for the infrastructure deployment

# ==============================================================================
# PROJECT AND LOCATION VARIABLES
# ==============================================================================

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources (Oracle Database@Google Cloud availability limited)"
  type        = string
  default     = "us-east4"
  
  validation {
    condition = contains([
      "us-east4",    # North Virginia
      "us-west1",    # Oregon  
      "europe-west2", # London
      "europe-west3"  # Frankfurt
    ], var.region)
    error_message = "Oracle Database@Google Cloud is only available in us-east4, us-west1, europe-west2, and europe-west3."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-east4-a"
}

# ==============================================================================
# ORACLE DATABASE@GOOGLE CLOUD CONFIGURATION
# ==============================================================================

variable "oracle_exadata_shape" {
  description = "The Exadata shape for Oracle infrastructure (determines compute and storage capacity)"
  type        = string
  default     = "Exadata.X9M"
  
  validation {
    condition = contains([
      "Exadata.X9M",
      "Exadata.X8M", 
      "Exadata.X7M"
    ], var.oracle_exadata_shape)
    error_message = "Exadata shape must be one of: Exadata.X9M, Exadata.X8M, Exadata.X7M."
  }
}

variable "oracle_storage_count" {
  description = "Number of storage servers in the Exadata infrastructure"
  type        = number
  default     = 3
  
  validation {
    condition     = var.oracle_storage_count >= 3 && var.oracle_storage_count <= 64
    error_message = "Storage count must be between 3 and 64."
  }
}

variable "oracle_compute_count" {
  description = "Number of compute nodes in the Exadata infrastructure"
  type        = number
  default     = 2
  
  validation {
    condition     = var.oracle_compute_count >= 2 && var.oracle_compute_count <= 32
    error_message = "Compute count must be between 2 and 32."
  }
}

variable "autonomous_database_edition" {
  description = "Oracle Autonomous Database edition"
  type        = string
  default     = "ENTERPRISE_EDITION"
  
  validation {
    condition = contains([
      "STANDARD_EDITION",
      "ENTERPRISE_EDITION"
    ], var.autonomous_database_edition)
    error_message = "Database edition must be either STANDARD_EDITION or ENTERPRISE_EDITION."
  }
}

variable "autonomous_database_workload_type" {
  description = "Oracle Autonomous Database workload type"
  type        = string
  default     = "OLTP"
  
  validation {
    condition = contains([
      "OLTP",   # Online Transaction Processing
      "DW",     # Data Warehouse
      "AJD",    # Autonomous JSON Database
      "APEX"    # Oracle APEX Application Development
    ], var.autonomous_database_workload_type)
    error_message = "Workload type must be one of: OLTP, DW, AJD, APEX."
  }
}

variable "autonomous_database_compute_count" {
  description = "Number of OCPU cores for Autonomous Database"
  type        = number
  default     = 4
  
  validation {
    condition     = var.autonomous_database_compute_count >= 1 && var.autonomous_database_compute_count <= 128
    error_message = "Compute count must be between 1 and 128."
  }
}

variable "autonomous_database_storage_size_tbs" {
  description = "Storage size in terabytes for Autonomous Database"
  type        = number
  default     = 1
  
  validation {
    condition     = var.autonomous_database_storage_size_tbs >= 1 && var.autonomous_database_storage_size_tbs <= 384
    error_message = "Storage size must be between 1 and 384 TB."
  }
}

variable "autonomous_database_admin_password" {
  description = "Administrator password for Oracle Autonomous Database (12-30 chars, mixed case, numbers, special chars)"
  type        = string
  default     = "OracleAnalytics123!"
  sensitive   = true
  
  validation {
    condition = can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[!@#$%^&*()_+\\-=\\[\\]{};':\"\\\\|,.<>\\/?]).{12,30}$", var.autonomous_database_admin_password))
    error_message = "Password must be 12-30 characters with at least one lowercase letter, uppercase letter, number, and special character."
  }
}

# ==============================================================================
# VERTEX AI CONFIGURATION
# ==============================================================================

variable "vertex_ai_region" {
  description = "Region for Vertex AI resources (may differ from main region for optimal performance)"
  type        = string
  default     = "us-central1"
}

variable "vertex_notebook_machine_type" {
  description = "Machine type for Vertex AI Workbench instance"
  type        = string
  default     = "n1-standard-4"
  
  validation {
    condition = contains([
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n1-standard-8", "n1-standard-16",
      "n1-highmem-2", "n1-highmem-4", "n1-highmem-8", "n1-highmem-16",
      "n1-highcpu-4", "n1-highcpu-8", "n1-highcpu-16"
    ], var.vertex_notebook_machine_type)
    error_message = "Machine type must be a valid Compute Engine machine type."
  }
}

variable "vertex_notebook_boot_disk_size_gb" {
  description = "Boot disk size in GB for Vertex AI Workbench instance"
  type        = number
  default     = 100
  
  validation {
    condition     = var.vertex_notebook_boot_disk_size_gb >= 100 && var.vertex_notebook_boot_disk_size_gb <= 64000
    error_message = "Boot disk size must be between 100 GB and 64,000 GB."
  }
}

variable "vertex_notebook_disk_type" {
  description = "Disk type for Vertex AI Workbench instance"
  type        = string
  default     = "PD_STANDARD"
  
  validation {
    condition = contains([
      "PD_STANDARD",
      "PD_SSD",
      "PD_BALANCED"
    ], var.vertex_notebook_disk_type)
    error_message = "Disk type must be one of: PD_STANDARD, PD_SSD, PD_BALANCED."
  }
}

variable "vertex_model_display_name" {
  description = "Display name for Vertex AI model endpoint"
  type        = string
  default     = "Oracle Analytics ML Model"
}

# ==============================================================================
# BIGQUERY CONFIGURATION
# ==============================================================================

variable "bigquery_location" {
  description = "Location for BigQuery dataset (should match Oracle region for optimal performance)"
  type        = string
  default     = "us-east4"
}

variable "bigquery_dataset_id" {
  description = "ID for BigQuery dataset (will be suffixed with random string)"
  type        = string
  default     = "oracle_analytics"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.bigquery_dataset_id))
    error_message = "Dataset ID must contain only letters, numbers, and underscores."
  }
}

variable "bigquery_dataset_description" {
  description = "Description for BigQuery dataset"
  type        = string
  default     = "Enterprise Oracle Database Analytics with Vertex AI integration"
}

variable "bigquery_table_deletion_protection" {
  description = "Whether to enable deletion protection on BigQuery tables"
  type        = bool
  default     = true
}

# ==============================================================================
# CLOUD FUNCTIONS CONFIGURATION
# ==============================================================================

variable "cloud_function_memory_mb" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 512
  
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.cloud_function_memory_mb)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "cloud_function_timeout_seconds" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.cloud_function_timeout_seconds >= 1 && var.cloud_function_timeout_seconds <= 540
    error_message = "Timeout must be between 1 and 540 seconds."
  }
}

variable "cloud_scheduler_schedule" {
  description = "Cron schedule for automated pipeline execution"
  type        = string
  default     = "0 */6 * * *"  # Every 6 hours
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.cloud_scheduler_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "cloud_scheduler_timezone" {
  description = "Timezone for Cloud Scheduler"
  type        = string
  default     = "America/New_York"
}

# ==============================================================================
# MONITORING AND ALERTING CONFIGURATION
# ==============================================================================

variable "enable_monitoring_alerts" {
  description = "Whether to create monitoring alert policies"
  type        = bool
  default     = true
}

variable "oracle_cpu_alert_threshold" {
  description = "CPU utilization threshold (percentage) for Oracle database alerts"
  type        = number
  default     = 80
  
  validation {
    condition     = var.oracle_cpu_alert_threshold >= 50 && var.oracle_cpu_alert_threshold <= 100
    error_message = "CPU alert threshold must be between 50 and 100 percent."
  }
}

variable "vertex_ai_latency_alert_threshold_ms" {
  description = "Response time threshold in milliseconds for Vertex AI model alerts"
  type        = number
  default     = 5000
  
  validation {
    condition     = var.vertex_ai_latency_alert_threshold_ms >= 1000 && var.vertex_ai_latency_alert_threshold_ms <= 30000
    error_message = "Latency threshold must be between 1,000 and 30,000 milliseconds."
  }
}

variable "monitoring_notification_channels" {
  description = "List of notification channel IDs for monitoring alerts"
  type        = list(string)
  default     = []
}

# ==============================================================================
# RESOURCE NAMING AND TAGGING
# ==============================================================================

variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "oracle-analytics"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment tag for resources (e.g., dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition = contains([
      "development", "dev",
      "staging", "stage", 
      "production", "prod"
    ], var.environment)
    error_message = "Environment must be one of: development, dev, staging, stage, production, prod."
  }
}

variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default = {
    purpose    = "analytics"
    ml-ready   = "true"
    managed-by = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# ==============================================================================
# SECURITY CONFIGURATION
# ==============================================================================

variable "enable_private_google_access" {
  description = "Whether to enable Private Google Access for VPC subnets"
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Whether to enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access resources (CIDR notation)"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_ip_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "All IP ranges must be valid CIDR notation."
  }
}

# ==============================================================================
# COST OPTIMIZATION
# ==============================================================================

variable "enable_cost_optimization" {
  description = "Whether to enable cost optimization features (preemptible instances, etc.)"
  type        = bool
  default     = false
}

variable "enable_auto_scaling" {
  description = "Whether to enable auto-scaling for applicable resources"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 1 and 365 days."
  }
}