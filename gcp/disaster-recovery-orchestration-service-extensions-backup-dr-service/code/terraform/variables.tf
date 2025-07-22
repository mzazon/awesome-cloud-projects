# variables.tf
# Input variables for the disaster recovery orchestration infrastructure

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "primary_region" {
  description = "Primary region for the application infrastructure"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.primary_region))
    error_message = "Primary region must be a valid GCP region name."
  }
}

variable "primary_zone" {
  description = "Primary zone within the primary region"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.primary_zone))
    error_message = "Primary zone must be a valid GCP zone name."
  }
}

variable "dr_region" {
  description = "Disaster recovery region for failover infrastructure"
  type        = string
  default     = "us-east1"
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.dr_region))
    error_message = "DR region must be a valid GCP region name."
  }
}

variable "dr_zone" {
  description = "Disaster recovery zone within the DR region"
  type        = string
  default     = "us-east1-a"
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.dr_zone))
    error_message = "DR zone must be a valid GCP zone name."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_suffix" {
  description = "Random suffix for resource names to ensure uniqueness"
  type        = string
  default     = ""
}

variable "primary_instance_count" {
  description = "Number of instances in the primary application group"
  type        = number
  default     = 2
  validation {
    condition = var.primary_instance_count >= 1 && var.primary_instance_count <= 10
    error_message = "Primary instance count must be between 1 and 10."
  }
}

variable "dr_initial_instance_count" {
  description = "Initial number of instances in the DR application group (usually 0 for cost efficiency)"
  type        = number
  default     = 0
  validation {
    condition = var.dr_initial_instance_count >= 0 && var.dr_initial_instance_count <= 10
    error_message = "DR initial instance count must be between 0 and 10."
  }
}

variable "machine_type" {
  description = "Machine type for application instances"
  type        = string
  default     = "e2-micro"
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.machine_type))
    error_message = "Machine type must be a valid GCP machine type."
  }
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  validation {
    condition = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

variable "failure_threshold" {
  description = "Number of failures before triggering disaster recovery"
  type        = number
  default     = 5
  validation {
    condition = var.failure_threshold >= 1 && var.failure_threshold <= 20
    error_message = "Failure threshold must be between 1 and 20."
  }
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 10
  validation {
    condition = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
  validation {
    condition = var.health_check_timeout >= 1 && var.health_check_timeout <= 60
    error_message = "Health check timeout must be between 1 and 60 seconds."
  }
}

variable "enable_monitoring" {
  description = "Enable monitoring and alerting for the disaster recovery system"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for disaster recovery notifications"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    terraform   = "true"
    solution    = "disaster-recovery-orchestration"
    cost-center = "infrastructure"
  }
}