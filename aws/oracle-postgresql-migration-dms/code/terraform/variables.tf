# Variable definitions for Oracle to PostgreSQL database migration infrastructure

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "owner" {
  description = "Owner tag for resource management"
  type        = string
  default     = "database-team"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "oracle-to-postgresql"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# Aurora PostgreSQL Configuration
variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "aurora_instance_class" {
  description = "Instance class for Aurora PostgreSQL"
  type        = string
  default     = "db.r6g.large"
}

variable "aurora_master_username" {
  description = "Master username for Aurora PostgreSQL"
  type        = string
  default     = "dbadmin"
}

variable "aurora_master_password" {
  description = "Master password for Aurora PostgreSQL"
  type        = string
  sensitive   = true
  default     = "TempPassword123!"
  
  validation {
    condition     = length(var.aurora_master_password) >= 8
    error_message = "Password must be at least 8 characters long."
  }
}

variable "aurora_backup_retention_period" {
  description = "Backup retention period for Aurora"
  type        = number
  default     = 7
}

variable "aurora_preferred_backup_window" {
  description = "Preferred backup window for Aurora"
  type        = string
  default     = "03:00-04:00"
}

variable "aurora_preferred_maintenance_window" {
  description = "Preferred maintenance window for Aurora"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

# DMS Configuration
variable "dms_replication_instance_class" {
  description = "DMS replication instance class"
  type        = string
  default     = "dms.c5.large"
}

variable "dms_allocated_storage" {
  description = "Allocated storage for DMS replication instance"
  type        = number
  default     = 100
}

variable "dms_engine_version" {
  description = "DMS engine version"
  type        = string
  default     = "3.5.2"
}

variable "dms_multi_az" {
  description = "Enable Multi-AZ for DMS replication instance"
  type        = bool
  default     = true
}

variable "dms_publicly_accessible" {
  description = "Make DMS replication instance publicly accessible"
  type        = bool
  default     = false
}

# Oracle Source Database Configuration
variable "oracle_server_name" {
  description = "Oracle source database server name"
  type        = string
  default     = "your-oracle-server.example.com"
}

variable "oracle_port" {
  description = "Oracle database port"
  type        = number
  default     = 1521
}

variable "oracle_database_name" {
  description = "Oracle database name"
  type        = string
  default     = "ORCL"
}

variable "oracle_username" {
  description = "Oracle database username"
  type        = string
  default     = "oracle_user"
}

variable "oracle_password" {
  description = "Oracle database password"
  type        = string
  sensitive   = true
  default     = "oracle_password"
}

# DMS Task Configuration
variable "migration_type" {
  description = "DMS migration type"
  type        = string
  default     = "full-load-and-cdc"
  
  validation {
    condition = contains([
      "full-load", 
      "cdc", 
      "full-load-and-cdc"
    ], var.migration_type)
    error_message = "Migration type must be full-load, cdc, or full-load-and-cdc."
  }
}

variable "source_schema_name" {
  description = "Source Oracle schema name to migrate"
  type        = string
  default     = "HR"
}

variable "target_schema_name" {
  description = "Target PostgreSQL schema name"
  type        = string
  default     = "hr"
}

# Monitoring Configuration
variable "enable_performance_insights" {
  description = "Enable Performance Insights for Aurora"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period in days"
  type        = number
  default     = 7
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds"
  type        = number
  default     = 60
}

# CloudWatch Configuration
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "replication_lag_threshold" {
  description = "Replication lag threshold in seconds for CloudWatch alarm"
  type        = number
  default     = 300
}

variable "sns_notification_email" {
  description = "Email address for SNS notifications"
  type        = string
  default     = "admin@example.com"
}