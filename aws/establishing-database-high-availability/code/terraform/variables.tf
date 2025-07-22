# variables.tf - Input variables for Multi-AZ Database Deployment

variable "aws_region" {
  description = "AWS region for deploying the Multi-AZ database cluster"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
  default     = "multiaz-db"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

variable "db_engine" {
  description = "Database engine for the RDS cluster (aurora-postgresql or aurora-mysql)"
  type        = string
  default     = "aurora-postgresql"
  
  validation {
    condition     = contains(["aurora-postgresql", "aurora-mysql"], var.db_engine)
    error_message = "Database engine must be either aurora-postgresql or aurora-mysql."
  }
}

variable "db_engine_version" {
  description = "Database engine version"
  type        = string
  default     = "15.4"
}

variable "db_instance_class" {
  description = "Database instance class for cluster instances"
  type        = string
  default     = "db.r6g.large"
  
  validation {
    condition = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.db_instance_class))
    error_message = "Database instance class must be a valid RDS instance type."
  }
}

variable "db_name" {
  description = "Name of the database to create"
  type        = string
  default     = "appdb"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "db_master_username" {
  description = "Master username for the database"
  type        = string
  default     = "dbadmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_master_username))
    error_message = "Master username must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 14
  
  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "preferred_backup_window" {
  description = "Preferred backup window in UTC format"
  type        = string
  default     = "03:00-04:00"
  
  validation {
    condition = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]-([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.preferred_backup_window))
    error_message = "Backup window must be in format HH:MM-HH:MM."
  }
}

variable "preferred_maintenance_window" {
  description = "Preferred maintenance window in UTC format"
  type        = string
  default     = "sun:04:00-sun:05:00"
  
  validation {
    condition = can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.preferred_maintenance_window))
    error_message = "Maintenance window must be in format day:HH:MM-day:HH:MM."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for the database cluster"
  type        = bool
  default     = true
}

variable "enable_storage_encryption" {
  description = "Enable storage encryption for the database cluster"
  type        = bool
  default     = true
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights for database instances"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Amount of time to retain performance insights data in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention period must be 7 days or a multiple of 31 days up to 731 days."
  }
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "cloudwatch_log_exports" {
  description = "List of log types to export to CloudWatch"
  type        = list(string)
  default     = ["postgresql"]
  
  validation {
    condition = alltrue([
      for log_type in var.cloudwatch_log_exports : 
      contains(["postgresql", "upgrade", "mysql", "error", "general", "slowquery"], log_type)
    ])
    error_message = "Log exports must be valid log types for the chosen engine."
  }
}

variable "cpu_utilization_alarm_threshold" {
  description = "CPU utilization threshold for CloudWatch alarms (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cpu_utilization_alarm_threshold >= 1 && var.cpu_utilization_alarm_threshold <= 100
    error_message = "CPU utilization threshold must be between 1 and 100."
  }
}

variable "database_connections_alarm_threshold" {
  description = "Database connections threshold for CloudWatch alarms"
  type        = number
  default     = 80
  
  validation {
    condition     = var.database_connections_alarm_threshold >= 1
    error_message = "Database connections threshold must be a positive number."
  }
}

variable "create_sns_topic" {
  description = "Whether to create an SNS topic for database alerts"
  type        = bool
  default     = true
}

variable "sns_endpoint" {
  description = "Email address to receive database alerts"
  type        = string
  default     = ""
  
  validation {
    condition = var.sns_endpoint == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sns_endpoint))
    error_message = "SNS endpoint must be a valid email address or empty string."
  }
}

variable "availability_zones" {
  description = "List of availability zones for the database cluster"
  type        = list(string)
  default     = []
}

variable "create_test_resources" {
  description = "Whether to create test database tables and sample data"
  type        = bool
  default     = false
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "multi-az-database"
    Environment = "dev"
    ManagedBy   = "terraform"
    Purpose     = "high-availability-database"
  }
}