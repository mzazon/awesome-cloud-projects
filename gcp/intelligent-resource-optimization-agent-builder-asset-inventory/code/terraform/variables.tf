# Variable definitions for GCP Intelligent Resource Optimization with Agent Builder and Asset Inventory
# These variables allow customization of the deployment for different environments and requirements

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for resource deployment"
  type        = string
  default     = "us-central1-a"
}

variable "organization_id" {
  description = "The GCP organization ID for Cloud Asset Inventory access"
  type        = string
  
  validation {
    condition     = can(regex("^[0-9]+$", var.organization_id))
    error_message = "Organization ID must be a numeric string."
  }
}

variable "dataset_name" {
  description = "Name for the BigQuery dataset to store asset inventory data"
  type        = string
  default     = "asset_optimization"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{1,1024}$", var.dataset_name))
    error_message = "Dataset name must contain only letters, numbers, and underscores, max 1024 characters."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (will be suffixed with random string)"
  type        = string
  default     = "resource-optimizer"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "schedule_timezone" {
  description = "Timezone for the Cloud Scheduler job"
  type        = string
  default     = "America/New_York"
}

variable "export_schedule" {
  description = "Cron schedule for asset export job (default: daily at 2 AM)"
  type        = string
  default     = "0 2 * * *"
  
  validation {
    condition     = can(regex("^[0-9*,-/\\s]+$", var.export_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "asset_types" {
  description = "List of asset types to include in the inventory export"
  type        = list(string)
  default = [
    "compute.googleapis.com/Instance",
    "compute.googleapis.com/Disk",
    "storage.googleapis.com/Bucket",
    "container.googleapis.com/Cluster",
    "sqladmin.googleapis.com/Instance"
  ]
}

variable "vertex_ai_model" {
  description = "Vertex AI model to use for the agent"
  type        = string
  default     = "gemini-1.5-pro"
  
  validation {
    condition = contains([
      "gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"
    ], var.vertex_ai_model)
    error_message = "Model must be a supported Vertex AI model."
  }
}

variable "agent_temperature" {
  description = "Temperature setting for the Vertex AI agent (0.0-1.0)"
  type        = number
  default     = 0.2
  
  validation {
    condition     = var.agent_temperature >= 0.0 && var.agent_temperature <= 1.0
    error_message = "Temperature must be between 0.0 and 1.0."
  }
}

variable "agent_max_tokens" {
  description = "Maximum output tokens for the Vertex AI agent"
  type        = number
  default     = 2000
  
  validation {
    condition     = var.agent_max_tokens > 0 && var.agent_max_tokens <= 8192
    error_message = "Max tokens must be between 1 and 8192."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and organization"
  type        = string
  default     = "production"
  
  validation {
    condition = contains([
      "development", "staging", "production", "testing"
    ], var.environment)
    error_message = "Environment must be one of: development, staging, production, testing."
  }
}

variable "enable_apis" {
  description = "Whether to enable required GCP APIs automatically"
  type        = bool
  default     = true
}

variable "retention_days" {
  description = "Number of days to retain BigQuery data"
  type        = number
  default     = 90
  
  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 3650
    error_message = "Retention days must be between 1 and 3650."
  }
}

variable "monitoring_notification_channels" {
  description = "List of notification channel IDs for monitoring alerts"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    solution   = "resource-optimization"
    component  = "asset-inventory"
  }
}