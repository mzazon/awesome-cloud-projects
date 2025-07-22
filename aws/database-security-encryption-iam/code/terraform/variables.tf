# ==============================================================================
# VARIABLES
# ==============================================================================

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1' or similar."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "secure-database"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Database Configuration
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r5.large"
  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z]+$", var.db_instance_class))
    error_message = "DB instance class must be in the format 'db.r5.large' or similar."
  }
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.7"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.db_engine_version))
    error_message = "DB engine version must be in the format 'X.Y'."
  }
}

variable "db_allocated_storage" {
  description = "Amount of storage (in GB) to allocate for the RDS instance"
  type        = number
  default     = 100
  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "db_storage_type" {
  description = "Storage type for the RDS instance"
  type        = string
  default     = "gp3"
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.db_storage_type)
    error_message = "Storage type must be gp2, gp3, io1, or io2."
  }
}

variable "db_backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
  validation {
    condition     = var.db_backup_retention_period >= 0 && var.db_backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

variable "db_backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "03:00-04:00"
  validation {
    condition     = can(regex("^[0-9]{2}:[0-9]{2}-[0-9]{2}:[0-9]{2}$", var.db_backup_window))
    error_message = "Backup window must be in the format 'HH:MM-HH:MM'."
  }
}

variable "db_maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
  validation {
    condition     = can(regex("^[a-z]{3}:[0-9]{2}:[0-9]{2}-[a-z]{3}:[0-9]{2}:[0-9]{2}$", var.db_maintenance_window))
    error_message = "Maintenance window must be in the format 'ddd:HH:MM-ddd:HH:MM'."
  }
}

variable "db_username" {
  description = "Database username for IAM authentication"
  type        = string
  default     = "app_user"
  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.db_username))
    error_message = "Database username must start with a letter or underscore and contain only letters, numbers, and underscores."
  }
}

variable "db_admin_username" {
  description = "Database admin username"
  type        = string
  default     = "dbadmin"
  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.db_admin_username))
    error_message = "Database admin username must start with a letter or underscore and contain only letters, numbers, and underscores."
  }
}

variable "db_name" {
  description = "Name of the application database"
  type        = string
  default     = "secure_app_db"
  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.db_name))
    error_message = "Database name must start with a letter or underscore and contain only letters, numbers, and underscores."
  }
}

# Performance Insights Configuration
variable "performance_insights_retention_period" {
  description = "Amount of time in days to retain Performance Insights data"
  type        = number
  default     = 7
  validation {
    condition     = contains([7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention period must be 7 days or a valid longer period."
  }
}

variable "enhanced_monitoring_interval" {
  description = "Interval for enhanced monitoring (in seconds)"
  type        = number
  default     = 60
  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.enhanced_monitoring_interval)
    error_message = "Enhanced monitoring interval must be 0, 1, 5, 10, 15, 30, or 60 seconds."
  }
}

# RDS Proxy Configuration
variable "proxy_idle_client_timeout" {
  description = "Number of seconds that a connection to the proxy can be idle before the proxy disconnects it"
  type        = number
  default     = 1800
  validation {
    condition     = var.proxy_idle_client_timeout >= 1 && var.proxy_idle_client_timeout <= 28800
    error_message = "Proxy idle client timeout must be between 1 and 28800 seconds."
  }
}

variable "proxy_max_connections_percent" {
  description = "Maximum size of the connection pool for each target in a target group"
  type        = number
  default     = 100
  validation {
    condition     = var.proxy_max_connections_percent >= 1 && var.proxy_max_connections_percent <= 100
    error_message = "Proxy max connections percent must be between 1 and 100."
  }
}

variable "proxy_max_idle_connections_percent" {
  description = "Controls how many connections in the connection pool remain idle"
  type        = number
  default     = 50
  validation {
    condition     = var.proxy_max_idle_connections_percent >= 0 && var.proxy_max_idle_connections_percent <= 100
    error_message = "Proxy max idle connections percent must be between 0 and 100."
  }
}

# Network Configuration
variable "vpc_id" {
  description = "VPC ID where resources will be created (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for the DB subnet group (leave empty to use default subnets)"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks that can access the database"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  validation {
    condition     = length(var.allowed_cidr_blocks) > 0
    error_message = "At least one CIDR block must be specified."
  }
}

# CloudWatch Configuration
variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid value."
  }
}

variable "cpu_utilization_threshold" {
  description = "CPU utilization threshold for CloudWatch alarms"
  type        = number
  default     = 80
  validation {
    condition     = var.cpu_utilization_threshold >= 0 && var.cpu_utilization_threshold <= 100
    error_message = "CPU utilization threshold must be between 0 and 100."
  }
}

variable "database_connections_threshold" {
  description = "Database connections threshold for CloudWatch alarms"
  type        = number
  default     = 50
  validation {
    condition     = var.database_connections_threshold >= 0
    error_message = "Database connections threshold must be a positive number."
  }
}

# Security Configuration
variable "deletion_protection" {
  description = "Enable deletion protection for the RDS instance"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "Number of days to wait before deleting the KMS key"
  type        = number
  default     = 7
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "enable_debug_logging" {
  description = "Enable debug logging for RDS Proxy"
  type        = bool
  default     = false
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}