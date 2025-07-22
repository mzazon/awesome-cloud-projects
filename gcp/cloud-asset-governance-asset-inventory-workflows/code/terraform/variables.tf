# Input Variables for Cloud Asset Governance Infrastructure
# This file defines all configurable parameters for the governance system

# Core Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where governance resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "organization_id" {
  description = "The Google Cloud organization ID for asset monitoring"
  type        = string
  
  validation {
    condition     = can(regex("^[0-9]+$", var.organization_id))
    error_message = "Organization ID must be a numeric string."
  }
}

# Regional Configuration
variable "region" {
  description = "The Google Cloud region for deploying regional resources"
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
  description = "The Google Cloud zone for deploying zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Governance System Configuration
variable "governance_suffix" {
  description = "Unique suffix for governance resource names to avoid conflicts"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.governance_suffix))
    error_message = "Governance suffix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "asset_types_to_monitor" {
  description = "List of Google Cloud asset types to monitor for governance"
  type        = list(string)
  default = [
    "storage.googleapis.com/Bucket",
    "compute.googleapis.com/Instance",
    "bigquery.googleapis.com/Dataset",
    "compute.googleapis.com/Disk",
    "iam.googleapis.com/ServiceAccount"
  ]
}

# Retention and Compliance Settings
variable "message_retention_days" {
  description = "Number of days to retain Pub/Sub messages for audit purposes"
  type        = number
  default     = 7
  
  validation {
    condition     = var.message_retention_days >= 1 && var.message_retention_days <= 31
    error_message = "Message retention days must be between 1 and 31."
  }
}

variable "bigquery_location" {
  description = "Location for BigQuery dataset (must be compatible with chosen region)"
  type        = string
  default     = "US"
  
  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid multi-region or single region location."
  }
}

# Cloud Function Configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
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

variable "max_function_instances" {
  description = "Maximum number of function instances for auto-scaling"
  type        = number
  default     = 20
  
  validation {
    condition     = var.max_function_instances >= 1 && var.max_function_instances <= 1000
    error_message = "Maximum function instances must be between 1 and 1000."
  }
}

# Storage Configuration
variable "storage_class" {
  description = "Storage class for governance artifacts bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on governance storage bucket for audit trail"
  type        = bool
  default     = true
}

# Security and IAM Configuration
variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access for governance storage"
  type        = bool
  default     = true
}

variable "governance_labels" {
  description = "Labels to apply to all governance resources for organization and billing"
  type        = map(string)
  default = {
    purpose     = "governance"
    managed-by  = "terraform"
    environment = "production"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.governance_labels : 
      can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && 
      can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Labels must have keys starting with lowercase letter (1-63 chars) and values of lowercase letters, numbers, underscores, hyphens (0-63 chars)."
  }
}

# Monitoring and Alerting Configuration
variable "enable_monitoring_alerts" {
  description = "Enable Cloud Monitoring alerts for governance violations"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for governance violation notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Workflow Configuration
variable "workflow_description" {
  description = "Description for the governance orchestration workflow"
  type        = string
  default     = "Automated governance workflow for asset compliance monitoring and policy enforcement"
}

# API Services to Enable
variable "required_apis" {
  description = "List of Google Cloud APIs required for governance system"
  type        = list(string)
  default = [
    "cloudasset.googleapis.com",
    "workflows.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]
}

# Asset Feed Configuration
variable "content_type" {
  description = "Content type for Cloud Asset Inventory feed"
  type        = string
  default     = "RESOURCE"
  
  validation {
    condition = contains([
      "CONTENT_TYPE_UNSPECIFIED", "RESOURCE", "IAM_POLICY", "ORG_POLICY", "ACCESS_POLICY"
    ], var.content_type)
    error_message = "Content type must be one of: CONTENT_TYPE_UNSPECIFIED, RESOURCE, IAM_POLICY, ORG_POLICY, ACCESS_POLICY."
  }
}

# Development and Testing Configuration
variable "enable_local_testing" {
  description = "Enable local testing features for development environments"
  type        = bool
  default     = false
}