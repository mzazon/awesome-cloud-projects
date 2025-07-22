# Variables for AWS Database Migration Service Infrastructure
# This file defines all configurable parameters for the DMS migration solution

# General Configuration
variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the migration project"
  type        = string
  default     = "database-migration"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "migration"
}

# Network Configuration
variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "VPC CIDR block must be a valid IPv4 CIDR."
  }
}

variable "subnet_1_cidr" {
  description = "CIDR block for the first subnet"
  type        = string
  default     = "10.0.1.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_1_cidr, 0))
    error_message = "Subnet 1 CIDR block must be a valid IPv4 CIDR."
  }
}

variable "subnet_2_cidr" {
  description = "CIDR block for the second subnet"
  type        = string
  default     = "10.0.2.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_2_cidr, 0))
    error_message = "Subnet 2 CIDR block must be a valid IPv4 CIDR."
  }
}

# DMS Configuration
variable "dms_replication_instance_class" {
  description = "Instance class for DMS replication instance"
  type        = string
  default     = "dms.t3.medium"
  validation {
    condition     = contains(["dms.t3.micro", "dms.t3.small", "dms.t3.medium", "dms.t3.large", "dms.c5.large", "dms.c5.xlarge", "dms.c5.2xlarge", "dms.c5.4xlarge"], var.dms_replication_instance_class)
    error_message = "DMS replication instance class must be a valid DMS instance type."
  }
}

variable "dms_allocated_storage" {
  description = "Allocated storage for DMS replication instance (GB)"
  type        = number
  default     = 100
  validation {
    condition     = var.dms_allocated_storage >= 20 && var.dms_allocated_storage <= 6144
    error_message = "DMS allocated storage must be between 20 and 6144 GB."
  }
}

variable "dms_engine_version" {
  description = "DMS engine version"
  type        = string
  default     = "3.5.2"
}

variable "dms_publicly_accessible" {
  description = "Whether the DMS replication instance is publicly accessible"
  type        = bool
  default     = true
}

variable "dms_multi_az" {
  description = "Whether to enable Multi-AZ deployment for DMS replication instance"
  type        = bool
  default     = false
}

# RDS Configuration
variable "rds_instance_class" {
  description = "Instance class for RDS target database"
  type        = string
  default     = "db.t3.medium"
  validation {
    condition     = contains(["db.t3.micro", "db.t3.small", "db.t3.medium", "db.t3.large", "db.t3.xlarge", "db.t3.2xlarge", "db.r5.large", "db.r5.xlarge"], var.rds_instance_class)
    error_message = "RDS instance class must be a valid RDS instance type."
  }
}

variable "rds_engine" {
  description = "Database engine for RDS target database"
  type        = string
  default     = "postgres"
  validation {
    condition     = contains(["postgres", "mysql", "mariadb"], var.rds_engine)
    error_message = "RDS engine must be postgres, mysql, or mariadb."
  }
}

variable "rds_engine_version" {
  description = "Database engine version for RDS target database"
  type        = string
  default     = "14.9"
}

variable "rds_allocated_storage" {
  description = "Allocated storage for RDS target database (GB)"
  type        = number
  default     = 100
  validation {
    condition     = var.rds_allocated_storage >= 20 && var.rds_allocated_storage <= 65536
    error_message = "RDS allocated storage must be between 20 and 65536 GB."
  }
}

variable "rds_backup_retention_period" {
  description = "Number of days to retain RDS backups"
  type        = number
  default     = 7
  validation {
    condition     = var.rds_backup_retention_period >= 0 && var.rds_backup_retention_period <= 35
    error_message = "RDS backup retention period must be between 0 and 35 days."
  }
}

variable "rds_publicly_accessible" {
  description = "Whether the RDS target database is publicly accessible"
  type        = bool
  default     = true
}

variable "rds_username" {
  description = "Master username for RDS target database"
  type        = string
  default     = "dbadmin"
  validation {
    condition     = length(var.rds_username) >= 1 && length(var.rds_username) <= 63
    error_message = "RDS username must be between 1 and 63 characters."
  }
}

variable "rds_password" {
  description = "Master password for RDS target database (leave empty to auto-generate)"
  type        = string
  default     = ""
  sensitive   = true
}

# Source Database Configuration
variable "source_db_engine" {
  description = "Source database engine"
  type        = string
  default     = "oracle"
  validation {
    condition     = contains(["oracle", "sqlserver", "mysql", "postgres", "mariadb", "aurora", "aurora-postgresql"], var.source_db_engine)
    error_message = "Source database engine must be a valid DMS-supported engine."
  }
}

variable "source_db_host" {
  description = "Source database hostname or IP address"
  type        = string
  default     = "your-source-database-host"
}

variable "source_db_port" {
  description = "Source database port"
  type        = number
  default     = 1521
  validation {
    condition     = var.source_db_port >= 1 && var.source_db_port <= 65535
    error_message = "Source database port must be between 1 and 65535."
  }
}

variable "source_db_name" {
  description = "Source database name"
  type        = string
  default     = "your-source-database"
}

variable "source_db_username" {
  description = "Source database username"
  type        = string
  default     = "your-source-username"
}

variable "source_db_password" {
  description = "Source database password"
  type        = string
  default     = "your-source-password"
  sensitive   = true
}

# Migration Configuration
variable "migration_type" {
  description = "Type of migration task"
  type        = string
  default     = "full-load-and-cdc"
  validation {
    condition     = contains(["full-load", "cdc", "full-load-and-cdc"], var.migration_type)
    error_message = "Migration type must be full-load, cdc, or full-load-and-cdc."
  }
}

variable "table_mappings" {
  description = "Table mappings configuration for DMS task"
  type        = string
  default     = ""
}

variable "task_settings" {
  description = "Task settings configuration for DMS task"
  type        = string
  default     = ""
}

# Monitoring Configuration
variable "enable_cloudwatch_logs" {
  description = "Whether to enable CloudWatch logs for DMS"
  type        = bool
  default     = true
}

variable "cloudwatch_log_group" {
  description = "CloudWatch log group name for DMS logs"
  type        = string
  default     = "/aws/dms/tasks"
}

variable "enable_enhanced_monitoring" {
  description = "Whether to enable enhanced monitoring for DMS"
  type        = bool
  default     = true
}

variable "create_dashboard" {
  description = "Whether to create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

# Security Configuration
variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the databases"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_deletion_protection" {
  description = "Whether to enable deletion protection for RDS"
  type        = bool
  default     = false
}

# Common Tags
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Migration"
    Project     = "DatabaseMigration"
    Owner       = "DataTeam"
    ManagedBy   = "Terraform"
  }
}