# Region Configuration
variable "primary_region" {
  description = "Primary AWS region where the main RDS database is located"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.primary_region))
    error_message = "Primary region must be a valid AWS region name."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for disaster recovery read replica"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.secondary_region))
    error_message = "Secondary region must be a valid AWS region name."
  }
}

# Database Configuration
variable "source_db_identifier" {
  description = "Identifier of the existing source RDS database instance"
  type        = string
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.source_db_identifier))
    error_message = "Source DB identifier must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "replica_instance_class" {
  description = "Instance class for the read replica (if different from source)"
  type        = string
  default     = null
}

variable "replica_multi_az" {
  description = "Whether to enable Multi-AZ for the read replica"
  type        = bool
  default     = true
}

variable "replica_storage_encrypted" {
  description = "Whether to encrypt the read replica storage"
  type        = bool
  default     = true
}

# Environment and Naming
variable "environment" {
  description = "Environment name (e.g., prod, staging, dev)"
  type        = string
  default     = "prod"
  
  validation {
    condition = contains(["prod", "staging", "dev", "test"], var.environment)
    error_message = "Environment must be one of: prod, staging, dev, test."
  }
}

variable "resource_name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "rds-dr"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.resource_name_prefix))
    error_message = "Resource name prefix must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

# Monitoring Configuration
variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold for CloudWatch alarms (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition = var.cpu_alarm_threshold >= 50 && var.cpu_alarm_threshold <= 100
    error_message = "CPU alarm threshold must be between 50 and 100."
  }
}

variable "replica_lag_threshold" {
  description = "Replica lag threshold for CloudWatch alarms (seconds)"
  type        = number
  default     = 300
  
  validation {
    condition = var.replica_lag_threshold >= 60 && var.replica_lag_threshold <= 3600
    error_message = "Replica lag threshold must be between 60 and 3600 seconds."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2
  
  validation {
    condition = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 5
    error_message = "Alarm evaluation periods must be between 1 and 5."
  }
}

# Notification Configuration
variable "notification_email" {
  description = "Email address for disaster recovery notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_email_notifications" {
  description = "Whether to enable email notifications for SNS topics"
  type        = bool
  default     = true
}

# Lambda Configuration
variable "lambda_timeout" {
  description = "Timeout for Lambda function (seconds)"
  type        = number
  default     = 300
  
  validation {
    condition = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function (MB)"
  type        = number
  default     = 256
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 3008
    error_message = "Lambda memory size must be between 128 and 3008 MB."
  }
}

# Dashboard Configuration
variable "create_dashboard" {
  description = "Whether to create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "dashboard_name" {
  description = "Name for the CloudWatch dashboard (auto-generated if not provided)"
  type        = string
  default     = ""
}

# Backup and Recovery Configuration
variable "backup_retention_period" {
  description = "Backup retention period for read replica (days)"
  type        = number
  default     = 7
  
  validation {
    condition = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "backup_window" {
  description = "Preferred backup window for read replica (UTC)"
  type        = string
  default     = "03:00-04:00"
  
  validation {
    condition = can(regex("^[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]$", var.backup_window))
    error_message = "Backup window must be in format HH:MM-HH:MM."
  }
}

variable "maintenance_window" {
  description = "Preferred maintenance window for read replica (UTC)"
  type        = string
  default     = "sun:04:00-sun:05:00"
  
  validation {
    condition = can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.maintenance_window))
    error_message = "Maintenance window must be in format ddd:HH:MM-ddd:HH:MM."
  }
}

# Security Configuration
variable "enable_deletion_protection" {
  description = "Whether to enable deletion protection for the read replica"
  type        = bool
  default     = true
}

variable "enable_performance_insights" {
  description = "Whether to enable Performance Insights for the read replica"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period (days)"
  type        = number
  default     = 7
  
  validation {
    condition = contains([7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention period must be a valid value (7, 31, or multiples of 31 up to 731)."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}