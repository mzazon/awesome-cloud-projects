# variables.tf - Input variables for Enterprise Migration Assessment infrastructure
# This file defines all configurable parameters for the migration assessment solution

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "migration_project_name" {
  description = "Name of the migration project for resource naming and tagging"
  type        = string
  default     = "enterprise-migration"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.migration_project_name))
    error_message = "Migration project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "enable_continuous_export" {
  description = "Enable continuous export of discovery data to S3"
  type        = bool
  default     = true
}

variable "data_retention_days" {
  description = "Number of days to retain discovery data in S3"
  type        = number
  default     = 90
  
  validation {
    condition     = var.data_retention_days >= 30 && var.data_retention_days <= 365
    error_message = "Data retention must be between 30 and 365 days."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on S3 bucket for data integrity"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable server-side encryption for S3 bucket"
  type        = bool
  default     = true
}

variable "discovery_agent_config" {
  description = "Configuration settings for discovery agents"
  type = object({
    collect_processes          = bool
    collect_network_connections = bool
    collect_performance_data   = bool
    collection_interval_hours  = number
  })
  default = {
    collect_processes          = true
    collect_network_connections = true
    collect_performance_data   = true
    collection_interval_hours  = 1
  }
  
  validation {
    condition = var.discovery_agent_config.collection_interval_hours >= 1 && var.discovery_agent_config.collection_interval_hours <= 24
    error_message = "Collection interval must be between 1 and 24 hours."
  }
}

variable "export_schedule" {
  description = "Schedule for automated data exports (cron format)"
  type        = string
  default     = "0 2 * * SUN"  # Weekly on Sunday at 2 AM
  
  validation {
    condition = can(regex("^[0-9\\*\\-\\,\\/\\s]+$", var.export_schedule))
    error_message = "Export schedule must be a valid cron expression."
  }
}

variable "migration_waves" {
  description = "Configuration for migration wave planning"
  type = list(object({
    wave_number           = number
    name                  = string
    description           = string
    target_migration_date = string
    priority              = string
  }))
  default = [
    {
      wave_number           = 1
      name                  = "Pilot Wave - Low Risk Applications"
      description           = "Standalone applications with minimal dependencies"
      target_migration_date = "2024-Q2"
      priority              = "high"
    },
    {
      wave_number           = 2
      name                  = "Business Applications Wave"
      description           = "Core business applications with managed dependencies"
      target_migration_date = "2024-Q3"
      priority              = "medium"
    },
    {
      wave_number           = 3
      name                  = "Legacy Systems Wave"
      description           = "Complex legacy systems requiring refactoring"
      target_migration_date = "2024-Q4"
      priority              = "low"
    }
  ]
}

variable "notification_email" {
  description = "Email address for migration assessment notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring for discovery service"
  type        = bool
  default     = true
}

variable "enable_eventbridge_automation" {
  description = "Enable EventBridge rules for automated discovery workflows"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "EnterpriseDiscovery"
    Owner       = "MigrationTeam"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access S3 bucket (leave empty for no restrictions)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges : can(cidrhost(ip, 0))
    ])
    error_message = "All IP ranges must be valid CIDR blocks."
  }
}

variable "vmware_vcenter_config" {
  description = "Configuration for VMware vCenter integration (optional)"
  type = object({
    hostname    = string
    username    = string
    enable_ssl  = bool
    port        = number
  })
  default = {
    hostname    = ""
    username    = ""
    enable_ssl  = true
    port        = 443
  }
}