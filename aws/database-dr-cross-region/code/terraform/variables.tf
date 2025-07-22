# Variable definitions for Database Disaster Recovery with Read Replicas

# Region Configuration
variable "primary_region" {
  description = "AWS region for the primary database instance"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.primary_region))
    error_message = "Primary region must be a valid AWS region name."
  }
}

variable "dr_region" {
  description = "AWS region for the disaster recovery read replica"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.dr_region))
    error_message = "DR region must be a valid AWS region name."
  }
}

# Environment Configuration
variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
  default     = "production"
  
  validation {
    condition = contains(["production", "staging", "development", "test"], var.environment)
    error_message = "Environment must be one of: production, staging, development, test."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "dr-database"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# Database Configuration
variable "db_instance_class" {
  description = "RDS instance class for both primary and replica databases"
  type        = string
  default     = "db.t3.micro"
  
  validation {
    condition = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.db_instance_class))
    error_message = "Database instance class must be a valid RDS instance type."
  }
}

variable "db_engine" {
  description = "Database engine type"
  type        = string
  default     = "mysql"
  
  validation {
    condition = contains(["mysql", "postgres", "mariadb"], var.db_engine)
    error_message = "Database engine must be one of: mysql, postgres, mariadb."
  }
}

variable "db_engine_version" {
  description = "Database engine version"
  type        = string
  default     = "8.0"
}

variable "allocated_storage" {
  description = "Allocated storage size in GB for the primary database"
  type        = number
  default     = 20
  
  validation {
    condition = var.allocated_storage >= 20 && var.allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
  
  validation {
    condition = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "storage_encrypted" {
  description = "Enable storage encryption for RDS instances"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection for the primary database"
  type        = bool
  default     = true
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights for RDS instances"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0, 1, 5, 10, 15, 30, 60)"
  type        = number
  default     = 60
  
  validation {
    condition = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, 60 seconds."
  }
}

# Database Credentials
variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "admin"
  sensitive   = true
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_username))
    error_message = "Database username must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "manage_master_user_password" {
  description = "Set to true to allow RDS to manage the master user password in Secrets Manager"
  type        = bool
  default     = true
}

# Network Configuration
variable "vpc_id_primary" {
  description = "VPC ID in the primary region (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "vpc_id_dr" {
  description = "VPC ID in the DR region (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids_primary" {
  description = "List of subnet IDs in the primary region for the DB subnet group"
  type        = list(string)
  default     = []
}

variable "subnet_ids_dr" {
  description = "List of subnet IDs in the DR region for the DB subnet group"
  type        = list(string)
  default     = []
}

variable "publicly_accessible" {
  description = "Make the RDS instances publicly accessible"
  type        = bool
  default     = false
}

# Monitoring and Alerting Configuration
variable "notification_email" {
  description = "Email address for SNS notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "cpu_threshold" {
  description = "CPU utilization threshold for CloudWatch alarms (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition = var.cpu_threshold >= 1 && var.cpu_threshold <= 100
    error_message = "CPU threshold must be between 1 and 100 percent."
  }
}

variable "replica_lag_threshold" {
  description = "Replica lag threshold in seconds for CloudWatch alarms"
  type        = number
  default     = 300
  
  validation {
    condition = var.replica_lag_threshold >= 60 && var.replica_lag_threshold <= 3600
    error_message = "Replica lag threshold must be between 60 and 3600 seconds."
  }
}

variable "connection_failure_threshold" {
  description = "Database connection failure threshold for CloudWatch alarms"
  type        = number
  default     = 0
}

# Route 53 Configuration
variable "create_health_checks" {
  description = "Create Route 53 health checks for database monitoring"
  type        = bool
  default     = true
}

variable "health_check_failure_threshold" {
  description = "Number of consecutive health check failures before alarm"
  type        = number
  default     = 3
  
  validation {
    condition = var.health_check_failure_threshold >= 1 && var.health_check_failure_threshold <= 10
    error_message = "Health check failure threshold must be between 1 and 10."
  }
}

# Lambda Configuration
variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "enable_lambda_insights" {
  description = "Enable Lambda Insights for enhanced monitoring"
  type        = bool
  default     = true
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name for the S3 bucket storing DR configuration (leave empty for auto-generated name)"
  type        = string
  default     = ""
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 configuration bucket"
  type        = bool
  default     = true
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Advanced Configuration
variable "auto_minor_version_upgrade" {
  description = "Enable auto minor version upgrade for RDS instances"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs_exports" {
  description = "List of log types to export to CloudWatch Logs"
  type        = list(string)
  default     = ["error", "general", "slow-query"]
}

variable "parameter_group_family" {
  description = "Database parameter group family"
  type        = string
  default     = "mysql8.0"
}

variable "create_custom_parameter_group" {
  description = "Create a custom parameter group optimized for replication"
  type        = bool
  default     = true
}

# EventBridge Configuration
variable "enable_eventbridge_rules" {
  description = "Enable EventBridge rules for RDS event automation"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_iam_database_authentication" {
  description = "Enable IAM database authentication"
  type        = bool
  default     = false
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (leave empty to use default AWS managed key)"
  type        = string
  default     = ""
}

# Skip final snapshot (use carefully in production)
variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting the database (NOT recommended for production)"
  type        = bool
  default     = false
}