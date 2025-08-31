# Project configuration variables
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
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource naming variables
variable "function_name" {
  description = "Name of the Cloud Function for email validation"
  type        = string
  default     = "email-validator"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a lowercase letter, followed by lowercase letters, numbers, or hyphens, and end with a lowercase letter or number."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (will be made globally unique)"
  type        = string
  default     = "email-validation-logs"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens, and cannot start or end with a hyphen."
  }
}

# Cloud Function configuration variables
variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function"
  type        = string
  default     = "256M"
  
  validation {
    condition = contains([
      "128M", "256M", "512M", "1024M", "2048M", "4096M", "8192M"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128M, 256M, 512M, 1024M, 2048M, 4096M, 8192M."
  }
}

variable "max_instances" {
  description = "Maximum number of function instances that can run in parallel"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "min_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 100
    error_message = "Min instances must be between 0 and 100."
  }
}

# Storage configuration variables
variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "lifecycle_age_nearline" {
  description = "Age in days after which objects transition to NEARLINE storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_age_nearline >= 0 && var.lifecycle_age_nearline <= 365
    error_message = "Lifecycle age for NEARLINE must be between 0 and 365 days."
  }
}

variable "lifecycle_age_delete" {
  description = "Age in days after which objects are deleted"
  type        = number
  default     = 365
  
  validation {
    condition     = var.lifecycle_age_delete >= 1 && var.lifecycle_age_delete <= 3650
    error_message = "Lifecycle age for deletion must be between 1 and 3650 days (10 years)."
  }
}

# Security and access variables
variable "allow_unauthenticated_invocations" {
  description = "Whether to allow unauthenticated invocations of the Cloud Function"
  type        = bool
  default     = true
}

variable "enable_uniform_bucket_access" {
  description = "Enable uniform bucket-level access for enhanced security"
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Enable object versioning for the Cloud Storage bucket"
  type        = bool
  default     = true
}

# Environment and runtime variables
variable "python_runtime" {
  description = "Python runtime version for the Cloud Function"
  type        = string
  default     = "python311"
  
  validation {
    condition = contains([
      "python37", "python38", "python39", "python310", "python311"
    ], var.python_runtime)
    error_message = "Python runtime must be one of the supported versions: python37, python38, python39, python310, python311."
  }
}

variable "entry_point" {
  description = "Entry point function name in the Cloud Function code"
  type        = string
  default     = "validate_email"
}

# Labels and tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    application = "email-validation"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for key, value in var.labels :
      can(regex("^[a-z0-9_-]+$", key)) && can(regex("^[a-z0-9_-]+$", value))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Cost optimization variables
variable "enable_cost_optimization" {
  description = "Enable cost optimization features like lifecycle policies"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain Cloud Function logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}