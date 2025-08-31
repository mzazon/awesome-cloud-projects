# Core configuration variables for newsletter content generation system
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

# Resource naming and configuration
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "newsletter-gen"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Cloud Function configuration
variable "function_name" {
  description = "Name of the Cloud Function for newsletter generation"
  type        = string
  default     = "newsletter-generator"
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

variable "python_runtime" {
  description = "Python runtime version for the Cloud Function"
  type        = string
  default     = "python312"
  
  validation {
    condition     = contains(["python39", "python310", "python311", "python312"], var.python_runtime)
    error_message = "Python runtime must be one of: python39, python310, python311, python312."
  }
}

# Cloud Storage configuration
variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE", "REGIONAL", "MULTI_REGIONAL"
    ], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE, REGIONAL, MULTI_REGIONAL."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for the Cloud Storage bucket"
  type        = bool
  default     = true
}

variable "lifecycle_age_days" {
  description = "Number of days after which to delete old object versions"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_age_days > 0 && var.lifecycle_age_days <= 365
    error_message = "Lifecycle age must be between 1 and 365 days."
  }
}

# Cloud Scheduler configuration
variable "schedule_cron" {
  description = "Cron schedule for newsletter generation (default: every Monday at 9 AM)"
  type        = string
  default     = "0 9 * * 1"
  
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.schedule_cron))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "schedule_timezone" {
  description = "Timezone for the schedule"
  type        = string
  default     = "America/New_York"
}

variable "default_newsletter_topic" {
  description = "Default topic for newsletter generation"
  type        = string
  default     = "Weekly Marketing Insights"
}

# IAM and Security configuration
variable "enable_public_access" {
  description = "Enable public access to the Cloud Function (set to false for production)"
  type        = bool
  default     = false
}

variable "allowed_members" {
  description = "List of members allowed to invoke the Cloud Function (when public access is disabled)"
  type        = list(string)
  default     = []
}

# Vertex AI configuration
variable "vertex_ai_location" {
  description = "Location for Vertex AI resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-east4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.vertex_ai_location)
    error_message = "Vertex AI location must be a supported region."
  }
}

# Monitoring and alerting
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for alerts and notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address or empty string."
  }
}

# Resource labels and tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "newsletter-automation"
    managed_by  = "terraform"
    cost_center = "marketing"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Labels must use lowercase letters, numbers, underscores, and hyphens only."
  }
}