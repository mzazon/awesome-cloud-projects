# Input variables for intelligent retail inventory optimization infrastructure
# These variables control the deployment of BigQuery, Vertex AI, Cloud Run, 
# Fleet Engine, and optimization services for retail inventory management

#
# Project Configuration
#

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The primary Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-central2", "europe-north1", "europe-west1", "europe-west2", "europe-west3", 
      "europe-west4", "europe-west6", "asia-east1", "asia-east2", "asia-northeast1", 
      "asia-northeast2", "asia-northeast3", "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region with comprehensive service availability."
  }
}

variable "zone" {
  description = "The primary Google Cloud zone within the specified region"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-c]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and organization"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

#
# Naming and Resource Configuration
#

variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness (auto-generated if not provided)"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9]{0,8}$", var.resource_suffix))
    error_message = "Resource suffix must contain only lowercase letters and numbers, max 8 characters."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs automatically"
  type        = bool
  default     = true
}

#
# BigQuery Configuration
#

variable "bigquery_dataset_id" {
  description = "BigQuery dataset ID for retail analytics data"
  type        = string
  default     = "retail_analytics"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{1,1024}$", var.bigquery_dataset_id))
    error_message = "BigQuery dataset ID must contain only letters, numbers, and underscores."
  }
}

variable "bigquery_location" {
  description = "Location for BigQuery dataset (must be compatible with other resources)"
  type        = string
  default     = "US"
  
  validation {
    condition     = contains(["US", "EU", "asia-northeast1", "asia-southeast1"], var.bigquery_location)
    error_message = "BigQuery location must be US, EU, or a supported regional location."
  }
}

variable "bigquery_default_table_expiration_ms" {
  description = "Default table expiration in milliseconds (null for no expiration)"
  type        = number
  default     = null
}

variable "bigquery_delete_contents_on_destroy" {
  description = "Whether to delete BigQuery dataset contents when destroying infrastructure"
  type        = bool
  default     = false
}

#
# Cloud Storage Configuration
#

variable "storage_bucket_location" {
  description = "Location for Cloud Storage buckets"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "ASIA", "us-central1", "us-east1", "europe-west1", "asia-east1"
    ], var.storage_bucket_location)
    error_message = "Storage location must be a valid Google Cloud Storage location."
  }
}

variable "storage_bucket_storage_class" {
  description = "Default storage class for buckets"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_bucket_storage_class)
    error_message = "Storage class must be STANDARD, NEARLINE, COLDLINE, or ARCHIVE."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on Cloud Storage buckets"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age_days" {
  description = "Number of days after which to transition objects to Nearline storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.bucket_lifecycle_age_days > 0 && var.bucket_lifecycle_age_days <= 365
    error_message = "Lifecycle age must be between 1 and 365 days."
  }
}

#
# Vertex AI Configuration
#

variable "vertex_ai_region" {
  description = "Region for Vertex AI services (must support required AI services)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "europe-west1", "europe-west4", "asia-northeast1"
    ], var.vertex_ai_region)
    error_message = "Vertex AI region must support required ML services."
  }
}

variable "enable_vertex_ai_metadata_store" {
  description = "Whether to create a Vertex AI Metadata Store for ML artifact tracking"
  type        = bool
  default     = true
}

variable "enable_vertex_ai_tensorboard" {
  description = "Whether to create Vertex AI Tensorboard for model monitoring"
  type        = bool
  default     = true
}

#
# Cloud Run Configuration
#

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances per service"
  type        = number
  default     = 10
  
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances per service"
  type        = number
  default     = 0
  
  validation {
    condition     = var.cloud_run_min_instances >= 0 && var.cloud_run_min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run services"
  type        = string
  default     = "1"
  
  validation {
    condition     = contains(["0.25", "0.5", "1", "2", "4", "6", "8"], var.cloud_run_cpu)
    error_message = "CPU must be one of: 0.25, 0.5, 1, 2, 4, 6, 8."
  }
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run services"
  type        = string
  default     = "2Gi"
  
  validation {
    condition     = can(regex("^[0-9]+Gi$", var.cloud_run_memory))
    error_message = "Memory must be specified in Gi format (e.g., 2Gi, 4Gi)."
  }
}

variable "cloud_run_timeout" {
  description = "Request timeout for Cloud Run services in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.cloud_run_timeout >= 1 && var.cloud_run_timeout <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

variable "allow_unauthenticated_cloud_run" {
  description = "Whether to allow unauthenticated access to Cloud Run services"
  type        = bool
  default     = false
}

#
# Fleet Engine Configuration
#

variable "enable_fleet_engine" {
  description = "Enable Fleet Engine services (requires special Google approval)"
  type        = bool
  default     = false
}

variable "fleet_engine_provider_id" {
  description = "Fleet Engine provider ID for delivery optimization"
  type        = string
  default     = ""
  
  validation {
    condition     = var.fleet_engine_provider_id == "" || can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.fleet_engine_provider_id))
    error_message = "Fleet Engine provider ID must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

#
# Monitoring and Logging Configuration
#

variable "enable_cloud_monitoring" {
  description = "Enable Cloud Monitoring dashboards and alerts"
  type        = bool
  default     = true
}

variable "monitoring_notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.monitoring_notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.monitoring_notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain Cloud Logging entries"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

#
# Security Configuration
#

variable "enable_workload_identity" {
  description = "Enable Workload Identity for secure service account access"
  type        = bool
  default     = true
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for container image security"
  type        = bool
  default     = false
}

variable "enable_vpc_connector" {
  description = "Create VPC connector for Cloud Run private connectivity"
  type        = bool
  default     = false
}

#
# Cost Optimization Configuration
#

variable "enable_committed_use_discounts" {
  description = "Enable committed use discounts for predictable workloads"
  type        = bool
  default     = false
}

variable "enable_preemptible_instances" {
  description = "Use preemptible instances where applicable for cost savings"
  type        = bool
  default     = false
}

#
# Development and Testing Configuration
#

variable "create_sample_data" {
  description = "Create sample data for testing and development"
  type        = bool
  default     = true
}

variable "enable_debug_logging" {
  description = "Enable detailed debug logging for troubleshooting"
  type        = bool
  default     = false
}

variable "deployment_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = alltrue([for k, v in var.deployment_labels : can(regex("^[a-z0-9_-]{1,63}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}