# Variables for multi-tenant resource scheduling infrastructure
# These variables allow customization of the deployment for different environments

variable "project_id" {
  type        = string
  description = "The Google Cloud project ID where resources will be created"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  type        = string
  description = "The Google Cloud region for resource deployment"
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "zone" {
  type        = string
  description = "The Google Cloud zone for zonal resources"
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "environment" {
  type        = string
  description = "Environment name for resource naming and tagging"
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_suffix" {
  type        = string
  description = "Unique suffix for resource names to avoid conflicts"
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.resource_suffix))
    error_message = "Resource suffix must contain only lowercase letters, numbers, and hyphens."
  }
}

# Filestore Configuration Variables
variable "filestore_capacity_gb" {
  type        = number
  description = "Capacity of the Cloud Filestore instance in GB"
  default     = 1024
  
  validation {
    condition     = var.filestore_capacity_gb >= 1024 && var.filestore_capacity_gb <= 65536
    error_message = "Filestore capacity must be between 1024 GB and 65536 GB for BASIC_HDD tier."
  }
}

variable "filestore_tier" {
  type        = string
  description = "Performance tier for Cloud Filestore instance"
  default     = "BASIC_HDD"
  
  validation {
    condition     = contains(["BASIC_HDD", "BASIC_SSD", "HIGH_SCALE_SSD", "ZONAL", "REGIONAL"], var.filestore_tier)
    error_message = "Filestore tier must be one of: BASIC_HDD, BASIC_SSD, HIGH_SCALE_SSD, ZONAL, REGIONAL."
  }
}

variable "filestore_share_name" {
  type        = string
  description = "Name of the file share on the Filestore instance"
  default     = "tenant_storage"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.filestore_share_name))
    error_message = "File share name must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

# Cloud Function Configuration Variables
variable "function_memory_mb" {
  type        = number
  description = "Memory allocation for Cloud Function in MB"
  default     = 512
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout_seconds" {
  type        = number
  description = "Timeout for Cloud Function execution in seconds"
  default     = 300
  
  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 3600
    error_message = "Function timeout must be between 60 and 3600 seconds."
  }
}

variable "function_runtime" {
  type        = string
  description = "Runtime for the Cloud Function"
  default     = "python311"
  
  validation {
    condition     = contains(["python39", "python310", "python311", "python312"], var.function_runtime)
    error_message = "Function runtime must be one of the supported Python versions."
  }
}

# Tenant Configuration Variables
variable "tenant_quotas" {
  type        = map(number)
  description = "Resource quotas for each tenant"
  default = {
    tenant_a = 10
    tenant_b = 15
    tenant_c = 8
    default  = 5
  }
  
  validation {
    condition     = alltrue([for quota in values(var.tenant_quotas) : quota > 0 && quota <= 100])
    error_message = "All tenant quotas must be between 1 and 100."
  }
}

# Monitoring Configuration Variables
variable "enable_monitoring" {
  type        = bool
  description = "Enable Cloud Monitoring alerts and dashboard"
  default     = true
}

variable "quota_alert_threshold" {
  type        = number
  description = "Threshold percentage for quota violation alerts"
  default     = 80
  
  validation {
    condition     = var.quota_alert_threshold >= 50 && var.quota_alert_threshold <= 95
    error_message = "Quota alert threshold must be between 50 and 95 percent."
  }
}

# Scheduler Configuration Variables
variable "scheduler_timezone" {
  type        = string
  description = "Timezone for Cloud Scheduler jobs"
  default     = "America/New_York"
}

variable "enable_scheduled_jobs" {
  type        = bool
  description = "Enable automated Cloud Scheduler jobs"
  default     = true
}

# Network Configuration Variables
variable "network_name" {
  type        = string
  description = "Name of the VPC network for resources"
  default     = "default"
}

variable "enable_apis" {
  type        = bool
  description = "Enable required Google Cloud APIs"
  default     = true
}

# Tagging and Labeling Variables
variable "labels" {
  type        = map(string)
  description = "Labels to apply to all resources"
  default = {
    managed_by = "terraform"
    purpose    = "multi-tenant-scheduling"
  }
  
  validation {
    condition = alltrue([
      for key, value in var.labels : 
      can(regex("^[a-z][a-z0-9_-]*$", key)) && 
      can(regex("^[a-z0-9_-]*$", value)) &&
      length(key) <= 63 && 
      length(value) <= 63
    ])
    error_message = "Label keys and values must follow Google Cloud labeling conventions."
  }
}

# Security Configuration Variables
variable "allow_unauthenticated_function" {
  type        = bool
  description = "Allow unauthenticated access to Cloud Function (not recommended for production)"
  default     = false
}

variable "function_service_account_email" {
  type        = string
  description = "Email of custom service account for Cloud Function (optional)"
  default     = ""
}

# Cost Management Variables
variable "budget_amount" {
  type        = number
  description = "Monthly budget amount in USD for cost monitoring"
  default     = 100
  
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}