# ============================================================================
# API Schema Generation with Gemini Code Assist and Cloud Build - Variables
# ============================================================================
# This file defines all input variables for the Terraform configuration,
# providing customizable parameters for deployment across different environments.

# ============================================================================
# Core Project Configuration
# ============================================================================

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources (Cloud Functions, Cloud Build)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-central2", "europe-north1", "europe-southwest1", "europe-west1", "europe-west2", 
      "europe-west3", "europe-west4", "europe-west6", "europe-west8", "europe-west9",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-south2", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Cloud Functions."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources (if any)"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

# ============================================================================
# Environment and Naming Configuration
# ============================================================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod) for resource labeling and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "Environment must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with alphanumeric character."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for Cloud Storage bucket name (will be suffixed with random string for uniqueness)"
  type        = string
  default     = "api-schemas"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must be 3-63 characters, start and end with alphanumeric characters, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_name_prefix" {
  description = "Prefix for naming all created resources to ensure uniqueness and organization"
  type        = string
  default     = "api-schema"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_name_prefix))
    error_message = "Resource name prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with alphanumeric character."
  }
}

# ============================================================================
# Cloud Storage Configuration
# ============================================================================

variable "storage_class" {
  description = "Default storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "retention_period_days" {
  description = "Retention period for bucket objects in days (for compliance and audit purposes)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.retention_period_days >= 1 && var.retention_period_days <= 3650
    error_message = "Retention period must be between 1 and 3650 days (10 years)."
  }
}

variable "enable_versioning" {
  description = "Enable object versioning on the Cloud Storage bucket for schema history tracking"
  type        = bool
  default     = true
}

variable "enable_lifecycle_management" {
  description = "Enable lifecycle management rules for cost optimization"
  type        = bool
  default     = true
}

# ============================================================================
# Cloud Functions Configuration
# ============================================================================

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 120
  
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds (9 minutes)."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances for auto-scaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Function max instances must be between 1 and 3000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances (0 for serverless scaling)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Function min instances must be between 0 and 1000."
  }
}

variable "python_runtime" {
  description = "Python runtime version for Cloud Functions"
  type        = string
  default     = "python312"
  
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312"
    ], var.python_runtime)
    error_message = "Python runtime must be one of: python39, python310, python311, python312."
  }
}

# ============================================================================
# Cloud Build Configuration
# ============================================================================

variable "repository_name" {
  description = "Name of the repository for Cloud Build triggers (placeholder for manual triggers)"
  type        = string
  default     = "api-schema-project"
}

variable "repository_owner" {
  description = "Owner/organization of the repository (for GitHub integration)"
  type        = string
  default     = "your-github-username"
}

variable "build_machine_type" {
  description = "Machine type for Cloud Build workers"
  type        = string
  default     = "E2_MEDIUM"
  
  validation {
    condition = contains([
      "E2_MICRO", "E2_SMALL", "E2_MEDIUM", "E2_STANDARD_2", "E2_STANDARD_4", 
      "E2_STANDARD_8", "E2_STANDARD_16", "E2_STANDARD_32", "E2_HIGHCPU_2",
      "E2_HIGHCPU_4", "E2_HIGHCPU_8", "E2_HIGHCPU_16", "E2_HIGHCPU_32",
      "E2_HIGHMEM_2", "E2_HIGHMEM_4", "E2_HIGHMEM_8", "E2_HIGHMEM_16"
    ], var.build_machine_type)
    error_message = "Build machine type must be a valid Google Cloud E2 machine type."
  }
}

variable "build_disk_size_gb" {
  description = "Disk size for Cloud Build workers in GB"
  type        = number
  default     = 100
  
  validation {
    condition     = var.build_disk_size_gb >= 10 && var.build_disk_size_gb <= 2000
    error_message = "Build disk size must be between 10 and 2000 GB."
  }
}

variable "build_timeout_seconds" {
  description = "Timeout for Cloud Build jobs in seconds"
  type        = number
  default     = 1200
  
  validation {
    condition     = var.build_timeout_seconds >= 60 && var.build_timeout_seconds <= 86400
    error_message = "Build timeout must be between 60 seconds (1 minute) and 86400 seconds (24 hours)."
  }
}

# ============================================================================
# Monitoring and Alerting Configuration
# ============================================================================

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting for the pipeline"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for receiving alerts and notifications (optional)"
  type        = string
  default     = null
  
  validation {
    condition = var.notification_email == null || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address format."
  }
}

variable "alert_threshold_error_rate" {
  description = "Error rate threshold for triggering alerts (as decimal, e.g., 0.1 for 10%)"
  type        = number
  default     = 0.1
  
  validation {
    condition     = var.alert_threshold_error_rate >= 0.0 && var.alert_threshold_error_rate <= 1.0
    error_message = "Alert threshold error rate must be between 0.0 and 1.0."
  }
}

variable "alert_duration_seconds" {
  description = "Duration in seconds before triggering alerts"
  type        = number
  default     = 300
  
  validation {
    condition     = var.alert_duration_seconds >= 60 && var.alert_duration_seconds <= 3600
    error_message = "Alert duration must be between 60 seconds (1 minute) and 3600 seconds (1 hour)."
  }
}

# ============================================================================
# Logging Configuration
# ============================================================================

variable "enable_audit_logs" {
  description = "Enable audit logging for compliance and security monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Retention period for logs in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

variable "enable_log_export" {
  description = "Enable exporting logs to Cloud Storage for long-term archival"
  type        = bool
  default     = true
}

# ============================================================================
# Security and Access Control
# ============================================================================

variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access for enhanced security"
  type        = bool
  default     = true
}

variable "allowed_source_ips" {
  description = "List of allowed source IP ranges for Cloud Functions access (CIDR notation)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_source_ips : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be in valid CIDR notation (e.g., 192.168.1.0/24)."
  }
}

variable "enable_vpc_connector" {
  description = "Enable VPC connector for Cloud Functions (for private network access)"
  type        = bool
  default     = false
}

# ============================================================================
# Feature Flags and Optional Components
# ============================================================================

variable "enable_gemini_integration" {
  description = "Enable integration with Gemini Code Assist (requires appropriate licensing)"
  type        = bool
  default     = true
}

variable "enable_advanced_validation" {
  description = "Deploy advanced schema validation function with extended checks"
  type        = bool
  default     = true
}

variable "enable_build_triggers" {
  description = "Create Cloud Build triggers for automated pipeline execution"
  type        = bool
  default     = true
}

variable "enable_cost_optimization" {
  description = "Enable cost optimization features like lifecycle management and storage tiering"
  type        = bool
  default     = true
}

# ============================================================================
# Development and Testing Configuration
# ============================================================================

variable "deployment_mode" {
  description = "Deployment mode (development, staging, production) affecting resource sizing and policies"
  type        = string
  default     = "development"
  
  validation {
    condition = contains([
      "development", "staging", "production"
    ], var.deployment_mode)
    error_message = "Deployment mode must be one of: development, staging, production."
  }
}

variable "enable_debug_logging" {
  description = "Enable debug-level logging for troubleshooting (not recommended for production)"
  type        = bool
  default     = false
}

variable "skip_api_enablement" {
  description = "Skip enabling Google Cloud APIs (useful when APIs are already enabled)"
  type        = bool
  default     = false
}

# ============================================================================
# Resource Tagging and Organization
# ============================================================================

variable "additional_labels" {
  description = "Additional labels to apply to all resources for organization and cost tracking"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens (max 63 characters)."
  }
  
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label values must contain only lowercase letters, numbers, underscores, and hyphens (max 63 characters)."
  }
}

variable "cost_center" {
  description = "Cost center or billing code for resource attribution"
  type        = string
  default     = ""
}

variable "owner" {
  description = "Owner or team responsible for the resources"
  type        = string
  default     = ""
}

variable "project_code" {
  description = "Project code for organizational tracking"
  type        = string
  default     = ""
}

# ============================================================================
# Advanced Configuration Options
# ============================================================================

variable "custom_service_account_emails" {
  description = "Custom service account emails for functions (if not using auto-created ones)"
  type = object({
    cloud_functions = optional(string)
    cloud_build     = optional(string)
  })
  default = {}
}

variable "function_source_bucket" {
  description = "Custom Cloud Storage bucket for function source code (if not using the main bucket)"
  type        = string
  default     = ""
}

variable "enable_private_google_access" {
  description = "Enable private Google access for enhanced security"
  type        = bool
  default     = false
}

variable "network_project_id" {
  description = "Project ID containing the VPC network (for shared VPC scenarios)"
  type        = string
  default     = ""
}

variable "subnet_name" {
  description = "Subnet name for VPC connector (if enabled)"
  type        = string
  default     = ""
}