# Input Variables for PostgreSQL High Availability Cluster
# These variables allow customization of the infrastructure deployment

# General Configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "postgresql-ha"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# Region Configuration
variable "aws_region" {
  description = "Primary AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "Disaster recovery AWS region"
  type        = string
  default     = "us-west-2"
}

# Networking Configuration
variable "vpc_id" {
  description = "ID of the VPC where resources will be created. If not provided, default VPC will be used"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for database subnet group. If not provided, default VPC subnets will be used"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the database"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

# Database Configuration
variable "db_name" {
  description = "Name of the initial database"
  type        = string
  default     = "productiondb"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "master_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "dbadmin"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.master_username))
    error_message = "Master username must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "master_password" {
  description = "Master password for the RDS instance"
  type        = string
  sensitive   = true
  default     = null
  
  validation {
    condition     = var.master_password == null || length(var.master_password) >= 8
    error_message = "Master password must be at least 8 characters long."
  }
}

variable "db_instance_class" {
  description = "The RDS instance class"
  type        = string
  default     = "db.r6g.large"
  
  validation {
    condition = contains([
      "db.r6g.large", "db.r6g.xlarge", "db.r6g.2xlarge", "db.r6g.4xlarge",
      "db.r5.large", "db.r5.xlarge", "db.r5.2xlarge", "db.r5.4xlarge",
      "db.t3.medium", "db.t3.large", "db.t3.xlarge", "db.t3.2xlarge"
    ], var.db_instance_class)
    error_message = "DB instance class must be a valid RDS instance type."
  }
}

variable "allocated_storage" {
  description = "The allocated storage in gibibytes"
  type        = number
  default     = 200
  
  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GiB."
  }
}

variable "max_allocated_storage" {
  description = "Maximum storage for autoscaling (0 = disabled)"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.max_allocated_storage == 0 || var.max_allocated_storage >= var.allocated_storage
    error_message = "Max allocated storage must be 0 (disabled) or greater than allocated storage."
  }
}

variable "storage_type" {
  description = "Storage type for the RDS instance"
  type        = string
  default     = "gp3"
  
  validation {
    condition     = contains(["gp3", "gp2", "io1", "io2"], var.storage_type)
    error_message = "Storage type must be one of: gp3, gp2, io1, io2."
  }
}

variable "iops" {
  description = "The amount of provisioned IOPS (only for io1/io2 storage types)"
  type        = number
  default     = null
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "parameter_group_family" {
  description = "DB parameter group family"
  type        = string
  default     = "postgres15"
}

# High Availability Configuration
variable "multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 35
  
  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

# Read Replica Configuration
variable "create_read_replica" {
  description = "Create read replica in the same region"
  type        = bool
  default     = true
}

variable "read_replica_instance_class" {
  description = "Instance class for read replica"
  type        = string
  default     = "db.r6g.large"
}

variable "create_cross_region_replica" {
  description = "Create cross-region read replica for disaster recovery"
  type        = bool
  default     = true
}

# RDS Proxy Configuration
variable "create_rds_proxy" {
  description = "Create RDS Proxy for connection pooling"
  type        = bool
  default     = true
}

variable "proxy_idle_client_timeout" {
  description = "Idle client timeout for RDS Proxy (seconds)"
  type        = number
  default     = 1800
  
  validation {
    condition     = var.proxy_idle_client_timeout >= 1 && var.proxy_idle_client_timeout <= 28800
    error_message = "Proxy idle client timeout must be between 1 and 28800 seconds."
  }
}

variable "proxy_max_connections_percent" {
  description = "Maximum connections percent for RDS Proxy"
  type        = number
  default     = 100
  
  validation {
    condition     = var.proxy_max_connections_percent >= 1 && var.proxy_max_connections_percent <= 100
    error_message = "Proxy max connections percent must be between 1 and 100."
  }
}

# Monitoring Configuration
variable "enable_performance_insights" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([7, 31, 93, 186, 372, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention period must be one of: 7, 31, 93, 186, 372, 731 days."
  }
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, 60 seconds."
  }
}

variable "enabled_cloudwatch_logs_exports" {
  description = "List of log types to export to CloudWatch"
  type        = list(string)
  default     = ["postgresql"]
}

# Alerting Configuration
variable "notification_email" {
  description = "Email address for database alerts"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "cpu_threshold" {
  description = "CPU utilization threshold for alerts"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cpu_threshold >= 1 && var.cpu_threshold <= 100
    error_message = "CPU threshold must be between 1 and 100."
  }
}

variable "connection_threshold" {
  description = "Database connection count threshold for alerts"
  type        = number
  default     = 150
  
  validation {
    condition     = var.connection_threshold >= 1
    error_message = "Connection threshold must be greater than 0."
  }
}

variable "replica_lag_threshold" {
  description = "Read replica lag threshold in seconds for alerts"
  type        = number
  default     = 30
  
  validation {
    condition     = var.replica_lag_threshold >= 1
    error_message = "Replica lag threshold must be greater than 0."
  }
}

# Security Configuration
variable "storage_encrypted" {
  description = "Enable storage encryption"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS Key ID for encryption (if not provided, default key will be used)"
  type        = string
  default     = ""
}

variable "copy_tags_to_snapshot" {
  description = "Copy tags to snapshots"
  type        = bool
  default     = true
}

# Additional Configuration
variable "auto_minor_version_upgrade" {
  description = "Enable automatic minor version upgrades"
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply modifications immediately"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting DB instance"
  type        = bool
  default     = false
}

# Custom Parameter Group Parameters
variable "custom_db_parameters" {
  description = "Custom database parameters for parameter group"
  type = map(object({
    value        = string
    apply_method = string
  }))
  default = {
    log_statement = {
      value        = "all"
      apply_method = "pending-reboot"
    }
    log_min_duration_statement = {
      value        = "1000"
      apply_method = "pending-reboot"
    }
    shared_preload_libraries = {
      value        = "pg_stat_statements"
      apply_method = "pending-reboot"
    }
    track_activity_query_size = {
      value        = "2048"
      apply_method = "pending-reboot"
    }
    max_connections = {
      value        = "200"
      apply_method = "pending-reboot"
    }
  }
}