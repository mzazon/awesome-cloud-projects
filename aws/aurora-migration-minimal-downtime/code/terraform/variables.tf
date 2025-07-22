# Variables for Aurora database migration infrastructure
# Customize these variables for your specific migration requirements

variable "aws_region" {
  description = "AWS region for deploying migration infrastructure"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region name."
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
  description = "Name of the migration project"
  type        = string
  default     = "aurora-migration"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  
  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnets are required for Aurora."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
  
  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least 2 public subnets are required for high availability."
  }
}

# Aurora Configuration
variable "aurora_engine" {
  description = "Aurora database engine"
  type        = string
  default     = "aurora-mysql"
  
  validation {
    condition     = contains(["aurora-mysql", "aurora-postgresql"], var.aurora_engine)
    error_message = "Aurora engine must be either aurora-mysql or aurora-postgresql."
  }
}

variable "aurora_engine_version" {
  description = "Aurora engine version"
  type        = string
  default     = "8.0.mysql_aurora.3.02.0"
}

variable "aurora_instance_class" {
  description = "Instance class for Aurora database instances"
  type        = string
  default     = "db.r6g.large"
  
  validation {
    condition     = can(regex("^db\\.", var.aurora_instance_class))
    error_message = "Aurora instance class must start with 'db.'."
  }
}

variable "aurora_master_username" {
  description = "Master username for Aurora cluster"
  type        = string
  default     = "admin"
  
  validation {
    condition     = length(var.aurora_master_username) >= 1 && length(var.aurora_master_username) <= 16
    error_message = "Master username must be between 1 and 16 characters."
  }
}

variable "aurora_database_name" {
  description = "Name of the initial database to create"
  type        = string
  default     = "migrationdb"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.aurora_database_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "aurora_backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.aurora_backup_retention_period >= 1 && var.aurora_backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "aurora_backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "03:00-04:00"
  
  validation {
    condition     = can(regex("^[0-9]{2}:[0-9]{2}-[0-9]{2}:[0-9]{2}$", var.aurora_backup_window))
    error_message = "Backup window must be in format HH:MM-HH:MM."
  }
}

variable "aurora_maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
  
  validation {
    condition     = can(regex("^[a-z]{3}:[0-9]{2}:[0-9]{2}-[a-z]{3}:[0-9]{2}:[0-9]{2}$", var.aurora_maintenance_window))
    error_message = "Maintenance window must be in format ddd:HH:MM-ddd:HH:MM."
  }
}

# DMS Configuration
variable "dms_replication_instance_class" {
  description = "DMS replication instance class"
  type        = string
  default     = "dms.t3.medium"
  
  validation {
    condition     = can(regex("^dms\\.", var.dms_replication_instance_class))
    error_message = "DMS instance class must start with 'dms.'."
  }
}

variable "dms_allocated_storage" {
  description = "Storage allocated to DMS replication instance (GB)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.dms_allocated_storage >= 20 && var.dms_allocated_storage <= 6144
    error_message = "DMS allocated storage must be between 20 and 6144 GB."
  }
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

# Source Database Configuration (for DMS endpoints)
variable "source_db_engine" {
  description = "Source database engine type"
  type        = string
  default     = "mysql"
  
  validation {
    condition     = contains(["mysql", "postgres", "oracle", "sqlserver"], var.source_db_engine)
    error_message = "Source database engine must be one of: mysql, postgres, oracle, sqlserver."
  }
}

variable "source_db_server_name" {
  description = "Source database server hostname or IP address"
  type        = string
  default     = "source-db.example.com"
}

variable "source_db_port" {
  description = "Source database port"
  type        = number
  default     = 3306
  
  validation {
    condition     = var.source_db_port > 0 && var.source_db_port <= 65535
    error_message = "Port must be between 1 and 65535."
  }
}

variable "source_db_username" {
  description = "Source database username"
  type        = string
  default     = "dms_user"
}

variable "source_db_password" {
  description = "Source database password"
  type        = string
  sensitive   = true
  default     = "change-me-in-production"
}

variable "source_db_name" {
  description = "Source database name"
  type        = string
  default     = "sourcedb"
}

# Route 53 Configuration
variable "route53_zone_name" {
  description = "Route 53 hosted zone name for DNS cutover"
  type        = string
  default     = "db.example.com"
  
  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.route53_zone_name))
    error_message = "Zone name must be a valid domain name."
  }
}

variable "route53_record_name" {
  description = "DNS record name for database endpoint"
  type        = string
  default     = "app-db"
}

variable "route53_record_ttl" {
  description = "TTL for DNS records (lower values enable faster cutover)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.route53_record_ttl >= 1 && var.route53_record_ttl <= 86400
    error_message = "TTL must be between 1 and 86400 seconds."
  }
}

# Security Configuration
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to Aurora"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "enable_encryption" {
  description = "Enable encryption at rest for Aurora"
  type        = bool
  default     = true
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights for Aurora"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition     = contains([7, 31, 93, 186, 372, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention period must be one of: 7, 31, 93, 186, 372, 731 days."
  }
}

# Migration Configuration
variable "migration_type" {
  description = "DMS migration type"
  type        = string
  default     = "full-load-and-cdc"
  
  validation {
    condition     = contains(["full-load", "cdc", "full-load-and-cdc"], var.migration_type)
    error_message = "Migration type must be one of: full-load, cdc, full-load-and-cdc."
  }
}

variable "enable_validation" {
  description = "Enable data validation during migration"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for Aurora"
  type        = bool
  default     = true
}

# Resource Naming
variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.resource_suffix))
    error_message = "Resource suffix must contain only lowercase letters, numbers, and hyphens."
  }
}