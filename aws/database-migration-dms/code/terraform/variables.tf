# General Configuration
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
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

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "dms-migration"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# VPC Configuration
variable "vpc_id" {
  description = "VPC ID where DMS resources will be deployed. If not provided, uses default VPC"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for DMS subnet group. If not provided, uses default VPC subnets"
  type        = list(string)
  default     = []
}

# DMS Replication Instance Configuration
variable "replication_instance_class" {
  description = "DMS replication instance class"
  type        = string
  default     = "dms.t3.medium"

  validation {
    condition = can(regex("^dms\\.(t3|t2|c5|c4|r5|r4)\\.(micro|small|medium|large|xlarge|2xlarge|4xlarge|8xlarge|12xlarge|16xlarge|24xlarge)$", var.replication_instance_class))
    error_message = "Replication instance class must be a valid DMS instance type."
  }
}

variable "allocated_storage" {
  description = "Storage allocated for DMS replication instance (GB)"
  type        = number
  default     = 100

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 6144
    error_message = "Allocated storage must be between 20 and 6144 GB."
  }
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment for replication instance"
  type        = bool
  default     = true
}

variable "publicly_accessible" {
  description = "Make replication instance publicly accessible"
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Enable automatic minor version upgrades"
  type        = bool
  default     = true
}

# Source Database Configuration
variable "source_engine" {
  description = "Source database engine"
  type        = string
  default     = "mysql"

  validation {
    condition = contains([
      "mysql", "postgres", "oracle", "sqlserver", "aurora", "aurora-postgresql", 
      "mariadb", "mongodb", "db2", "sybase", "redshift", "s3"
    ], var.source_engine)
    error_message = "Source engine must be a supported DMS engine."
  }
}

variable "source_server_name" {
  description = "Source database server hostname or IP address"
  type        = string
}

variable "source_port" {
  description = "Source database port"
  type        = number
  default     = 3306

  validation {
    condition     = var.source_port > 0 && var.source_port <= 65535
    error_message = "Port must be between 1 and 65535."
  }
}

variable "source_database_name" {
  description = "Source database name"
  type        = string
}

variable "source_username" {
  description = "Source database username"
  type        = string
}

variable "source_password" {
  description = "Source database password"
  type        = string
  sensitive   = true
}

variable "source_ssl_mode" {
  description = "SSL mode for source database connection"
  type        = string
  default     = "require"

  validation {
    condition     = contains(["none", "require", "verify-ca", "verify-full"], var.source_ssl_mode)
    error_message = "SSL mode must be one of: none, require, verify-ca, verify-full."
  }
}

# Target Database Configuration
variable "target_engine" {
  description = "Target database engine"
  type        = string
  default     = "mysql"

  validation {
    condition = contains([
      "mysql", "postgres", "oracle", "sqlserver", "aurora", "aurora-postgresql", 
      "mariadb", "redshift", "dynamodb", "kinesis", "kafka", "elasticsearch", "s3"
    ], var.target_engine)
    error_message = "Target engine must be a supported DMS engine."
  }
}

variable "target_server_name" {
  description = "Target database server hostname (e.g., RDS endpoint)"
  type        = string
}

variable "target_port" {
  description = "Target database port"
  type        = number
  default     = 3306

  validation {
    condition     = var.target_port > 0 && var.target_port <= 65535
    error_message = "Port must be between 1 and 65535."
  }
}

variable "target_database_name" {
  description = "Target database name"
  type        = string
}

variable "target_username" {
  description = "Target database username"
  type        = string
}

variable "target_password" {
  description = "Target database password"
  type        = string
  sensitive   = true
}

variable "target_ssl_mode" {
  description = "SSL mode for target database connection"
  type        = string
  default     = "require"

  validation {
    condition     = contains(["none", "require", "verify-ca", "verify-full"], var.target_ssl_mode)
    error_message = "SSL mode must be one of: none, require, verify-ca, verify-full."
  }
}

# Migration Task Configuration
variable "migration_type" {
  description = "Migration type (full-load, cdc, full-load-and-cdc)"
  type        = string
  default     = "full-load-and-cdc"

  validation {
    condition     = contains(["full-load", "cdc", "full-load-and-cdc"], var.migration_type)
    error_message = "Migration type must be one of: full-load, cdc, full-load-and-cdc."
  }
}

variable "target_table_prep_mode" {
  description = "Target table preparation mode"
  type        = string
  default     = "DROP_AND_CREATE"

  validation {
    condition     = contains(["NOTHING", "DROP_AND_CREATE", "TRUNCATE_BEFORE_LOAD"], var.target_table_prep_mode)
    error_message = "Target table prep mode must be one of: NOTHING, DROP_AND_CREATE, TRUNCATE_BEFORE_LOAD."
  }
}

variable "enable_data_validation" {
  description = "Enable data validation for migration task"
  type        = bool
  default     = true
}

variable "start_replication_task" {
  description = "Automatically start replication task after creation"
  type        = bool
  default     = false
}

# Monitoring Configuration
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for DMS tasks"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

variable "notification_email" {
  description = "Email address for DMS notifications (optional)"
  type        = string
  default     = ""

  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Table Mapping Configuration
variable "schema_name_pattern" {
  description = "Schema name pattern for table mappings (% for all schemas)"
  type        = string
  default     = "%"
}

variable "table_name_pattern" {
  description = "Table name pattern for table mappings (% for all tables)"
  type        = string
  default     = "%"
}

variable "add_table_prefix" {
  description = "Prefix to add to migrated table names (empty for no prefix)"
  type        = string
  default     = ""
}

# Security Configuration
variable "enable_kms_encryption" {
  description = "Enable KMS encryption for DMS resources"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (uses default if not specified)"
  type        = string
  default     = ""
}

# Performance and Tuning
variable "max_full_load_sub_tasks" {
  description = "Maximum number of full load sub-tasks"
  type        = number
  default     = 8

  validation {
    condition     = var.max_full_load_sub_tasks >= 1 && var.max_full_load_sub_tasks <= 49
    error_message = "Max full load sub-tasks must be between 1 and 49."
  }
}

variable "parallel_load_threads" {
  description = "Number of parallel load threads"
  type        = number
  default     = 0

  validation {
    condition     = var.parallel_load_threads >= 0 && var.parallel_load_threads <= 32
    error_message = "Parallel load threads must be between 0 and 32."
  }
}

variable "batch_apply_enabled" {
  description = "Enable batch apply for improved performance"
  type        = bool
  default     = false
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}