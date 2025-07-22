# Input variables for session management infrastructure
# These variables allow customization of the deployment

variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be in format like 'us-central1'."
  }
}

variable "zone" {
  description = "Google Cloud zone for resource deployment"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+[a-z]$", var.zone))
    error_message = "Zone must be in format like 'us-central1-a'."
  }
}

variable "redis_instance_name" {
  description = "Name for the Cloud Memorystore Redis instance"
  type        = string
  default     = "session-store"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.redis_instance_name))
    error_message = "Redis instance name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "redis_memory_size_gb" {
  description = "Memory size in GB for the Redis instance"
  type        = number
  default     = 1
  validation {
    condition     = var.redis_memory_size_gb >= 1 && var.redis_memory_size_gb <= 300
    error_message = "Redis memory size must be between 1 and 300 GB."
  }
}

variable "redis_tier" {
  description = "Service tier for the Redis instance (BASIC or STANDARD_HA)"
  type        = string
  default     = "BASIC"
  validation {
    condition     = contains(["BASIC", "STANDARD_HA"], var.redis_tier)
    error_message = "Redis tier must be either 'BASIC' or 'STANDARD_HA'."
  }
}

variable "redis_version" {
  description = "Redis version to use"
  type        = string
  default     = "REDIS_7_0"
  validation {
    condition     = contains(["REDIS_6_X", "REDIS_7_0"], var.redis_version)
    error_message = "Redis version must be 'REDIS_6_X' or 'REDIS_7_0'."
  }
}

variable "function_name_prefix" {
  description = "Prefix for Cloud Function names"
  type        = string
  default     = "session-manager"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.function_name_prefix))
    error_message = "Function name prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "secret_name_prefix" {
  description = "Prefix for Secret Manager secret names"
  type        = string
  default     = "redis-connection"
  validation {
    condition     = can(regex("^[a-zA-Z]([a-zA-Z0-9_-]*[a-zA-Z0-9])?$", var.secret_name_prefix))
    error_message = "Secret name prefix must start with a letter and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "512M"
  validation {
    condition = can(regex("^[0-9]+(M|G)$", var.function_memory))
    error_message = "Function memory must be in format like '512M' or '1G'."
  }
}

variable "function_timeout" {
  description = "Timeout in seconds for Cloud Functions"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "cleanup_schedule" {
  description = "Cron schedule for session cleanup (Cloud Scheduler format)"
  type        = string
  default     = "0 */6 * * *"
  validation {
    condition = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.cleanup_schedule))
    error_message = "Cleanup schedule must be in valid cron format."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "session_ttl_hours" {
  description = "Session time-to-live in hours for cleanup function"
  type        = number
  default     = 24
  validation {
    condition     = var.session_ttl_hours >= 1 && var.session_ttl_hours <= 168
    error_message = "Session TTL must be between 1 and 168 hours (1 week)."
  }
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection for critical resources"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "session-management"
    environment = "production"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for label_key, label_value in var.labels :
      can(regex("^[a-z]([a-z0-9_-]{0,62}[a-z0-9])?$", label_key)) &&
      can(regex("^[a-z0-9_-]{0,63}$", label_value))
    ])
    error_message = "Labels must follow Google Cloud naming conventions."
  }
}